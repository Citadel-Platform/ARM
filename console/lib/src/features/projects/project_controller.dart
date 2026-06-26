import 'dart:async';
import 'dart:collection';

import 'package:arm_console/src/features/arm_data/data/arm_telemetry_gateway.dart';
import 'package:arm_console/src/features/auth/auth_controller.dart';
import 'package:arm_console/src/features/auth/domain/auth_models.dart';
import 'package:arm_console/src/features/projects/data/project_repository.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:arm_console/src/features/projects/project_connection_validator.dart';
import 'package:flutter/foundation.dart';

enum ProjectLoadState { loading, ready, error }

class ProjectController extends ChangeNotifier {
  ProjectController({
    required AuthController authController,
    required ProjectRepository projectRepository,
    required ProjectConnectionValidator connectionValidator,
    ArmTelemetryGateway? telemetryGateway,
  }) : this._(
         authController,
         projectRepository,
         connectionValidator,
         telemetryGateway,
       );

  ProjectController._(
    this._authController,
    this._projectRepository,
    this._connectionValidator, [
    this._telemetryGateway,
  ]);

  final AuthController _authController;
  final ProjectRepository _projectRepository;
  final ProjectConnectionValidator _connectionValidator;
  final ArmTelemetryGateway? _telemetryGateway;

  StreamSubscription<List<ConsoleProject>>? _projectSubscription;
  List<ConsoleProject> _allProjects = const <ConsoleProject>[];
  List<ConsoleProject> _visibleProjects = const <ConsoleProject>[];
  ProjectLoadState _loadState = ProjectLoadState.loading;
  String? _selectedProjectId;
  String? _errorMessage;
  String? _noticeMessage;
  ProjectConnectionStatus _noticeStatus = ProjectConnectionStatus.unknown;
  ProjectValidationResult? _latestValidation;
  String? _latestValidationSignature;
  bool _isSaving = false;
  bool _isValidating = false;
  bool _started = false;
  bool _isTelemetryScopeLoading = false;
  Set<String> _telemetryReadableProjectIds = <String>{};
  Map<String, String> _telemetryBlockedProjectMessages = <String, String>{};
  int _telemetryProbeRevision = 0;
  String? _projectSubscriptionSignature;

  AuthSession get _session => _authController.session;
  static final ArmTelemetryGateway _defaultTelemetryGateway =
      FirebaseArmTelemetryGateway();

  ProjectLoadState get loadState => _loadState;
  bool get isSaving => _isSaving;
  bool get isValidating => _isValidating;
  bool get isTelemetryScopeLoading => _isTelemetryScopeLoading;
  String? get errorMessage => _errorMessage;
  String? get noticeMessage => _noticeMessage;
  ProjectConnectionStatus get noticeStatus => _noticeStatus;
  ProjectValidationResult? get latestValidation => _latestValidation;
  String? get latestValidationSignature => _latestValidationSignature;

  bool get canManageProjects => _session.isSuperuser;
  bool get canSelectAll => _session.isSuperuser;
  bool get isAllProjectsSelected => canSelectAll && _selectedProjectId == null;
  bool get hasProjects => _visibleProjects.isNotEmpty;
  bool get hasTelemetryRestrictedProjects =>
      _telemetryBlockedProjectMessages.isNotEmpty;
  bool get canEditCurrentProjectData =>
      _session.canWriteProject(_selectedProjectId ?? '');

  String get accessLabel {
    return switch (_session.role) {
      AuthRole.superuser => 'Superuser',
      AuthRole.developer => 'Developer',
      AuthRole.viewer => 'Viewer',
      null => 'Unknown',
    };
  }

  UnmodifiableListView<ConsoleProject> get visibleProjects =>
      UnmodifiableListView<ConsoleProject>(_visibleProjects);

  UnmodifiableListView<ConsoleProject> get telemetryProjects =>
      UnmodifiableListView<ConsoleProject>(
        _visibleProjects.where(_canReadTelemetryForProject).toList(),
      );

  String? get telemetryRestrictionMessage {
    if (_telemetryBlockedProjectMessages.isEmpty) {
      return null;
    }
    final List<String> blockedSummaries = _visibleProjects
        .where(
          (ConsoleProject project) =>
              _telemetryBlockedProjectMessages.containsKey(project.id),
        )
        .map((ConsoleProject project) {
          final String? rawMessage =
              _telemetryBlockedProjectMessages[project.id];
          final String normalizedMessage = rawMessage == null
              ? ''
              : rawMessage.trim().replaceAll(RegExp(r'\s+'), ' ');
          return normalizedMessage.isEmpty
              ? project.name
              : '${project.name} ($normalizedMessage)';
        })
        .toList();
    if (blockedSummaries.isEmpty) {
      return 'Some monitored projects rejected telemetry reads.';
    }
    return 'Telemetry reads are currently unavailable for ${blockedSummaries.join(', ')}.';
  }

  ConsoleProject? get selectedProject {
    if (_selectedProjectId == null) {
      return null;
    }
    for (final ConsoleProject project in _visibleProjects) {
      if (project.id == _selectedProjectId) {
        return project;
      }
    }
    return null;
  }

  String? get selectedProjectId => _selectedProjectId;

  String get selectionLabel {
    if (_loadState == ProjectLoadState.loading) {
      return 'Loading projects';
    }
    if (isAllProjectsSelected) {
      return 'All projects';
    }
    return selectedProject?.shellLabel ??
        (_visibleProjects.isEmpty ? 'No assigned projects' : 'Select project');
  }

  void start() {
    if (_started) {
      return;
    }
    _started = true;

    _authController.addListener(_handleAuthChanged);
    _resubscribeToProjects();
    _handleAuthChanged();
  }

  void selectProject(String? projectId) {
    if (projectId == null && !canSelectAll) {
      return;
    }
    if (projectId == _selectedProjectId) {
      return;
    }

    _selectedProjectId = projectId;
    notifyListeners();
  }

  Future<ProjectValidationResult> validateDraft(ProjectDraft draft) async {
    final List<String> errors = draft.validationErrors();
    if (errors.isNotEmpty) {
      final ProjectValidationResult result =
          ProjectValidationResult.fromFormErrors(errors);
      _latestValidation = result;
      _latestValidationSignature = draft.validationSignature;
      _noticeMessage = result.summary;
      _noticeStatus = result.status;
      notifyListeners();
      return result;
    }

    _isValidating = true;
    _noticeMessage = null;
    notifyListeners();

    try {
      final ProjectValidationResult result = await _connectionValidator
          .validate(draft);
      _latestValidation = result;
      _latestValidationSignature = draft.validationSignature;
      _noticeMessage = result.summary;
      _noticeStatus = result.status;
      return result;
    } finally {
      _isValidating = false;
      notifyListeners();
    }
  }

  Future<bool> saveDraft(ProjectDraft draft) async {
    if (!canManageProjects) {
      _noticeMessage = 'Only the superuser can change the project directory.';
      _noticeStatus = ProjectConnectionStatus.failed;
      notifyListeners();
      return false;
    }

    final ProjectValidationResult validation;
    if (_latestValidationSignature == draft.validationSignature &&
        _latestValidation != null) {
      validation = _latestValidation!;
    } else {
      validation = await validateDraft(draft);
    }

    if (validation.isFailure) {
      return false;
    }

    _isSaving = true;
    _noticeMessage = null;
    notifyListeners();

    try {
      final ConsoleProject? existingProject = _findProjectById(draft.id);
      final ConsoleProject project = draft.toProject(
        connectionState: validation.connectionState,
        createdAt: existingProject?.createdAt,
        updatedAt: existingProject?.updatedAt,
        createdBy: existingProject?.createdBy,
        updatedBy: existingProject?.updatedBy,
      );

      await _projectRepository.upsertProject(
        project,
        actorEmail: _session.email ?? 'unknown@arm-console.local',
      );

      _selectedProjectId = project.id;
      _noticeMessage = 'Saved ${project.name} to the console project registry.';
      _noticeStatus = ProjectConnectionStatus.healthy;
      return true;
    } catch (error) {
      _noticeMessage = 'Project save failed: $error';
      _noticeStatus = ProjectConnectionStatus.failed;
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  ConsoleProject? projectForSelection(String? projectId) {
    if (projectId == null) {
      return null;
    }
    return _findVisibleProjectById(projectId);
  }

  bool canReadTelemetryForProjectId(String? projectId) {
    if (projectId == null) {
      return false;
    }
    final ConsoleProject? project = _findVisibleProjectById(projectId);
    return project != null && _canReadTelemetryForProject(project);
  }

  bool hasCurrentValidation(ProjectDraft draft) {
    return _latestValidationSignature == draft.validationSignature &&
        _latestValidation != null;
  }

  void clearNotice() {
    if (_noticeMessage == null) {
      return;
    }
    _noticeMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _projectSubscription?.cancel();
    _authController.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleProjectsUpdated(List<ConsoleProject> projects) {
    _allProjects = List<ConsoleProject>.from(projects);
    _loadState = ProjectLoadState.ready;
    _errorMessage = null;
    _syncVisibleProjects();
  }

  void _handleAuthChanged() {
    _resubscribeToProjects();
    if (_session.stage == AuthStage.bootstrapping) {
      _loadState = ProjectLoadState.loading;
      notifyListeners();
      return;
    }

    _syncVisibleProjects();
  }

  void _resubscribeToProjects() {
    final _ProjectSubscriptionScope scope = _subscriptionScopeForSession();
    if (scope.signature == _projectSubscriptionSignature) {
      return;
    }
    _projectSubscriptionSignature = scope.signature;
    unawaited(_projectSubscription?.cancel());
    _projectSubscription = null;

    if (!scope.shouldSubscribe) {
      _allProjects = const <ConsoleProject>[];
      _loadState = _session.stage == AuthStage.bootstrapping
          ? ProjectLoadState.loading
          : ProjectLoadState.ready;
      _errorMessage = null;
      return;
    }

    _loadState = ProjectLoadState.loading;
    _errorMessage = null;
    _projectSubscription = _projectRepository
        .watchProjects(projectIds: scope.projectIds)
        .listen(
          _handleProjectsUpdated,
          onError: (Object error, StackTrace stackTrace) {
            _loadState = ProjectLoadState.error;
            _errorMessage = 'Project directory could not be loaded: $error';
            notifyListeners();
          },
        );
  }

  void _syncVisibleProjects() {
    if (!_session.isAuthenticated) {
      _visibleProjects = const <ConsoleProject>[];
      _selectedProjectId = null;
      _clearTelemetryScope();
      notifyListeners();
      return;
    }

    if (_session.isSuperuser) {
      _visibleProjects = List<ConsoleProject>.from(_allProjects);
    } else {
      _visibleProjects = _allProjects
          .where(
            (ConsoleProject project) => _session.canReadProject(project.id),
          )
          .toList();
    }

    final bool selectionExists =
        _selectedProjectId != null &&
        _visibleProjects.any(
          (ConsoleProject project) => project.id == _selectedProjectId,
        );
    if (!selectionExists) {
      _selectedProjectId = switch (_session.role) {
        AuthRole.superuser => null,
        AuthRole.developer || AuthRole.viewer =>
          _visibleProjects.isEmpty ? null : _visibleProjects.first.id,
        null => null,
      };
    }

    unawaited(_refreshTelemetryScope());
    notifyListeners();
  }

  Future<void> _refreshTelemetryScope() async {
    final int revision = ++_telemetryProbeRevision;
    final List<ConsoleProject> currentVisibleProjects =
        List<ConsoleProject>.from(_visibleProjects);
    if (!_session.isAuthenticated || currentVisibleProjects.isEmpty) {
      _clearTelemetryScope();
      notifyListeners();
      return;
    }

    final List<ArmMonitoredProject> remoteProjects = currentVisibleProjects
        .where(
          (ConsoleProject project) =>
              isRemoteCapableConfig(project.firebaseConfig),
        )
        .map(
          (ConsoleProject project) => ArmMonitoredProject(
            id: project.id,
            name: project.name,
            environmentLabel: project.environmentLabel,
            firebaseConfig: project.firebaseConfig,
          ),
        )
        .toList();

    if (remoteProjects.isEmpty) {
      _telemetryReadableProjectIds = currentVisibleProjects
          .map((ConsoleProject project) => project.id)
          .toSet();
      _telemetryBlockedProjectMessages = <String, String>{};
      _isTelemetryScopeLoading = false;
      notifyListeners();
      return;
    }

    _isTelemetryScopeLoading = true;
    notifyListeners();

    try {
      final List<ArmProjectAccessResult> results =
          await (_telemetryGateway ?? _defaultTelemetryGateway)
              .probeProjectAccess(projects: remoteProjects);
      if (revision != _telemetryProbeRevision) {
        return;
      }

      final Set<String> readableIds = currentVisibleProjects
          .where(
            (ConsoleProject project) =>
                !isRemoteCapableConfig(project.firebaseConfig),
          )
          .map((ConsoleProject project) => project.id)
          .toSet();
      final Map<String, String> blockedMessages = <String, String>{};
      for (final ArmProjectAccessResult result in results) {
        if (result.canReadTelemetry) {
          readableIds.add(result.project.id);
        } else {
          blockedMessages[result.project.id] =
              result.errorMessage ?? 'Telemetry reads were rejected.';
        }
      }

      _telemetryReadableProjectIds = readableIds;
      _telemetryBlockedProjectMessages = blockedMessages;
      _isTelemetryScopeLoading = false;
      notifyListeners();
    } catch (error) {
      if (revision != _telemetryProbeRevision) {
        return;
      }
      _telemetryReadableProjectIds = currentVisibleProjects
          .where(
            (ConsoleProject project) =>
                !isRemoteCapableConfig(project.firebaseConfig),
          )
          .map((ConsoleProject project) => project.id)
          .toSet();
      _telemetryBlockedProjectMessages = <String, String>{
        for (final ArmMonitoredProject project in remoteProjects)
          project.id: '$error',
      };
      _isTelemetryScopeLoading = false;
      notifyListeners();
    }
  }

  void _clearTelemetryScope() {
    _telemetryReadableProjectIds = <String>{};
    _telemetryBlockedProjectMessages = <String, String>{};
    _isTelemetryScopeLoading = false;
  }

  bool _canReadTelemetryForProject(ConsoleProject project) {
    if (!isRemoteCapableConfig(project.firebaseConfig)) {
      return true;
    }
    return _telemetryReadableProjectIds.contains(project.id);
  }

  ConsoleProject? _findProjectById(String id) {
    for (final ConsoleProject project in _allProjects) {
      if (project.id == id) {
        return project;
      }
    }
    return null;
  }

  ConsoleProject? _findVisibleProjectById(String id) {
    for (final ConsoleProject project in _visibleProjects) {
      if (project.id == id) {
        return project;
      }
    }
    return null;
  }
}

class _ProjectSubscriptionScope {
  const _ProjectSubscriptionScope({
    required this.signature,
    required this.shouldSubscribe,
    this.projectIds,
  });

  final String signature;
  final bool shouldSubscribe;
  final Set<String>? projectIds;
}

extension on ProjectController {
  _ProjectSubscriptionScope _subscriptionScopeForSession() {
    if (_session.stage == AuthStage.bootstrapping) {
      return const _ProjectSubscriptionScope(
        signature: 'bootstrapping',
        shouldSubscribe: false,
      );
    }
    if (!_session.isAuthenticated) {
      return const _ProjectSubscriptionScope(
        signature: 'signed-out',
        shouldSubscribe: false,
      );
    }
    if (_session.role == AuthRole.superuser) {
      return const _ProjectSubscriptionScope(
        signature: 'superuser:all',
        shouldSubscribe: true,
      );
    }

    final List<String> projectIds = _session.allowedProjectIds.toList()..sort();
    return _ProjectSubscriptionScope(
      signature: 'scoped:${projectIds.join(",")}',
      shouldSubscribe: projectIds.isNotEmpty,
      projectIds: projectIds.toSet(),
    );
  }
}
