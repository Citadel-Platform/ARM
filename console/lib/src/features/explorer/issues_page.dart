import 'package:arm_console/src/features/explorer/data/explorer_repository.dart';
import 'package:arm_console/src/features/explorer/domain/explorer_models.dart';
import 'package:arm_console/src/features/explorer/explorer_widgets.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/ui/console_primitives.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class IssuesExplorerPage extends StatelessWidget {
  const IssuesExplorerPage({
    required this.projectController,
    required this.uri,
    this.repository = const AdaptiveExplorerRepository(),
    super.key,
  });

  final ProjectController projectController;
  final Uri uri;
  final ExplorerRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectController,
      builder: (BuildContext context, Widget? child) {
        final IssuesQuery rawQuery = IssuesQuery.fromUri(uri);

        return ConsolePageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ConsoleSectionHeader(
                eyebrow: 'Investigation',
                title: 'Issues',
                description:
                    'Repeated incidents are grouped into issue fingerprints so operators can sort by urgency, latest activity, and linked case volume before drilling into the underlying records.',
              ),
              const SizedBox(height: 24),
              _buildBody(context, rawQuery),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, IssuesQuery rawQuery) {
    if (projectController.loadState == ProjectLoadState.loading) {
      return const SizedBox(
        height: 360,
        child: ConsoleStateView.loading(
          title: 'Loading issue explorer',
          message: 'Preparing scoped fingerprints and linked case counts.',
        ),
      );
    }

    if (projectController.isTelemetryScopeLoading) {
      return const SizedBox(
        height: 360,
        child: ConsoleStateView.loading(
          title: 'Checking project access',
          message:
              'Verifying monitored-project telemetry permissions for the current scope.',
        ),
      );
    }

    if (projectController.loadState == ProjectLoadState.error) {
      return SizedBox(
        height: 360,
        child: ConsoleStateView.error(
          title: 'Issue explorer unavailable',
          message:
              projectController.errorMessage ??
              'The issue explorer could not be prepared.',
        ),
      );
    }

    final List<ConsoleProject> visibleProjects = projectController
        .telemetryProjects
        .toList();
    if (visibleProjects.isEmpty) {
      return SizedBox(
        height: 360,
        child: ConsoleStateView.noAccess(
          title: 'No readable projects',
          message:
              projectController.telemetryRestrictionMessage ??
              'Your session does not currently have any project scopes that can read monitored ARM telemetry.',
        ),
      );
    }

    final String? forcedProjectId = _forcedProjectId(visibleProjects);
    final bool hasInvalidProject =
        rawQuery.projectId != null &&
        !visibleProjects.any(
          (ConsoleProject project) => project.id == rawQuery.projectId,
        );
    final bool conflictsWithLockedScope =
        forcedProjectId != null &&
        rawQuery.projectId != null &&
        rawQuery.projectId != forcedProjectId;

    if (hasInvalidProject || conflictsWithLockedScope) {
      return SizedBox(
        height: 360,
        child: ConsoleStateView.noAccess(
          title: 'Requested issue scope is not available',
          message:
              'The deep link requested a project scope that this session cannot inspect.',
          actionLabel: 'Clear project filter',
          onAction: () =>
              context.go(rawQuery.copyWith(clearProject: true).toLocation()),
        ),
      );
    }

    final IssuesQuery effectiveQuery = forcedProjectId == null
        ? rawQuery
        : rawQuery.copyWith(projectId: forcedProjectId);

    return FutureBuilder<IssuesResult>(
      future: repository.loadIssues(
        query: effectiveQuery,
        visibleProjects: visibleProjects,
      ),
      builder: (BuildContext context, AsyncSnapshot<IssuesResult> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 360,
            child: ConsoleStateView.loading(
              title: 'Loading issue explorer',
              message: 'Filtering fingerprints and restoring the active route.',
            ),
          );
        }

        if (snapshot.hasError) {
          return SizedBox(
            height: 360,
            child: ConsoleStateView.error(
              title: 'Issue query failed',
              message: 'The scoped issue query could not be completed.',
              onAction: () => context.go(rawQuery.toLocation()),
            ),
          );
        }

        final IssuesResult result = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildFilters(
              context,
              rawQuery: rawQuery,
              effectiveQuery: effectiveQuery,
              visibleProjects: visibleProjects,
              projectLocked: forcedProjectId != null,
            ),
            const SizedBox(height: 16),
            if (result.selectedIssue != null) ...<Widget>[
              _SelectedIssueCard(
                issue: result.selectedIssue!,
                onViewCases: () {
                  context.go(
                    CasesQuery(
                      projectId: rawQuery.projectId,
                      range: rawQuery.range,
                      severityFilter: rawQuery.severityFilter,
                      issueId: result.selectedIssue!.issueId,
                    ).toLocation(),
                  );
                },
                onClear: () {
                  context.go(
                    rawQuery.copyWith(clearSelectedIssue: true).toLocation(),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            if (result.totalCount == 0)
              SizedBox(
                height: 360,
                child: ConsoleStateView.empty(
                  title: 'No matching issues',
                  message:
                      'No issue fingerprints matched the current scope, filters, or search term.',
                  actionLabel: 'Clear filters',
                  onAction: () => context.go(const IssuesQuery().toLocation()),
                ),
              )
            else
              _IssuesTableCard(
                query: rawQuery,
                result: result,
                onSelectIssue: (IssueRecord issue) {
                  context.go(
                    rawQuery
                        .copyWith(selectedIssueId: issue.issueId)
                        .toLocation(),
                  );
                },
                onViewCases: (IssueRecord issue) {
                  context.go(
                    CasesQuery(
                      projectId: rawQuery.projectId,
                      range: rawQuery.range,
                      severityFilter: rawQuery.severityFilter,
                      issueId: issue.issueId,
                    ).toLocation(),
                  );
                },
                onPreviousPage: result.currentPage > 1
                    ? () => context.go(
                        rawQuery
                            .copyWith(page: result.currentPage - 1)
                            .toLocation(),
                      )
                    : null,
                onNextPage: result.currentPage < result.totalPages
                    ? () => context.go(
                        rawQuery
                            .copyWith(page: result.currentPage + 1)
                            .toLocation(),
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }

  Widget _buildFilters(
    BuildContext context, {
    required IssuesQuery rawQuery,
    required IssuesQuery effectiveQuery,
    required List<ConsoleProject> visibleProjects,
    required bool projectLocked,
  }) {
    final List<_ProjectOption> projectOptions = <_ProjectOption>[
      const _ProjectOption(id: null, label: 'All scoped projects'),
      ...visibleProjects.map(
        (ConsoleProject project) =>
            _ProjectOption(id: project.id, label: project.shellLabel),
      ),
    ];

    return ConsoleFilterBar(
      children: <Widget>[
        ExplorerSearchField(
          search: effectiveQuery.search,
          hintText: 'Search fingerprint or summary',
          onSubmitted: (String value) {
            context.go(
              rawQuery.copyWith(search: value.trim(), page: 1).toLocation(),
            );
          },
          onClear: () =>
              context.go(rawQuery.copyWith(search: '', page: 1).toLocation()),
        ),
        ExplorerMenuChip<ExplorerSeverityFilter>(
          label: 'Severity',
          value: effectiveQuery.severityFilter.label,
          items: ExplorerSeverityFilter.values,
          itemLabel: (ExplorerSeverityFilter item) => item.label,
          onSelected: (ExplorerSeverityFilter filter) {
            context.go(
              rawQuery.copyWith(severityFilter: filter, page: 1).toLocation(),
            );
          },
        ),
        ExplorerMenuChip<ExplorerDateRange>(
          label: 'Time range',
          value: effectiveQuery.range.label,
          items: ExplorerDateRange.values,
          itemLabel: (ExplorerDateRange item) => item.label,
          onSelected: (ExplorerDateRange range) {
            context.go(rawQuery.copyWith(range: range, page: 1).toLocation());
          },
        ),
        ExplorerMenuChip<IssueStatusFilter>(
          label: 'Status',
          value: effectiveQuery.status.label,
          items: IssueStatusFilter.values,
          itemLabel: (IssueStatusFilter item) => item.label,
          onSelected: (IssueStatusFilter status) {
            context.go(rawQuery.copyWith(status: status, page: 1).toLocation());
          },
        ),
        ExplorerMenuChip<IssueSort>(
          label: 'Sort',
          value: effectiveQuery.sort.label,
          items: IssueSort.values,
          itemLabel: (IssueSort item) => item.label,
          onSelected: (IssueSort sort) {
            context.go(rawQuery.copyWith(sort: sort, page: 1).toLocation());
          },
        ),
        if (projectLocked)
          ExplorerMenuChip<String>(
            label: 'Project',
            value: projectController.selectionLabel,
            items: const <String>[],
            itemLabel: (String item) => item,
            onSelected: (_) {},
            enabled: false,
          )
        else
          ExplorerMenuChip<_ProjectOption>(
            label: 'Project',
            value: projectOptions
                .firstWhere(
                  (_ProjectOption option) => option.id == rawQuery.projectId,
                  orElse: () => projectOptions.first,
                )
                .label,
            items: projectOptions,
            itemLabel: (_ProjectOption item) => item.label,
            onSelected: (_ProjectOption option) {
              context.go(
                option.id == null
                    ? rawQuery
                          .copyWith(clearProject: true, page: 1)
                          .toLocation()
                    : rawQuery
                          .copyWith(projectId: option.id, page: 1)
                          .toLocation(),
              );
            },
          ),
      ],
    );
  }

  String? _forcedProjectId(List<ConsoleProject> visibleProjects) {
    if (!projectController.canSelectAll ||
        !projectController.isAllProjectsSelected) {
      return projectController.selectedProjectId ?? visibleProjects.first.id;
    }
    return null;
  }
}

class _IssuesTableCard extends StatelessWidget {
  const _IssuesTableCard({
    required this.query,
    required this.result,
    required this.onSelectIssue,
    required this.onViewCases,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final IssuesQuery query;
  final IssuesResult result;
  final ValueChanged<IssueRecord> onSelectIssue;
  final ValueChanged<IssueRecord> onViewCases;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Issue fingerprints',
      description:
          'The explorer keeps filter state in the URL so investigative table views can be shared and restored without losing context.',
      child: Column(
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 52,
              dataRowMinHeight: 88,
              dataRowMaxHeight: 88,
              columns: const <DataColumn>[
                DataColumn(label: Text('Fingerprint')),
                DataColumn(label: Text('Project')),
                DataColumn(label: Text('Severity')),
                DataColumn(label: Text('First seen')),
                DataColumn(label: Text('Latest activity')),
                DataColumn(label: Text('Cases')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Investigate')),
              ],
              rows: result.records.map((IssueRecord issue) {
                final bool isSelected = issue.issueId == query.selectedIssueId;
                return DataRow(
                  color: WidgetStateProperty.resolveWith<Color?>((
                    Set<WidgetState> states,
                  ) {
                    if (!isSelected) {
                      return null;
                    }
                    return Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.35);
                  }),
                  cells: <DataCell>[
                    DataCell(
                      SizedBox(
                        width: 280,
                        child: InkWell(
                          onTap: () => onSelectIssue(issue),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                issue.fingerprint,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                issue.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(width: 180, child: Text(issue.projectLabel)),
                    ),
                    DataCell(Text(issue.severity.label)),
                    DataCell(Text(issue.firstSeenLabel)),
                    DataCell(Text(issue.lastSeenLabel)),
                    DataCell(Text('${issue.totalCases}')),
                    DataCell(
                      SizedBox(
                        width: 120,
                        child: Text(
                          '${issue.status.label} · ${issue.urgencyLabel}',
                        ),
                      ),
                    ),
                    DataCell(
                      TextButton(
                        onPressed: () => onViewCases(issue),
                        child: const Text('View cases'),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          ExplorerPaginationFooter(
            totalCount: result.totalCount,
            currentPage: result.currentPage,
            totalPages: result.totalPages,
            onPrevious: onPreviousPage,
            onNext: onNextPage,
          ),
        ],
      ),
    );
  }
}

class _SelectedIssueCard extends StatelessWidget {
  const _SelectedIssueCard({
    required this.issue,
    required this.onViewCases,
    required this.onClear,
  });

  final IssueRecord issue;
  final VoidCallback onViewCases;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Selected issue',
      description:
          'Direct links can keep a specific fingerprint selected while the surrounding table state remains shareable.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            issue.fingerprint,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(issue.title),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _MetaPill(label: 'Project', value: issue.projectLabel),
              _MetaPill(label: 'Severity', value: issue.severity.label),
              _MetaPill(label: 'Latest activity', value: issue.lastSeenLabel),
              _MetaPill(label: 'Linked cases', value: '${issue.totalCases}'),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton(
                onPressed: onViewCases,
                child: const Text('View linked cases'),
              ),
              OutlinedButton(
                onPressed: onClear,
                child: const Text('Clear selection'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ProjectOption {
  const _ProjectOption({required this.id, required this.label});

  final String? id;
  final String label;
}
