import 'package:arm_console/src/features/overview/data/overview_repository.dart';
import 'package:arm_console/src/features/overview/domain/overview_models.dart';
import 'package:arm_console/src/features/overview/overview_controller.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/ui/console_primitives.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OverviewDashboardPage extends StatefulWidget {
  const OverviewDashboardPage({
    required this.projectController,
    this.repository = const AdaptiveOverviewRepository(),
    super.key,
  });

  final ProjectController projectController;
  final OverviewRepository repository;

  @override
  State<OverviewDashboardPage> createState() => _OverviewDashboardPageState();
}

class _OverviewDashboardPageState extends State<OverviewDashboardPage> {
  late final OverviewController _controller = OverviewController(
    projectController: widget.projectController,
    repository: widget.repository,
  )..start();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        return ConsolePageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ConsoleSectionHeader(
                eyebrow: 'Command view',
                title: 'Overview',
                description:
                    'Urgent ARM signals stay ahead of vanity metrics so the first screen leads directly into investigation.',
              ),
              const SizedBox(height: 24),
              ConsoleFilterBar(
                children: <Widget>[
                  _OverviewFilterMenu<OverviewDateRange>(
                    label: 'Time range',
                    value: _controller.query.dateRange.label,
                    items: OverviewDateRange.values,
                    itemLabel: (OverviewDateRange item) => item.label,
                    onSelected: _controller.setDateRange,
                  ),
                  _OverviewFilterMenu<OverviewSeverityFilter>(
                    label: 'Severity',
                    value: _controller.query.severityFilter.label,
                    items: OverviewSeverityFilter.values,
                    itemLabel: (OverviewSeverityFilter item) => item.label,
                    onSelected: _controller.setSeverityFilter,
                  ),
                  _ScopePill(
                    label: 'Project',
                    value: _controller.scopeLabel,
                    locked: _controller.isProjectScopeLocked,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ScopeBanner(controller: _controller),
              const SizedBox(height: 24),
              _buildBody(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_controller.loadState == OverviewLoadState.loading) {
      return const SizedBox(
        height: 360,
        child: ConsoleStateView.loading(
          title: 'Loading overview',
          message:
              'Preparing project-scoped counts, urgent queues, and trend panels.',
        ),
      );
    }

    if (_controller.loadState == OverviewLoadState.error) {
      return SizedBox(
        height: 360,
        child: ConsoleStateView.error(
          title: 'Overview unavailable',
          message:
              _controller.errorMessage ??
              'The overview data could not be prepared.',
        ),
      );
    }

    final OverviewSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null || snapshot.activeProjects.isEmpty) {
      return SizedBox(
        height: 360,
        child: ConsoleStateView.noAccess(
          title: 'No readable projects',
          message:
              widget.projectController.telemetryRestrictionMessage ??
              'Select one of the assigned projects from the shell switcher to load a scoped overview.',
          actionLabel: 'Open projects',
          onAction: () => context.go('/projects'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: <Widget>[
            _MetricTile(
              label: 'Critical issues',
              value: '${snapshot.counts.criticalIssues}',
              supportingText: _metricDeltaLabel(snapshot.query.dateRange, '+'),
              icon: Icons.priority_high_rounded,
              tone: ConsoleMetricTone.critical,
              onTap: () => context.go('/issues'),
            ),
            _MetricTile(
              label: 'Open cases',
              value: '${snapshot.counts.openCases}',
              supportingText:
                  '${snapshot.urgentItems.length} urgent queues need review',
              icon: Icons.confirmation_number_rounded,
              onTap: () => context.go('/cases'),
            ),
            _MetricTile(
              label: 'Fresh incidents',
              value: '${snapshot.counts.freshIncidents}',
              supportingText:
                  '${snapshot.activeProjects.length} project${snapshot.activeProjects.length == 1 ? '' : 's'} in scope',
              icon: Icons.bolt_rounded,
              tone: ConsoleMetricTone.attention,
              onTap: () => context.go('/reports'),
            ),
            _MetricTile(
              label: 'Healthy projects',
              value: '${snapshot.counts.healthyProjects}',
              supportingText: snapshot.counts.healthyProjects == 0
                  ? 'No calm projects in the current scope'
                  : 'No high-severity alerts in those projects',
              icon: Icons.verified_rounded,
              tone: ConsoleMetricTone.positive,
              onTap: () => context.go('/projects'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (snapshot.overloaded) ...<Widget>[
          _OverloadedBanner(onTap: () => context.go('/issues')),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool split = constraints.maxWidth >= 1080;
            final Widget urgentPanel = ConsoleSurface(
              title: 'Urgent queues',
              description:
                  'High-signal operational worklists stay first so severe fingerprints, integrity risks, and stale cases are visible immediately.',
              child: snapshot.urgentItems.isEmpty
                  ? const ConsoleStateView.empty(
                      title: 'No urgent queues',
                      message:
                          'Critical and high-severity queues are calm for the current scope.',
                    )
                  : Column(
                      children: snapshot.urgentItems
                          .map(
                            (OverviewQueueItem item) => _QueueTile(
                              item: item,
                              onTap: () => context.go(item.routePath),
                            ),
                          )
                          .toList(),
                    ),
            );
            final Widget posturePanel = ConsoleSurface(
              title: 'Incident posture',
              description:
                  'Recent spikes, stale queues, and recovery posture keep the dashboard pointed toward investigation instead of passive monitoring.',
              child: snapshot.postureCards.isEmpty
                  ? const ConsoleStateView.empty(
                      title: 'Calm posture',
                      message:
                          'No anomaly spikes or stale high-priority cases are active in the current scope.',
                    )
                  : Column(
                      children: snapshot.postureCards
                          .map(
                            (OverviewPostureCard card) => _PostureTile(
                              card: card,
                              onTap: () => context.go(card.targetPath),
                            ),
                          )
                          .toList(),
                    ),
            );

            if (split) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: urgentPanel),
                  const SizedBox(width: 16),
                  Expanded(child: posturePanel),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                urgentPanel,
                const SizedBox(height: 16),
                posturePanel,
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool split = constraints.maxWidth >= 1080;
            final Widget volumePanel = _TrendCard(
              series: snapshot.issueVolumeTrend,
              onTap: () => context.go(snapshot.issueVolumeTrend.targetPath),
            );
            final Widget severityPanel = ConsoleSurface(
              title: 'Severity distribution',
              description:
                  'Critical and high-severity balance shows whether the current pressure is still clustered in the most urgent incidents.',
              child: _SeverityMixChart(
                mix: snapshot.severityMix,
                onTap: () => context.go('/reports'),
              ),
            );

            if (split) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: volumePanel),
                  const SizedBox(width: 16),
                  Expanded(child: severityPanel),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                volumePanel,
                const SizedBox(height: 16),
                severityPanel,
              ],
            );
          },
        ),
      ],
    );
  }

  String _metricDeltaLabel(OverviewDateRange range, String direction) {
    return switch (range) {
      OverviewDateRange.last24Hours => '$direction today',
      OverviewDateRange.last7Days => '$direction this week',
      OverviewDateRange.last30Days => '$direction this month',
    };
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.supportingText,
    required this.icon,
    required this.onTap,
    this.tone = ConsoleMetricTone.standard,
  });

  final String label;
  final String value;
  final String supportingText;
  final IconData icon;
  final ConsoleMetricTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: ConsoleMetricCard(
          label: label,
          value: value,
          supportingText: supportingText,
          icon: icon,
          tone: tone,
        ),
      ),
    );
  }
}

class _ScopeBanner extends StatelessWidget {
  const _ScopeBanner({required this.controller});

  final OverviewController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isCrossProject = controller.query.scope.isAllProjects;
    final Color background = isCrossProject
        ? colorScheme.primaryContainer.withValues(alpha: 0.45)
        : colorScheme.surface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isCrossProject ? Icons.hub_outlined : Icons.folder_shared_outlined,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  controller.scopeDescription,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  isCrossProject
                      ? 'Counts and queues aggregate every visible project in the current session.'
                      : 'Counts and queues stay locked to the selected project so broader data is never exposed.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewFilterMenu<T> extends StatelessWidget {
  const _OverviewFilterMenu({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onSelected,
  });

  final String label;
  final String value;
  final List<T> items;
  final String Function(T item) itemLabel;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (BuildContext context) {
        return items
            .map(
              (T item) =>
                  PopupMenuItem<T>(value: item, child: Text(itemLabel(item))),
            )
            .toList();
      },
      child: _ScopePill(label: label, value: value, locked: false),
    );
  }
}

class _ScopePill extends StatelessWidget {
  const _ScopePill({
    required this.label,
    required this.value,
    required this.locked,
  });

  final String label;
  final String value;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: locked ? colorScheme.surfaceContainerHigh : colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              if (locked) ...<Widget>[
                const SizedBox(width: 6),
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.item, required this.onTap});

  final OverviewQueueItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color toneColor = switch (item.severity) {
      OverviewSeverity.critical => const Color(0xFFB3261E),
      OverviewSeverity.high => const Color(0xFF8D5C00),
      OverviewSeverity.medium => Theme.of(context).colorScheme.primary,
    };

    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: Icon(
          item.severity == OverviewSeverity.critical
              ? Icons.error_outline_rounded
              : Icons.warning_amber_rounded,
          color: toneColor,
        ),
        title: Text(item.title),
        subtitle: Text('${item.subtitle} · ${item.projectLabel}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              item.severity.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: toneColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${item.incidentCount} cases',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PostureTile extends StatelessWidget {
  const _PostureTile({required this.card, required this.onTap});

  final OverviewPostureCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ({Color background, Color foreground}) palette = switch (card.tone) {
      OverviewPostureTone.critical => (
        background: const Color(0xFFFDECEA),
        foreground: const Color(0xFFB3261E),
      ),
      OverviewPostureTone.attention => (
        background: const Color(0xFFFFF4E5),
        foreground: const Color(0xFF8D5C00),
      ),
      OverviewPostureTone.positive => (
        background: const Color(0xFFE9F6EC),
        foreground: const Color(0xFF1F6A37),
      ),
      OverviewPostureTone.neutral => (
        background: Theme.of(context).colorScheme.surfaceContainerHighest,
        foreground: Theme.of(context).colorScheme.primary,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.insights_outlined, color: palette.foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      card.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(card.description),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.series, required this.onTap});

  final OverviewTrendSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final int maxValue = series.points.fold<int>(
      1,
      (int previousValue, OverviewTrendPoint point) =>
          previousValue > point.value ? previousValue : point.value,
    );

    return ConsoleSurface(
      title: series.title,
      description: series.subtitle,
      child: Column(
        children: <Widget>[
          for (final OverviewTrendPoint point in series.points) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: <Widget>[
                  SizedBox(width: 88, child: Text(point.label)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 16,
                        value: point.value / maxValue,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${point.value}'),
                ],
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.north_east_rounded),
              label: const Text('Open linked surface'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityMixChart extends StatelessWidget {
  const _SeverityMixChart({required this.mix, required this.onTap});

  final OverviewSeverityMix mix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final int total = mix.total == 0 ? 1 : mix.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _MixRow(
          label: 'Critical',
          value: mix.critical,
          total: total,
          color: const Color(0xFFB3261E),
        ),
        const SizedBox(height: 12),
        _MixRow(
          label: 'High',
          value: mix.high,
          total: total,
          color: const Color(0xFF8D5C00),
        ),
        const SizedBox(height: 12),
        _MixRow(
          label: 'Medium',
          value: mix.medium,
          total: total,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.north_east_rounded),
          label: const Text('Open reports'),
        ),
      ],
    );
  }
}

class _MixRow extends StatelessWidget {
  const _MixRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 16,
              value: value / total,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('$value'),
      ],
    );
  }
}

class _OverloadedBanner extends StatelessWidget {
  const _OverloadedBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.crisis_alert_outlined, color: Color(0xFFB3261E)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Overloaded queue',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Critical or high-severity incidents are clustering fast enough that the dashboard should lead straight into the issues explorer.',
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: onTap, child: const Text('Open issues')),
        ],
      ),
    );
  }
}
