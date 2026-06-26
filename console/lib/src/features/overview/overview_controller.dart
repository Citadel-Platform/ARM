import 'package:arm_console/src/features/overview/data/overview_repository.dart';
import 'package:arm_console/src/features/overview/domain/overview_models.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:flutter/foundation.dart';

enum OverviewLoadState { loading, ready, error }

class OverviewController extends ChangeNotifier {
  OverviewController({
    required ProjectController projectController,
    required OverviewRepository repository,
  }) : this._(projectController, repository);

  OverviewController._(this._projectController, this._repository);

  final ProjectController _projectController;
  final OverviewRepository _repository;

  OverviewQuery _query = const OverviewQuery(
    dateRange: OverviewDateRange.last24Hours,
    severityFilter: OverviewSeverityFilter.criticalAndHigh,
    scope: DashboardScope.allProjects(),
  );
  OverviewLoadState _loadState = OverviewLoadState.loading;
  OverviewSnapshot? _snapshot;
  String? _errorMessage;
  bool _started = false;

  OverviewQuery get query => _query;
  OverviewLoadState get loadState => _loadState;
  OverviewSnapshot? get snapshot => _snapshot;
  String? get errorMessage => _errorMessage;

  bool get isProjectScopeLocked => _projectController.canSelectAll == false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _projectController.addListener(_handleProjectScopeChanged);
    _syncScopeFromProjects();
    _refresh();
  }

  void setDateRange(OverviewDateRange dateRange) {
    if (_query.dateRange == dateRange) {
      return;
    }
    _query = _query.copyWith(dateRange: dateRange);
    _refresh();
  }

  void setSeverityFilter(OverviewSeverityFilter severityFilter) {
    if (_query.severityFilter == severityFilter) {
      return;
    }
    _query = _query.copyWith(severityFilter: severityFilter);
    _refresh();
  }

  String get scopeLabel => _projectController.selectionLabel;

  String get scopeDescription {
    if (_projectController.canManageProjects &&
        _projectController.isAllProjectsSelected) {
      return 'Cross-project view (superuser)';
    }
    return 'Project-scoped view (${_projectController.accessLabel.toLowerCase()})';
  }

  List<OverviewProjectReference> get activeProjects {
    final List<ConsoleProject> source = switch (_query.scope.isAllProjects) {
      true => _projectController.telemetryProjects.toList(),
      false =>
        _projectController.selectedProject == null ||
                !_projectController.canReadTelemetryForProjectId(
                  _projectController.selectedProjectId,
                )
            ? const <ConsoleProject>[]
            : <ConsoleProject>[_projectController.selectedProject!],
    };
    return source
        .map(
          (ConsoleProject project) => OverviewProjectReference(
            id: project.id,
            name: project.name,
            environmentLabel: project.environmentLabel,
            firebaseConfig: project.firebaseConfig,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _projectController.removeListener(_handleProjectScopeChanged);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_projectController.loadState == ProjectLoadState.loading) {
      _loadState = OverviewLoadState.loading;
      notifyListeners();
      return;
    }

    if (_projectController.isTelemetryScopeLoading) {
      _loadState = OverviewLoadState.loading;
      notifyListeners();
      return;
    }

    _loadState = OverviewLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _syncScopeFromProjects();
      _snapshot = await _repository.load(
        query: _query,
        activeProjects: activeProjects,
      );
      _loadState = OverviewLoadState.ready;
    } catch (error) {
      _errorMessage = 'Overview data could not be prepared: $error';
      _loadState = OverviewLoadState.error;
    }
    notifyListeners();
  }

  void _handleProjectScopeChanged() {
    _syncScopeFromProjects();
    _refresh();
  }

  void _syncScopeFromProjects() {
    final DashboardScope nextScope;
    if (_projectController.canSelectAll &&
        _projectController.isAllProjectsSelected) {
      nextScope = const DashboardScope.allProjects();
    } else {
      final String? selectedProjectId = _projectController.selectedProjectId;
      nextScope = DashboardScope.project(selectedProjectId);
    }
    _query = _query.copyWith(scope: nextScope);
  }
}
