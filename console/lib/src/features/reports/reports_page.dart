import 'package:arm_console/src/features/explorer/domain/explorer_models.dart';
import 'package:arm_console/src/features/explorer/explorer_widgets.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/features/reports/data/reports_repository.dart';
import 'package:arm_console/src/features/reports/domain/reports_models.dart';
import 'package:arm_console/src/ui/console_primitives.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ReportsDashboardPage extends StatelessWidget {
  const ReportsDashboardPage({
    required this.projectController,
    required this.uri,
    this.repository = const AdaptiveReportsRepository(),
    super.key,
  });

  final ProjectController projectController;
  final Uri uri;
  final ReportsRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectController,
      builder: (BuildContext context, Widget? child) {
        final ReportsQuery rawQuery = ReportsQuery.fromUri(uri);
        return ConsolePageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ConsoleSectionHeader(
                eyebrow: 'Analysis',
                title: 'Reports',
                description:
                    'Trend, distribution, and hotspot views help operators move from record-by-record triage into broader operational patterns without leaving the routed console shell.',
              ),
              const SizedBox(height: 24),
              _buildBody(context, rawQuery),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, ReportsQuery rawQuery) {
    if (projectController.loadState == ProjectLoadState.loading) {
      return const SizedBox(
        height: 360,
        child: ConsoleStateView.loading(
          title: 'Loading reports',
          message:
              'Preparing scoped trends, distributions, and hotspot comparisons.',
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
          title: 'Reports unavailable',
          message:
              projectController.errorMessage ??
              'The reports view could not be prepared.',
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

    final Set<String> visibleProjectIds = visibleProjects
        .map((ConsoleProject project) => project.id)
        .toSet();
    final String? forcedProjectId = _forcedProjectId(visibleProjects);
    final bool hasInvalidProject =
        rawQuery.projectId != null &&
        !visibleProjectIds.contains(rawQuery.projectId);
    final bool conflictsWithLockedScope =
        forcedProjectId != null &&
        rawQuery.projectId != null &&
        rawQuery.projectId != forcedProjectId;

    if (hasInvalidProject || conflictsWithLockedScope) {
      return SizedBox(
        height: 360,
        child: ConsoleStateView.noAccess(
          title: 'Requested report scope is not available',
          message:
              'The deep link requested a project scope that this session cannot inspect.',
          actionLabel: 'Clear project filter',
          onAction: () =>
              context.go(rawQuery.copyWith(clearProject: true).toLocation()),
        ),
      );
    }

    final ReportsQuery effectiveQuery = forcedProjectId == null
        ? rawQuery
        : rawQuery.copyWith(projectId: forcedProjectId);
    final List<ReportProjectReference> activeProjects = visibleProjects
        .where((ConsoleProject project) {
          final bool projectMatches =
              effectiveQuery.projectId == null ||
              project.id == effectiveQuery.projectId;
          final bool environmentMatches =
              switch (effectiveQuery.environmentFilter) {
                ReportEnvironmentFilter.all => true,
                ReportEnvironmentFilter.production =>
                  project.environment == ProjectEnvironment.production,
                ReportEnvironmentFilter.staging =>
                  project.environment == ProjectEnvironment.staging,
              };
          return projectMatches && environmentMatches;
        })
        .map(
          (ConsoleProject project) => ReportProjectReference(
            id: project.id,
            name: project.name,
            environmentLabel: project.environmentLabel,
            firebaseConfig: project.firebaseConfig,
          ),
        )
        .toList();

    return FutureBuilder<ReportsSnapshot>(
      future: repository.load(
        query: effectiveQuery,
        activeProjects: activeProjects,
      ),
      builder: (BuildContext context, AsyncSnapshot<ReportsSnapshot> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 360,
            child: ConsoleStateView.loading(
              title: 'Loading reports',
              message: 'Refreshing report cards for the active route filters.',
            ),
          );
        }

        if (snapshot.hasError) {
          return SizedBox(
            height: 360,
            child: ConsoleStateView.error(
              title: 'Report query failed',
              message: 'The requested report aggregate could not be prepared.',
              onAction: () => context.go(rawQuery.toLocation()),
            ),
          );
        }

        final ReportsSnapshot result = snapshot.data!;
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
            _ReportsScopeBanner(
              snapshot: result,
              projectLocked: forcedProjectId != null,
            ),
            const SizedBox(height: 24),
            if (result.activeProjects.isEmpty)
              SizedBox(
                height: 360,
                child: ConsoleStateView.empty(
                  title: 'No matching report scope',
                  message:
                      'No projects matched the current project and environment filters.',
                  actionLabel: 'Clear filters',
                  onAction: () => context.go(const ReportsQuery().toLocation()),
                ),
              )
            else
              _ReportsContent(snapshot: result),
          ],
        );
      },
    );
  }

  Widget _buildFilters(
    BuildContext context, {
    required ReportsQuery rawQuery,
    required ReportsQuery effectiveQuery,
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
        ExplorerMenuChip<ExplorerDateRange>(
          label: 'Time range',
          value: effectiveQuery.range.label,
          items: ExplorerDateRange.values,
          itemLabel: (ExplorerDateRange item) => item.label,
          onSelected: (ExplorerDateRange value) {
            context.go(rawQuery.copyWith(range: value).toLocation());
          },
        ),
        ExplorerMenuChip<ExplorerSeverityFilter>(
          label: 'Severity',
          value: effectiveQuery.severityFilter.label,
          items: ExplorerSeverityFilter.values,
          itemLabel: (ExplorerSeverityFilter item) => item.label,
          onSelected: (ExplorerSeverityFilter value) {
            context.go(rawQuery.copyWith(severityFilter: value).toLocation());
          },
        ),
        ExplorerMenuChip<ReportEnvironmentFilter>(
          label: 'Environment',
          value: effectiveQuery.environmentFilter.label,
          items: ReportEnvironmentFilter.values,
          itemLabel: (ReportEnvironmentFilter item) => item.label,
          onSelected: (ReportEnvironmentFilter value) {
            context.go(
              rawQuery.copyWith(environmentFilter: value).toLocation(),
            );
          },
        ),
        ExplorerMenuChip<_ProjectOption>(
          label: 'Project',
          value: _labelForProject(projectOptions, effectiveQuery.projectId),
          items: projectOptions,
          itemLabel: (_ProjectOption item) => item.label,
          enabled: !projectLocked,
          onSelected: (_ProjectOption option) {
            context.go(
              rawQuery
                  .copyWith(
                    projectId: option.id,
                    clearProject: option.id == null,
                  )
                  .toLocation(),
            );
          },
        ),
      ],
    );
  }
}

class _ReportsContent extends StatelessWidget {
  const _ReportsContent({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          spacing: 16,
          runSpacing: 16,
          children: <Widget>[
            SizedBox(
              width: 240,
              child: ConsoleMetricCard(
                label: 'Issue volume',
                value: '${snapshot.totalIssueVolume}',
                supportingText: snapshot.query.range.label,
                icon: Icons.show_chart_rounded,
                tone: ConsoleMetricTone.critical,
              ),
            ),
            SizedBox(
              width: 240,
              child: ConsoleMetricCard(
                label: 'Case frequency',
                value: '${snapshot.totalCaseVolume}',
                supportingText:
                    '${snapshot.repeatOffenders.length} repeat offenders',
                icon: Icons.stacked_line_chart_rounded,
                tone: ConsoleMetricTone.attention,
              ),
            ),
            SizedBox(
              width: 240,
              child: ConsoleMetricCard(
                label: 'Projects in scope',
                value: '${snapshot.impactedProjectCount}',
                supportingText: snapshot.crossProjectComparisonAvailable
                    ? 'Cross-project comparisons enabled'
                    : 'Single-project reporting scope',
                icon: Icons.hub_rounded,
              ),
            ),
            SizedBox(
              width: 240,
              child: ConsoleMetricCard(
                label: 'Severity buckets',
                value: '${snapshot.severityDistribution.length}',
                supportingText: 'Drill into routed issue explorers',
                icon: Icons.pie_chart_outline_rounded,
                tone: ConsoleMetricTone.positive,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool split = constraints.maxWidth >= 1080;
            final Widget trendColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TrendCard(series: snapshot.issueVolumeTrend),
                const SizedBox(height: 16),
                _TrendCard(series: snapshot.caseFrequencyTrend),
              ],
            );
            final Widget summaryColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _SeverityDistributionCard(
                  buckets: snapshot.severityDistribution,
                ),
                const SizedBox(height: 16),
                _RepeatOffendersCard(records: snapshot.repeatOffenders),
              ],
            );

            if (split) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: trendColumn),
                  const SizedBox(width: 16),
                  Expanded(child: summaryColumn),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                trendColumn,
                const SizedBox(height: 16),
                summaryColumn,
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool split = constraints.maxWidth >= 1080;
            final Widget hotspots = _HotspotsCard(snapshot: snapshot);
            final Widget spikes = _SpikesCard(records: snapshot.spikes);

            if (split) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: hotspots),
                  const SizedBox(width: 16),
                  Expanded(child: spikes),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[hotspots, const SizedBox(height: 16), spikes],
            );
          },
        ),
      ],
    );
  }
}

class _ReportsScopeBanner extends StatelessWidget {
  const _ReportsScopeBanner({
    required this.snapshot,
    required this.projectLocked,
  });

  final ReportsSnapshot snapshot;
  final bool projectLocked;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String scopeLabel = snapshot.activeProjects.isEmpty
        ? 'No matching projects in scope'
        : snapshot.activeProjects.length == 1
        ? '${snapshot.activeProjects.first.name} · ${snapshot.activeProjects.first.environmentLabel}'
        : '${snapshot.activeProjects.length} projects in scope';
    final String description = projectLocked
        ? 'Project-scoped sessions stay pinned to assigned projects while still supporting routed range, severity, and environment filters.'
        : snapshot.crossProjectComparisonAvailable
        ? 'Superuser sessions can compare hotspots across projects and drill straight into the routed explorers from any report card.'
        : 'The current route is focused on a single project, so cross-project comparisons collapse into project-specific reporting.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stacked = constraints.maxWidth < 560;
          final Widget icon = Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              projectLocked ? Icons.lock_outline_rounded : Icons.hub_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
          );
          final Widget copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                scopeLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(description),
            ],
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[icon, const SizedBox(height: 12), copy],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              icon,
              const SizedBox(width: 12),
              Expanded(child: copy),
            ],
          );
        },
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.series});

  final ReportTrendSeries series;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: series.title,
      description: series.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MiniBarChart(points: series.points),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go(series.targetPath),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Open drill-down'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityDistributionCard extends StatelessWidget {
  const _SeverityDistributionCard({required this.buckets});

  final List<ReportDistributionBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final int maxValue = buckets.fold(0, (
      int current,
      ReportDistributionBucket bucket,
    ) {
      return bucket.value > current ? bucket.value : current;
    });

    return ConsoleSurface(
      title: 'Severity distribution',
      description:
          'Each severity bucket links back to the underlying routed issue explorer instead of becoming a dead-end summary.',
      child: buckets.isEmpty
          ? const ConsoleStateView.empty(
              title: 'No severity data',
              message:
                  'The active report filters removed every severity bucket from the current scope.',
            )
          : Column(
              children: buckets.map((ReportDistributionBucket bucket) {
                final double fraction = maxValue == 0
                    ? 0
                    : bucket.value / maxValue;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 88,
                        child: Text(
                          bucket.label,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 10,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${bucket.value}'),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => context.go(bucket.targetPath),
                        child: const Text('View issues'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _RepeatOffendersCard extends StatelessWidget {
  const _RepeatOffendersCard({required this.records});

  final List<ReportRepeatOffender> records;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Repeat offenders',
      description:
          'Repeated fingerprints stay actionable with direct issue drill-downs, project context, and severity tags instead of being flattened into a static leaderboard.',
      child: records.isEmpty
          ? const ConsoleStateView.empty(
              title: 'No repeat offenders',
              message:
                  'The current filters removed all routed issue candidates from this scope.',
            )
          : Column(
              children: records.map((ReportRepeatOffender record) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        final Widget copy = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              record.fingerprint,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${record.projectLabel} · ${record.severity.label} · ${record.caseCount} linked cases',
                            ),
                          ],
                        );
                        final Widget action = OutlinedButton(
                          onPressed: () => context.go(record.targetPath),
                          child: const Text('Open issue'),
                        );

                        if (constraints.maxWidth < 420) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              copy,
                              const SizedBox(height: 12),
                              action,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: copy),
                            const SizedBox(width: 12),
                            action,
                          ],
                        );
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _HotspotsCard extends StatelessWidget {
  const _HotspotsCard({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (!snapshot.crossProjectComparisonAvailable) {
      return const ConsoleSurface(
        title: 'Cross-project hotspots',
        description:
            'Cross-project comparison becomes meaningful when more than one visible project remains in the active route scope.',
        child: ConsoleStateView.empty(
          title: 'Single-project scope',
          message:
              'Widen the project filter to compare hotspots across projects; this route is currently focused on one project.',
        ),
      );
    }

    return ConsoleSurface(
      title: 'Cross-project hotspots',
      description:
          'The noisiest projects surface first so developers can spot systemic failures and jump straight into routed issue explorers.',
      child: Column(
        children: snapshot.hotspots.map((ReportProjectHotspot hotspot) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget copy = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        hotspot.projectLabel,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${hotspot.environmentLabel} · ${hotspot.issueVolume} issues · ${hotspot.caseVolume} cases',
                      ),
                      const SizedBox(height: 6),
                      Text(hotspot.spikeLabel),
                    ],
                  );
                  final Widget action = OutlinedButton(
                    onPressed: () => context.go(hotspot.targetPath),
                    child: const Text('Open project issues'),
                  );

                  if (constraints.maxWidth < 420) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        copy,
                        const SizedBox(height: 12),
                        action,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: copy),
                      const SizedBox(width: 12),
                      action,
                    ],
                  );
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SpikesCard extends StatelessWidget {
  const _SpikesCard({required this.records});

  final List<ReportSpike> records;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Sudden reporting spikes',
      description:
          'Annotated spike cards make sparse or bursty report windows readable without over-explaining the charts above.',
      child: records.isEmpty
          ? const ConsoleStateView.empty(
              title: 'No spike cards',
              message:
                  'No spike annotations matched the current route filters and severity scope.',
            )
          : Column(
              children: records.map((ReportSpike record) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        final Widget copy = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              record.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${record.projectLabel} · ${record.severity.label} · ${record.changeLabel}',
                            ),
                          ],
                        );
                        final Widget action = OutlinedButton(
                          onPressed: () => context.go(record.targetPath),
                          child: const Text('Open spike'),
                        );

                        if (constraints.maxWidth < 420) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              copy,
                              const SizedBox(height: 12),
                              action,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: copy),
                            const SizedBox(width: 12),
                            action,
                          ],
                        );
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _MiniBarChart extends StatelessWidget {
  const _MiniBarChart({required this.points});

  final List<ReportTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final int maxValue = points.fold(0, (int current, ReportTrendPoint point) {
      return point.value > current ? point.value : current;
    });
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((ReportTrendPoint point) {
          final double fraction = maxValue == 0 ? 0 : point.value / maxValue;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${point.value}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: fraction == 0 ? 0.08 : fraction,
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    point.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ProjectOption {
  const _ProjectOption({required this.id, required this.label});

  final String? id;
  final String label;
}

String _labelForProject(List<_ProjectOption> options, String? projectId) {
  for (final _ProjectOption option in options) {
    if (option.id == projectId) {
      return option.label;
    }
  }
  return options.first.label;
}

String? _forcedProjectId(List<ConsoleProject> visibleProjects) {
  return visibleProjects.length == 1 ? visibleProjects.first.id : null;
}
