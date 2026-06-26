import 'package:arm_console/src/features/auth/domain/auth_models.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/ui/console_primitives.dart';
import 'package:flutter/material.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({
    required this.controller,
    required this.authSession,
    super.key,
  });

  final ProjectController controller;
  final AuthSession authSession;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final TextEditingController _projectIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _appIdController = TextEditingController();
  final TextEditingController _messagingSenderIdController =
      TextEditingController();
  final TextEditingController _firebaseProjectIdController =
      TextEditingController();
  final TextEditingController _authDomainController = TextEditingController();
  final TextEditingController _databaseUrlController = TextEditingController();
  final TextEditingController _storageBucketController =
      TextEditingController();
  final TextEditingController _measurementIdController =
      TextEditingController();
  final TextEditingController _androidClientIdController =
      TextEditingController();
  final TextEditingController _iosClientIdController = TextEditingController();
  final TextEditingController _iosBundleIdController = TextEditingController();
  final TextEditingController _developerEmailController =
      TextEditingController();
  final TextEditingController _viewerEmailController = TextEditingController();

  ProjectEnvironment _environment = ProjectEnvironment.production;
  List<String> _developerEmails = const <String>[];
  List<String> _viewerEmails = const <String>[];
  bool _isHydrating = false;
  bool _projectIdEditedManually = false;
  String? _activeProjectId;
  String? _developerEmailError;
  String? _viewerEmailError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _nameController.addListener(_syncProjectIdFromName);
    _projectIdController.addListener(_trackProjectIdEditing);
    _hydrateForSelection(widget.controller.selectedProject);
  }

  @override
  void didUpdateWidget(covariant ProjectsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _hydrateForSelection(widget.controller.selectedProject);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _projectIdController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _apiKeyController.dispose();
    _appIdController.dispose();
    _messagingSenderIdController.dispose();
    _firebaseProjectIdController.dispose();
    _authDomainController.dispose();
    _databaseUrlController.dispose();
    _storageBucketController.dispose();
    _measurementIdController.dispose();
    _androidClientIdController.dispose();
    _iosClientIdController.dispose();
    _iosBundleIdController.dispose();
    _developerEmailController.dispose();
    _viewerEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) {
        return ConsolePageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ConsoleSectionHeader(
                eyebrow: 'Registry',
                title: 'Projects',
                description:
                    'Register monitored projects, validate their Firebase read path, and maintain developer and viewer access without ever writing to ARM evidence data.',
                actions: widget.controller.canManageProjects
                    ? <Widget>[
                        FilledButton.icon(
                          onPressed: _startNewProject,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Register project'),
                        ),
                      ]
                    : null,
              ),
              const SizedBox(height: 24),
              ConsoleFilterBar(
                children: <Widget>[
                  _InfoPill(
                    label: 'Current scope',
                    value: widget.controller.selectionLabel,
                  ),
                  _InfoPill(
                    label: 'Visible projects',
                    value: '${widget.controller.visibleProjects.length}',
                  ),
                  _InfoPill(
                    label: 'Access',
                    value: widget.controller.accessLabel,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _ReadOnlyGuardrailBanner(
                canManageProjects: widget.controller.canManageProjects,
              ),
              const SizedBox(height: 24),
              _buildBody(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (widget.controller.loadState) {
      ProjectLoadState.loading => const SizedBox(
        height: 360,
        child: ConsoleStateView.loading(
          title: 'Loading project directory',
          message:
              'Preparing configured projects, access scopes, and connection state.',
        ),
      ),
      ProjectLoadState.error => SizedBox(
        height: 360,
        child: ConsoleStateView.error(
          title: 'Project directory unavailable',
          message:
              widget.controller.errorMessage ??
              'The project registry could not be loaded.',
        ),
      ),
      ProjectLoadState.ready => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool split = constraints.maxWidth >= 1120;
          final Widget listPane = _ProjectDirectoryPane(
            controller: widget.controller,
            onSelect: (ConsoleProject project) {
              widget.controller.selectProject(project.id);
              _hydrateForSelection(project);
            },
          );
          final Widget detailPane = widget.controller.canManageProjects
              ? _ProjectEditorPane(
                  projectIdController: _projectIdController,
                  nameController: _nameController,
                  descriptionController: _descriptionController,
                  apiKeyController: _apiKeyController,
                  appIdController: _appIdController,
                  messagingSenderIdController: _messagingSenderIdController,
                  firebaseProjectIdController: _firebaseProjectIdController,
                  authDomainController: _authDomainController,
                  databaseUrlController: _databaseUrlController,
                  storageBucketController: _storageBucketController,
                  measurementIdController: _measurementIdController,
                  androidClientIdController: _androidClientIdController,
                  iosClientIdController: _iosClientIdController,
                  iosBundleIdController: _iosBundleIdController,
                  developerEmailController: _developerEmailController,
                  viewerEmailController: _viewerEmailController,
                  environment: _environment,
                  developerEmails: _developerEmails,
                  viewerEmails: _viewerEmails,
                  developerEmailError: _developerEmailError,
                  viewerEmailError: _viewerEmailError,
                  activeProjectId: _activeProjectId,
                  controller: widget.controller,
                  onEnvironmentChanged: (ProjectEnvironment nextEnvironment) {
                    setState(() {
                      _environment = nextEnvironment;
                    });
                  },
                  onAddDeveloper: () =>
                      _addRoleEmail(ProjectAccessRole.developer),
                  onAddViewer: () => _addRoleEmail(ProjectAccessRole.viewer),
                  onRemoveDeveloper: (String email) {
                    _removeRoleEmail(ProjectAccessRole.developer, email);
                  },
                  onRemoveViewer: (String email) {
                    _removeRoleEmail(ProjectAccessRole.viewer, email);
                  },
                  onValidate: _validateDraft,
                  onSave: _saveDraft,
                  currentDraft: _currentDraft(),
                )
              : _ProjectReadOnlyPane(
                  project: widget.controller.selectedProject,
                  selectionLabel: widget.controller.selectionLabel,
                );

          if (split) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 5, child: listPane),
                const SizedBox(width: 16),
                Expanded(flex: 7, child: detailPane),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              listPane,
              const SizedBox(height: 16),
              detailPane,
            ],
          );
        },
      ),
    };
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }

    final ConsoleProject? selectedProject = widget.controller.selectedProject;
    if (selectedProject?.id == _activeProjectId) {
      return;
    }

    if (widget.controller.selectedProjectId == null &&
        _activeProjectId == null) {
      return;
    }

    if (_draftHasUnsavedChanges() && widget.controller.canManageProjects) {
      return;
    }

    _hydrateForSelection(selectedProject);
  }

  void _syncProjectIdFromName() {
    if (_isHydrating || _projectIdEditedManually) {
      return;
    }

    final String slug = normalizeProjectId(_nameController.text);
    if (_projectIdController.text == slug) {
      return;
    }

    _isHydrating = true;
    _projectIdController.text = slug;
    _isHydrating = false;
  }

  void _trackProjectIdEditing() {
    if (_isHydrating) {
      return;
    }
    _projectIdEditedManually = true;
  }

  void _hydrateForSelection(ConsoleProject? project) {
    _isHydrating = true;
    final ProjectDraft draft = project == null
        ? ProjectDraft.empty()
        : ProjectDraft.fromProject(project);

    _projectIdController.text = draft.id;
    _nameController.text = draft.name;
    _descriptionController.text = draft.description;
    _apiKeyController.text = draft.firebaseConfig.apiKey;
    _appIdController.text = draft.firebaseConfig.appId;
    _messagingSenderIdController.text = draft.firebaseConfig.messagingSenderId;
    _firebaseProjectIdController.text = draft.firebaseConfig.projectId;
    _authDomainController.text = draft.firebaseConfig.authDomain ?? '';
    _databaseUrlController.text = draft.firebaseConfig.databaseUrl ?? '';
    _storageBucketController.text = draft.firebaseConfig.storageBucket ?? '';
    _measurementIdController.text = draft.firebaseConfig.measurementId ?? '';
    _androidClientIdController.text =
        draft.firebaseConfig.androidClientId ?? '';
    _iosClientIdController.text = draft.firebaseConfig.iosClientId ?? '';
    _iosBundleIdController.text = draft.firebaseConfig.iosBundleId ?? '';

    setState(() {
      _environment = draft.environment;
      _developerEmails = List<String>.from(draft.developerEmails);
      _viewerEmails = List<String>.from(draft.viewerEmails);
      _developerEmailError = null;
      _viewerEmailError = null;
      _activeProjectId = project?.id;
      _projectIdEditedManually = project != null;
    });
    _isHydrating = false;
  }

  void _startNewProject() {
    widget.controller.selectProject(null);
    _hydrateForSelection(null);
  }

  Future<void> _validateDraft() async {
    final ProjectDraft draft = _currentDraft();
    await widget.controller.validateDraft(draft);
  }

  Future<void> _saveDraft() async {
    final ProjectDraft draft = _currentDraft();
    final bool saved = await widget.controller.saveDraft(draft);
    if (!saved || !mounted) {
      return;
    }

    _projectIdEditedManually = true;
    _activeProjectId = draft.id;
  }

  ProjectDraft _currentDraft() {
    return ProjectDraft(
      id: _projectIdController.text,
      name: _nameController.text,
      environment: _environment,
      description: _descriptionController.text,
      firebaseConfig: ProjectFirebaseConfig(
        apiKey: _apiKeyController.text,
        appId: _appIdController.text,
        messagingSenderId: _messagingSenderIdController.text,
        projectId: _firebaseProjectIdController.text,
        authDomain: _authDomainController.text,
        databaseUrl: _databaseUrlController.text,
        storageBucket: _storageBucketController.text,
        measurementId: _measurementIdController.text,
        androidClientId: _androidClientIdController.text,
        iosClientId: _iosClientIdController.text,
        iosBundleId: _iosBundleIdController.text,
      ),
      developerEmails: _developerEmails,
      viewerEmails: _viewerEmails,
    );
  }

  bool _draftHasUnsavedChanges() {
    if (_activeProjectId == null &&
        _currentDraft().validationSignature.isEmpty) {
      return false;
    }
    final ConsoleProject? currentProject = widget.controller.selectedProject;
    if (currentProject == null) {
      return _currentDraft().validationSignature !=
          ProjectDraft.empty().validationSignature;
    }
    return _currentDraft().validationSignature !=
        ProjectDraft.fromProject(currentProject).validationSignature;
  }

  void _addRoleEmail(ProjectAccessRole role) {
    final TextEditingController controller = switch (role) {
      ProjectAccessRole.developer => _developerEmailController,
      ProjectAccessRole.viewer => _viewerEmailController,
    };
    final List<String> currentEmails = switch (role) {
      ProjectAccessRole.developer => _developerEmails,
      ProjectAccessRole.viewer => _viewerEmails,
    };
    final List<String> otherEmails = switch (role) {
      ProjectAccessRole.developer => _viewerEmails,
      ProjectAccessRole.viewer => _developerEmails,
    };
    final String normalizedEmail = normalizeEmail(controller.text);
    if (normalizedEmail.isEmpty) {
      setState(() {
        _setRoleEmailError(role, 'Enter an email address to add it.');
      });
      return;
    }
    if (!_emailPattern.hasMatch(normalizedEmail)) {
      setState(() {
        _setRoleEmailError(role, 'Use a valid email address.');
      });
      return;
    }
    if (currentEmails.contains(normalizedEmail)) {
      setState(() {
        _setRoleEmailError(
          role,
          'That email is already assigned to this role.',
        );
      });
      return;
    }
    if (otherEmails.contains(normalizedEmail)) {
      setState(() {
        _setRoleEmailError(
          role,
          'That email is already assigned to the other project role.',
        );
      });
      return;
    }

    setState(() {
      if (role == ProjectAccessRole.developer) {
        _developerEmails = <String>[..._developerEmails, normalizedEmail]
          ..sort();
        _developerEmailController.clear();
        _developerEmailError = null;
      } else {
        _viewerEmails = <String>[..._viewerEmails, normalizedEmail]..sort();
        _viewerEmailController.clear();
        _viewerEmailError = null;
      }
    });
  }

  void _removeRoleEmail(ProjectAccessRole role, String email) {
    setState(() {
      if (role == ProjectAccessRole.developer) {
        _developerEmails = _developerEmails
            .where((String item) => item != email)
            .toList();
      } else {
        _viewerEmails = _viewerEmails
            .where((String item) => item != email)
            .toList();
      }
    });
  }

  void _setRoleEmailError(ProjectAccessRole role, String? message) {
    if (role == ProjectAccessRole.developer) {
      _developerEmailError = message;
    } else {
      _viewerEmailError = message;
    }
  }
}

class _ProjectDirectoryPane extends StatelessWidget {
  const _ProjectDirectoryPane({
    required this.controller,
    required this.onSelect,
  });

  final ProjectController controller;
  final ValueChanged<ConsoleProject> onSelect;

  @override
  Widget build(BuildContext context) {
    if (controller.visibleProjects.isEmpty) {
      return ConsoleSurface(
        title: 'Configured projects',
        description:
            'The console project directory is empty. Add the first monitored project to start the registry.',
        child: SizedBox(
          height: 320,
          child: ConsoleStateView.empty(
            title: controller.canManageProjects
                ? 'No configured projects'
                : 'No assigned projects',
            message: controller.canManageProjects
                ? 'Create the first project entry to capture Firebase connection details and scoped access.'
                : 'Your account does not currently have any project entries in scope.',
          ),
        ),
      );
    }

    return ConsoleSurface(
      title: 'Configured projects',
      description:
          'Keep the active project obvious from the shell and use the directory to audit environment, access scope, and connection posture.',
      child: Column(
        children: <Widget>[
          for (final ConsoleProject project
              in controller.visibleProjects) ...<Widget>[
            _ProjectRow(
              project: project,
              isSelected: controller.selectedProjectId == project.id,
              onTap: () => onSelect(project),
            ),
            if (project != controller.visibleProjects.last)
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _ProjectEditorPane extends StatelessWidget {
  const _ProjectEditorPane({
    required this.projectIdController,
    required this.nameController,
    required this.descriptionController,
    required this.apiKeyController,
    required this.appIdController,
    required this.messagingSenderIdController,
    required this.firebaseProjectIdController,
    required this.authDomainController,
    required this.databaseUrlController,
    required this.storageBucketController,
    required this.measurementIdController,
    required this.androidClientIdController,
    required this.iosClientIdController,
    required this.iosBundleIdController,
    required this.developerEmailController,
    required this.viewerEmailController,
    required this.environment,
    required this.developerEmails,
    required this.viewerEmails,
    required this.developerEmailError,
    required this.viewerEmailError,
    required this.activeProjectId,
    required this.controller,
    required this.onEnvironmentChanged,
    required this.onAddDeveloper,
    required this.onAddViewer,
    required this.onRemoveDeveloper,
    required this.onRemoveViewer,
    required this.onValidate,
    required this.onSave,
    required this.currentDraft,
  });

  final TextEditingController projectIdController;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController apiKeyController;
  final TextEditingController appIdController;
  final TextEditingController messagingSenderIdController;
  final TextEditingController firebaseProjectIdController;
  final TextEditingController authDomainController;
  final TextEditingController databaseUrlController;
  final TextEditingController storageBucketController;
  final TextEditingController measurementIdController;
  final TextEditingController androidClientIdController;
  final TextEditingController iosClientIdController;
  final TextEditingController iosBundleIdController;
  final TextEditingController developerEmailController;
  final TextEditingController viewerEmailController;
  final ProjectEnvironment environment;
  final List<String> developerEmails;
  final List<String> viewerEmails;
  final String? developerEmailError;
  final String? viewerEmailError;
  final String? activeProjectId;
  final ProjectController controller;
  final ValueChanged<ProjectEnvironment> onEnvironmentChanged;
  final VoidCallback onAddDeveloper;
  final VoidCallback onAddViewer;
  final ValueChanged<String> onRemoveDeveloper;
  final ValueChanged<String> onRemoveViewer;
  final Future<void> Function() onValidate;
  final Future<void> Function() onSave;
  final ProjectDraft currentDraft;

  @override
  Widget build(BuildContext context) {
    final bool hasCurrentValidation = controller.hasCurrentValidation(
      currentDraft,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConsoleFormSection(
          title: activeProjectId == null
              ? 'Project registration'
              : 'Project configuration',
          description:
              'Capture the monitored project identity first so the shell and directory can refer to it consistently everywhere.',
          child: Column(
            children: <Widget>[
              _FormFieldRow(
                children: <_FieldSpec>[
                  _FieldSpec(
                    title: 'Project name',
                    child: TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        helperText:
                            'Shown in the shell switcher and project directory.',
                      ),
                    ),
                  ),
                  _FieldSpec(
                    title: 'Environment',
                    child: DropdownButtonFormField<ProjectEnvironment>(
                      initialValue: environment,
                      onChanged: (ProjectEnvironment? value) {
                        if (value != null) {
                          onEnvironmentChanged(value);
                        }
                      },
                      items: ProjectEnvironment.values
                          .map(
                            (ProjectEnvironment environment) =>
                                DropdownMenuItem<ProjectEnvironment>(
                                  value: environment,
                                  child: Text(environment.label),
                                ),
                          )
                          .toList(),
                      decoration: const InputDecoration(
                        labelText: 'Environment label',
                        helperText:
                            'Makes staging, development, and production scopes obvious at a glance.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FormFieldRow(
                children: <_FieldSpec>[
                  _FieldSpec(
                    title: 'Project id',
                    child: TextField(
                      controller: projectIdController,
                      decoration: const InputDecoration(
                        labelText: 'Registry id',
                        helperText:
                            'Lowercase letters, digits, and hyphens only.',
                      ),
                    ),
                  ),
                  _FieldSpec(
                    title: 'Monitored Firebase project id',
                    child: TextField(
                      controller: firebaseProjectIdController,
                      decoration: const InputDecoration(
                        labelText: 'Firebase project id',
                        helperText:
                            'Used when the console initializes a secondary Firebase app.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Operational notes',
                  helperText:
                      'Optional context for the team, such as ownership or rollout notes.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ConsoleFormSection(
          title: 'Firebase connection details',
          description:
              'These values are only used to initialize a read-only monitored-project app instance later. The console never writes to ARM telemetry, cases, screenshots, or snapshots.',
          child: Column(
            children: <Widget>[
              _FormFieldRow(
                children: <_FieldSpec>[
                  _FieldSpec(
                    title: 'API key',
                    child: TextField(
                      controller: apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'API key',
                        helperText: 'Required for monitored-project bootstrap.',
                      ),
                    ),
                  ),
                  _FieldSpec(
                    title: 'App id',
                    child: TextField(
                      controller: appIdController,
                      decoration: const InputDecoration(
                        labelText: 'App id',
                        helperText: 'Required for monitored-project bootstrap.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FormFieldRow(
                children: <_FieldSpec>[
                  _FieldSpec(
                    title: 'Messaging sender id',
                    child: TextField(
                      controller: messagingSenderIdController,
                      decoration: const InputDecoration(
                        labelText: 'Messaging sender id',
                        helperText: 'Required by Firebase options.',
                      ),
                    ),
                  ),
                  _FieldSpec(
                    title: 'Storage bucket',
                    child: TextField(
                      controller: storageBucketController,
                      decoration: const InputDecoration(
                        labelText: 'Storage bucket',
                        helperText:
                            'Optional now, but used for screenshot and evidence asset reads.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FormFieldRow(
                children: <_FieldSpec>[
                  _FieldSpec(
                    title: 'Auth domain',
                    child: TextField(
                      controller: authDomainController,
                      decoration: const InputDecoration(
                        labelText: 'Auth domain',
                        helperText: 'Optional web setting.',
                      ),
                    ),
                  ),
                  _FieldSpec(
                    title: 'Database URL',
                    child: TextField(
                      controller: databaseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Database URL',
                        helperText: 'Optional and only needed when relevant.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FormFieldRow(
                children: <_FieldSpec>[
                  _FieldSpec(
                    title: 'Measurement id',
                    child: TextField(
                      controller: measurementIdController,
                      decoration: const InputDecoration(
                        labelText: 'Measurement id',
                        helperText: 'Optional web analytics field.',
                      ),
                    ),
                  ),
                  _FieldSpec(
                    title: 'Android client id',
                    child: TextField(
                      controller: androidClientIdController,
                      decoration: const InputDecoration(
                        labelText: 'Android client id',
                        helperText: 'Optional mobile OAuth setting.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FormFieldRow(
                children: <_FieldSpec>[
                  _FieldSpec(
                    title: 'iOS client id',
                    child: TextField(
                      controller: iosClientIdController,
                      decoration: const InputDecoration(
                        labelText: 'iOS client id',
                        helperText: 'Optional mobile OAuth setting.',
                      ),
                    ),
                  ),
                  _FieldSpec(
                    title: 'iOS bundle id',
                    child: TextField(
                      controller: iosBundleIdController,
                      decoration: const InputDecoration(
                        labelText: 'iOS bundle id',
                        helperText: 'Optional iOS bootstrap setting.',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ConsoleFormSection(
          title: 'Project access',
          description:
              'Assign project-scoped developers and viewers explicitly. Duplicate or malformed emails are rejected before save, and the same email cannot hold both roles for one project.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _AccessRoleEditor(
                title: 'Developers',
                description:
                    'Project-scoped developers can work with editable project data when those flows are introduced.',
                controller: developerEmailController,
                labelText: 'Developer email',
                helperText:
                    'Leave empty when only the superuser should have write-level access.',
                errorText: developerEmailError,
                emails: developerEmails,
                emptyMessage:
                    'No project-scoped developers assigned yet. The superuser still keeps full access.',
                onSubmitted: onAddDeveloper,
                onAdd: onAddDeveloper,
                onRemove: onRemoveDeveloper,
              ),
              const SizedBox(height: 16),
              _AccessRoleEditor(
                title: 'Viewers',
                description:
                    'Viewers can inspect assigned projects but stay read-only.',
                controller: viewerEmailController,
                labelText: 'Viewer email',
                helperText:
                    'Use this for stakeholders who need project visibility without edit rights.',
                errorText: viewerEmailError,
                emails: viewerEmails,
                emptyMessage:
                    'No viewers assigned yet. Add them only when a stakeholder needs read-only access.',
                onSubmitted: onAddViewer,
                onAdd: onAddViewer,
                onRemove: onRemoveViewer,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ConsoleSurface(
          title: 'Validation and save review',
          description:
              'Validate the connection before saving so failures are actionable. Warnings allow save when the read path is usable but optional checks still need follow-up.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SummaryRow(
                label: 'Scope summary',
                value:
                    '${currentDraft.name.trim().isEmpty ? 'Unnamed project' : currentDraft.name.trim()} · ${environment.label}',
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Registry id',
                value: normalizeProjectId(currentDraft.id).isEmpty
                    ? 'Pending'
                    : normalizeProjectId(currentDraft.id),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Scoped access',
                value: _roleSummary(
                  developerEmails: developerEmails,
                  viewerEmails: viewerEmails,
                ),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Read-only posture',
                value:
                    'This setup never writes to monitored-project telemetry or evidence.',
              ),
              const SizedBox(height: 20),
              if (controller.noticeMessage != null) ...<Widget>[
                _ValidationBanner(
                  status: controller.noticeStatus,
                  message: controller.noticeMessage!,
                ),
                const SizedBox(height: 16),
              ],
              if (hasCurrentValidation &&
                  controller.latestValidation != null) ...<Widget>[
                _ValidationChecks(result: controller.latestValidation!),
                const SizedBox(height: 16),
              ],
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: controller.isValidating ? null : onValidate,
                    icon: controller.isValidating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined),
                    label: const Text('Validate connection'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: controller.isSaving ? null : onSave,
                    icon: controller.isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      activeProjectId == null ? 'Save project' : 'Save changes',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProjectReadOnlyPane extends StatelessWidget {
  const _ProjectReadOnlyPane({
    required this.project,
    required this.selectionLabel,
  });

  final ConsoleProject? project;
  final String selectionLabel;

  @override
  Widget build(BuildContext context) {
    if (project == null) {
      return ConsoleSurface(
        title: 'Project details',
        description:
            'Project-scoped developer and viewer accounts can inspect only their assigned projects.',
        child: SizedBox(
          height: 280,
          child: ConsoleStateView.noAccess(
            title: 'No project selected',
            message:
                'Pick one of your assigned projects from the shell switcher to inspect its configuration summary.',
          ),
        ),
      );
    }

    final ConsoleProject selectedProject = project!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConsoleSurface(
          title: 'Project details',
          description:
              'Configuration is visible here for auditability, but only the superuser can modify the registry and access assignments.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SummaryRow(label: 'Selected scope', value: selectionLabel),
              const SizedBox(height: 12),
              _SummaryRow(label: 'Registry id', value: selectedProject.id),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Environment',
                value: selectedProject.environmentLabel,
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Scoped access',
                value: _roleSummary(
                  developerEmails: selectedProject.developerEmails,
                  viewerEmails: selectedProject.viewerEmails,
                ),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Developer emails',
                value: _joinedEmails(selectedProject.developerEmails),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Viewer emails',
                value: _joinedEmails(selectedProject.viewerEmails),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Connection posture',
                value: selectedProject.connectionState.status.label,
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Read-only posture',
                value:
                    'ARM Console reads telemetry, cases, screenshots, and snapshots without mutating evidence.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ConsoleSurface(
          title: 'Firebase connection summary',
          description:
              'These values are shown for transparency so project-scoped users can confirm the expected monitored project.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SummaryRow(
                label: 'Firebase project id',
                value: selectedProject.firebaseConfig.projectId,
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Storage bucket',
                value:
                    selectedProject.firebaseConfig.storageBucket ??
                    'Not configured',
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Last checked',
                value: _formatDateTime(
                  selectedProject.connectionState.checkedAt,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.isSelected,
    required this.onTap,
  });

  final ConsoleProject project;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color selectedColor = colorScheme.primaryContainer.withValues(
      alpha: 0.62,
    );
    final String? description = project.description?.trim();
    final bool hasDescription = description?.isNotEmpty ?? false;

    return Material(
      color: isSelected ? selectedColor : Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.folder_outlined,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      project.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${project.environmentLabel} · ${project.id}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (hasDescription) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _StatusChip(
                        label: project.scopeLabel,
                        tone: _chipToneForScope(project),
                      ),
                      _StatusChip(
                        label: project.connectionState.status.label,
                        tone: _chipToneForConnection(
                          project.connectionState.status,
                        ),
                      ),
                    ],
                  ),
                  if (isSelected) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'Selected',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _ChipTone _chipToneForScope(ConsoleProject project) {
    return project.developerEmails.isEmpty && project.viewerEmails.isEmpty
        ? _ChipTone.warning
        : _ChipTone.standard;
  }

  _ChipTone _chipToneForConnection(ProjectConnectionStatus status) {
    return switch (status) {
      ProjectConnectionStatus.healthy => _ChipTone.success,
      ProjectConnectionStatus.warning ||
      ProjectConnectionStatus.unknown => _ChipTone.warning,
      ProjectConnectionStatus.failed => _ChipTone.critical,
    };
  }
}

class _ValidationChecks extends StatelessWidget {
  const _ValidationChecks({required this.result});

  final ProjectValidationResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Latest validation',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _formatDateTime(result.checkedAt),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final ProjectValidationCheck check in result.checks) ...<Widget>[
          _ValidationCheckRow(check: check),
          if (check != result.checks.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ValidationCheckRow extends StatelessWidget {
  const _ValidationCheckRow({required this.check});

  final ProjectValidationCheck check;

  @override
  Widget build(BuildContext context) {
    final (_ChipTone tone, IconData icon) = switch (check.status) {
      ProjectValidationCheckStatus.success => (
        _ChipTone.success,
        Icons.check_circle_outline,
      ),
      ProjectValidationCheckStatus.warning => (
        _ChipTone.warning,
        Icons.warning_amber_rounded,
      ),
      ProjectValidationCheckStatus.failure => (
        _ChipTone.critical,
        Icons.error_outline_rounded,
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      check.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusChip(label: check.status.label, tone: tone),
                ],
              ),
              const SizedBox(height: 4),
              Text(check.message),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyGuardrailBanner extends StatelessWidget {
  const _ReadOnlyGuardrailBanner({required this.canManageProjects});

  final bool canManageProjects;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.shield_outlined,
              color: colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  canManageProjects
                      ? 'Registry writes only'
                      : 'Read-only access',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  canManageProjects
                      ? 'Project setup writes only to the console-owned registry and access index. Monitored-project telemetry, cases, screenshots, and snapshots stay strictly read-only.'
                      : 'This workspace is read-only for project-scoped sessions. Only the superuser can change the console registry or project access assignments.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationBanner extends StatelessWidget {
  const _ValidationBanner({required this.status, required this.message});

  final ProjectConnectionStatus status;
  final String message;

  @override
  Widget build(BuildContext context) {
    final (_ChipTone tone, IconData icon) = switch (status) {
      ProjectConnectionStatus.healthy => (
        _ChipTone.success,
        Icons.verified_outlined,
      ),
      ProjectConnectionStatus.warning || ProjectConnectionStatus.unknown => (
        _ChipTone.warning,
        Icons.warning_amber_rounded,
      ),
      ProjectConnectionStatus.failed => (
        _ChipTone.critical,
        Icons.error_outline_rounded,
      ),
    };
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color background = switch (tone) {
      _ChipTone.standard => colorScheme.surfaceContainerHighest,
      _ChipTone.success => const Color(0xFFE9F6EC),
      _ChipTone.warning => const Color(0xFFFFF4E5),
      _ChipTone.critical => const Color(0xFFFDECEA),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _AccessRoleEditor extends StatelessWidget {
  const _AccessRoleEditor({
    required this.title,
    required this.description,
    required this.controller,
    required this.labelText,
    required this.helperText,
    required this.errorText,
    required this.emails,
    required this.emptyMessage,
    required this.onSubmitted,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final String description;
  final TextEditingController controller;
  final String labelText;
  final String helperText;
  final String? errorText;
  final List<String> emails;
  final String emptyMessage;
  final VoidCallback onSubmitted;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: labelText,
                  helperText: helperText,
                  errorText: errorText,
                ),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (emails.isEmpty)
          Text(emptyMessage)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: emails
                .map(
                  (String email) => InputChip(
                    label: Text(email),
                    onDeleted: () => onRemove(email),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final ({Color background, Color foreground}) palette = switch (tone) {
      _ChipTone.standard => (
        background: Theme.of(context).colorScheme.surfaceContainerHighest,
        foreground: Theme.of(context).colorScheme.onSurface,
      ),
      _ChipTone.success => (
        background: const Color(0xFFE9F6EC),
        foreground: const Color(0xFF1F6A37),
      ),
      _ChipTone.warning => (
        background: const Color(0xFFFFF4E5),
        foreground: const Color(0xFF8D5C00),
      ),
      _ChipTone.critical => (
        background: const Color(0xFFFDECEA),
        foreground: const Color(0xFFB3261E),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum _ChipTone { standard, success, warning, critical }

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final TextTheme textTheme = Theme.of(context).textTheme;
        final ColorScheme colorScheme = Theme.of(context).colorScheme;
        final TextStyle labelStyle =
            textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ) ??
            const TextStyle();
        final TextStyle valueStyle =
            textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600) ??
            const TextStyle();

        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label.toUpperCase(), style: labelStyle),
              const SizedBox(height: 4),
              Text(value, style: valueStyle),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 160,
              child: Text(label.toUpperCase(), style: labelStyle),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(value, style: valueStyle)),
          ],
        );
      },
    );
  }
}

class _FormFieldRow extends StatelessWidget {
  const _FormFieldRow({required this.children});

  final List<_FieldSpec> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            children: <Widget>[
              for (int index = 0; index < children.length; index++) ...<Widget>[
                children[index].child,
                if (index != children.length - 1) const SizedBox(height: 16),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int index = 0; index < children.length; index++) ...<Widget>[
              Expanded(child: children[index].child),
              if (index != children.length - 1) const SizedBox(width: 16),
            ],
          ],
        );
      },
    );
  }
}

class _FieldSpec {
  const _FieldSpec({required this.title, required this.child});

  final String title;
  final Widget child;
}

String _roleSummary({
  required List<String> developerEmails,
  required List<String> viewerEmails,
}) {
  if (developerEmails.isEmpty && viewerEmails.isEmpty) {
    return 'Superuser only';
  }

  final List<String> parts = <String>[];
  if (developerEmails.isNotEmpty) {
    parts.add(
      '${developerEmails.length} developer${developerEmails.length == 1 ? '' : 's'}',
    );
  }
  if (viewerEmails.isNotEmpty) {
    parts.add(
      '${viewerEmails.length} viewer${viewerEmails.length == 1 ? '' : 's'}',
    );
  }
  return parts.join(' · ');
}

String _joinedEmails(List<String> emails) {
  if (emails.isEmpty) {
    return 'None assigned';
  }
  return emails.join(', ');
}

String _formatDateTime(DateTime? dateTime) {
  if (dateTime == null) {
    return 'Not yet checked';
  }
  final DateTime local = dateTime.toLocal();
  final String twoDigitMonth = local.month.toString().padLeft(2, '0');
  final String twoDigitDay = local.day.toString().padLeft(2, '0');
  final String twoDigitHour = local.hour.toString().padLeft(2, '0');
  final String twoDigitMinute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$twoDigitMonth-$twoDigitDay $twoDigitHour:$twoDigitMinute';
}

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
