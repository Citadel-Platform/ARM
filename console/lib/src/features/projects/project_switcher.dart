import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:flutter/material.dart';

class ProjectSwitcher extends StatelessWidget {
  const ProjectSwitcher({
    required this.controller,
    this.compact = false,
    super.key,
  });

  final ProjectController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final bool enabled =
            controller.canSelectAll || controller.visibleProjects.isNotEmpty;

        return PopupMenuButton<String?>(
          enabled: enabled,
          tooltip: 'Project scope',
          onSelected: controller.selectProject,
          itemBuilder: (BuildContext context) {
            return <PopupMenuEntry<String?>>[
              if (controller.canSelectAll)
                CheckedPopupMenuItem<String?>(
                  value: null,
                  checked: controller.isAllProjectsSelected,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('All projects'),
                      Text(
                        'Every visible project in the current scope',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ...controller.visibleProjects.map(
                (ConsoleProject project) => CheckedPopupMenuItem<String?>(
                  value: project.id,
                  checked: controller.selectedProjectId == project.id,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        project.name,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${project.environmentLabel} · ${project.scopeLabel}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (project.description?.trim().isNotEmpty ??
                          false) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          project.description!.trim(),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ];
          },
          child: _ProjectSwitcherChrome(
            compact: compact,
            selectionLabel: controller.selectionLabel,
            enabled: enabled,
            selectedProject: controller.selectedProject,
          ),
        );
      },
    );
  }
}

class _ProjectSwitcherChrome extends StatelessWidget {
  const _ProjectSwitcherChrome({
    required this.compact,
    required this.selectionLabel,
    required this.enabled,
    required this.selectedProject,
  });

  final bool compact;
  final String selectionLabel;
  final bool enabled;
  final ConsoleProject? selectedProject;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.72,
      duration: const Duration(milliseconds: 120),
      child: Container(
        constraints: BoxConstraints(
          minWidth: compact ? 0 : 220,
          maxWidth: compact ? 220 : 300,
        ),
        height: compact ? 48 : 52,
        margin: compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.folder_open_rounded,
                color: colorScheme.onPrimaryContainer,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Project scope',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selectionLabel,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.unfold_more_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
