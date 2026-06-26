import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/ui/console_primitives.dart';
import 'package:flutter/material.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({required this.projectController, super.key});

  final ProjectController projectController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectController,
      builder: (BuildContext context, Widget? child) {
        return ConsolePageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ConsoleSectionHeader(
                eyebrow: 'Command view',
                title: 'Overview',
                description:
                    'A calm triage surface for active ARM signals across cases, '
                    'issues, and project health.',
              ),
              const SizedBox(height: 24),
              ConsoleFilterBar(
                children: <Widget>[
                  const _Pill(label: 'Time range', value: 'Last 24 hours'),
                  _Pill(
                    label: 'Project',
                    value: projectController.selectionLabel,
                  ),
                  const _Pill(
                    label: 'Severity',
                    value: 'Critical and above',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: const <Widget>[
                  SizedBox(
                    width: 260,
                    child: ConsoleMetricCard(
                      label: 'Critical issues',
                      value: '12',
                      supportingText: '+3 since 08:00',
                      icon: Icons.priority_high_rounded,
                      tone: ConsoleMetricTone.critical,
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: ConsoleMetricCard(
                      label: 'Open cases',
                      value: '28',
                      supportingText: '9 waiting on follow-up',
                      icon: Icons.confirmation_number_rounded,
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: ConsoleMetricCard(
                      label: 'Fresh incidents',
                      value: '7',
                      supportingText: 'Across 3 projects',
                      icon: Icons.bolt_rounded,
                      tone: ConsoleMetricTone.attention,
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: ConsoleMetricCard(
                      label: 'Healthy projects',
                      value: '5',
                      supportingText: 'No high-severity alerts',
                      icon: Icons.verified_rounded,
                      tone: ConsoleMetricTone.positive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool split = constraints.maxWidth >= 1080;
                  final Widget urgentQueuesPanel = ConsoleSurface(
                    title: 'Urgent queues',
                    description:
                        'High-signal sections are prioritised over passive KPI '
                        'tiles so the first screen leads to action.',
                    child: const _TriageList(),
                  );
                  final Widget posturePanel = ConsoleSurface(
                    title: 'Recent system posture',
                    description:
                        'Shared content states are reusable across sparse, '
                        'loading, and restricted screens.',
                    child: const ConsoleStateView.empty(
                      title: 'No new anomaly spikes',
                      message:
                          'When a project becomes noisy, the overview will '
                          'surface the affected fingerprints here first.',
                    ),
                  );

                  if (split) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: urgentQueuesPanel),
                        const SizedBox(width: 16),
                        Expanded(child: posturePanel),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      urgentQueuesPanel,
                      const SizedBox(height: 16),
                      posturePanel,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class IssuesPage extends StatelessWidget {
  const IssuesPage({required this.projectController, super.key});

  final ProjectController projectController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectController,
      builder: (BuildContext context, Widget? child) {
        return _ConsoleDataPage(
          eyebrow: 'Investigation',
          title: 'Issues',
          description:
              'Dense, readable tables and preserved filter state belong here once '
              'ARM records are wired in.',
          filterChips: <Widget>[
            const _Pill(label: 'Severity', value: 'Critical, high'),
            const _Pill(label: 'Status', value: 'Open'),
            _Pill(label: 'Project', value: projectController.selectionLabel),
          ],
          surfaceTitle: 'Issue fingerprints',
          columns: const <String>[
            'Fingerprint',
            'Severity',
            'Cases',
            'Latest activity',
          ],
          rows: const <List<String>>[
            <String>['saveDraft/network-timeout', 'Critical', '11', '4 min ago'],
            <String>['auth/session-expired', 'High', '8', '14 min ago'],
            <String>['checkout/missing-snapshot', 'High', '4', '39 min ago'],
          ],
        );
      },
    );
  }
}

class CasesPage extends StatelessWidget {
  const CasesPage({required this.projectController, super.key});

  final ProjectController projectController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectController,
      builder: (BuildContext context, Widget? child) {
        return _ConsoleDataPage(
          eyebrow: 'Investigation',
          title: 'Cases',
          description:
              'Case IDs, evidence links, and parent-child navigation will reuse the '
              'same routed shell and table wrappers.',
          filterChips: <Widget>[
            _Pill(label: 'Project', value: projectController.selectionLabel),
            const _Pill(label: 'Recency', value: 'Latest 50'),
          ],
          surfaceTitle: 'Recent cases',
          columns: const <String>['Case ID', 'Issue', 'Severity', 'Reported'],
          rows: const <List<String>>[
            <String>[
              'ARM-2026-00412',
              'saveDraft/network-timeout',
              'Critical',
              '2 min ago',
            ],
            <String>[
              'ARM-2026-00411',
              'auth/session-expired',
              'High',
              '7 min ago',
            ],
            <String>[
              'ARM-2026-00410',
              'checkout/missing-snapshot',
              'High',
              '21 min ago',
            ],
          ],
        );
      },
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({required this.projectController, super.key});

  final ProjectController projectController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectController,
      builder: (BuildContext context, Widget? child) {
        return ConsolePageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ConsoleSectionHeader(
                eyebrow: 'Analysis',
                title: 'Reports',
                description:
                    'Report layouts will plug into the same card rhythm and filter '
                    'language used by the dashboard.',
              ),
              const SizedBox(height: 24),
              ConsoleFilterBar(
                children: <Widget>[
                  const _Pill(label: 'Preset', value: 'Last 7 days'),
                  _Pill(label: 'Scope', value: projectController.selectionLabel),
                  const _Pill(label: 'View', value: 'Severity distribution'),
                ],
              ),
              const SizedBox(height: 24),
              ConsoleSurface(
                title: 'Trend placeholder',
                description:
                    'Shared surfaces keep future charts visually consistent with '
                    'the table and form flows.',
                child: const _TrendPlaceholder(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.projectController, super.key});

  final ProjectController projectController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectController,
      builder: (BuildContext context, Widget? child) {
        return ConsolePageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ConsoleSectionHeader(
                eyebrow: 'Workspace',
                title: 'Settings',
                description:
                    'Shell conventions, access boundaries, and read-only guardrails '
                    'are documented here before feature-specific forms land.',
              ),
              const SizedBox(height: 24),
              ConsoleFormSection(
                title: 'Console conventions',
                description:
                    'These shared primitives define the baseline for future forms, '
                    'evidence panes, and project configuration screens.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const _SettingsRow(
                      label: 'Responsive shell',
                      value:
                          'Single code path with rail on wide layouts and drawer on narrow layouts.',
                    ),
                    const SizedBox(height: 12),
                    const _SettingsRow(
                      label: 'Content states',
                      value:
                          'Loading, empty, error, and no-access views are shared widgets.',
                    ),
                    const SizedBox(height: 12),
                    const _SettingsRow(
                      label: 'Data posture',
                      value:
                          'ARM Console reads project telemetry but does not mutate project evidence.',
                    ),
                    const SizedBox(height: 12),
                    _SettingsRow(
                      label: 'Current scope',
                      value: projectController.selectionLabel,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConsoleDataPage extends StatelessWidget {
  const _ConsoleDataPage({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.filterChips,
    required this.surfaceTitle,
    required this.columns,
    required this.rows,
  });

  final String eyebrow;
  final String title;
  final String description;
  final List<Widget> filterChips;
  final String surfaceTitle;
  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return ConsolePageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ConsoleSectionHeader(
            eyebrow: eyebrow,
            title: title,
            description: description,
          ),
          const SizedBox(height: 24),
          ConsoleFilterBar(children: filterChips),
          const SizedBox(height: 24),
          ConsoleDataTableCard(
            title: surfaceTitle,
            description:
                'Future backend wiring can replace these placeholders without '
                'changing the surrounding surface contract.',
            columns: columns,
            rows: rows,
          ),
        ],
      ),
    );
  }
}

class _TriageList extends StatelessWidget {
  const _TriageList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const <Widget>[
        _TriageItem(
          title: 'Repeated save failures in Core platform',
          subtitle: '11 linked cases in the last hour',
          severity: 'Critical',
        ),
        Divider(height: 1),
        _TriageItem(
          title: 'Session expiry loop in Customer Operations',
          subtitle: '8 cases reported after the latest deploy',
          severity: 'High',
        ),
        Divider(height: 1),
        _TriageItem(
          title: 'Snapshot recovery gap in Checkout',
          subtitle: '4 cases missing recovery payloads',
          severity: 'High',
        ),
      ],
    );
  }
}

class _TriageItem extends StatelessWidget {
  const _TriageItem({
    required this.title,
    required this.subtitle,
    required this.severity,
  });

  final String title;
  final String subtitle;
  final String severity;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: severity == 'Critical'
          ? const Icon(Icons.error_outline_rounded)
          : const Icon(Icons.warning_amber_rounded),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        severity,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TrendPlaceholder extends StatelessWidget {
  const _TrendPlaceholder();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: List<Widget>.generate(5, (int index) {
        final double widthFactor = <double>[
          0.42,
          0.68,
          0.54,
          0.86,
          0.61,
        ][index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: <Widget>[
              SizedBox(width: 88, child: Text('Day ${index + 1}')),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 16,
                    value: widthFactor,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 160,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
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
