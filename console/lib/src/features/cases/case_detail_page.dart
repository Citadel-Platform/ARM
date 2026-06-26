import 'package:arm_console/src/features/cases/case_detail_models.dart';
import 'package:arm_console/src/features/explorer/data/explorer_repository.dart';
import 'package:arm_console/src/features/explorer/domain/explorer_models.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:arm_console/src/features/projects/project_controller.dart';
import 'package:arm_console/src/ui/console_primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class CaseDetailPage extends StatelessWidget {
  const CaseDetailPage({
    required this.projectController,
    required this.caseId,
    this.repository = const AdaptiveExplorerRepository(),
    super.key,
  });

  final ProjectController projectController;
  final String caseId;
  final ExplorerRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectController,
      builder: (BuildContext context, Widget? child) {
        return ConsolePageBody(child: _buildBody(context));
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    if (projectController.loadState == ProjectLoadState.loading) {
      return const SizedBox(
        height: 480,
        child: ConsoleStateView.loading(
          title: 'Loading case workspace',
          message: 'Preparing the case evidence bundle and scoped detail view.',
        ),
      );
    }

    if (projectController.isTelemetryScopeLoading) {
      return const SizedBox(
        height: 480,
        child: ConsoleStateView.loading(
          title: 'Checking project access',
          message:
              'Verifying monitored-project telemetry permissions for the current scope.',
        ),
      );
    }

    if (projectController.loadState == ProjectLoadState.error) {
      return SizedBox(
        height: 480,
        child: ConsoleStateView.error(
          title: 'Case workspace unavailable',
          message:
              projectController.errorMessage ??
              'The case detail view could not be prepared.',
        ),
      );
    }

    final List<ConsoleProject> visibleProjects = projectController
        .telemetryProjects
        .toList();
    if (visibleProjects.isEmpty) {
      return SizedBox(
        height: 480,
        child: ConsoleStateView.noAccess(
          title: 'No readable projects',
          message:
              projectController.telemetryRestrictionMessage ??
              'Your session does not currently have any project scopes that can read monitored ARM telemetry.',
        ),
      );
    }

    return FutureBuilder<CaseDetailRecord?>(
      future: repository.loadCaseDetail(
        caseId: caseId,
        visibleProjects: visibleProjects,
      ),
      builder: (BuildContext context, AsyncSnapshot<CaseDetailRecord?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 480,
            child: ConsoleStateView.loading(
              title: 'Loading case workspace',
              message:
                  'Restoring the case evidence bundle from the seeded data layer.',
            ),
          );
        }

        if (snapshot.hasError) {
          return const SizedBox(
            height: 480,
            child: ConsoleStateView.error(
              title: 'Case detail query failed',
              message:
                  'The case evidence bundle could not be loaded for the current route.',
            ),
          );
        }

        final CaseDetailRecord? detail = snapshot.data;
        if (detail == null) {
          return SizedBox(
            height: 480,
            child: ConsoleStateView.noAccess(
              title: 'Case not available',
              message:
                  'This case either does not exist in the current seeded dataset or is outside the projects visible to the current session.',
              actionLabel: 'Back to cases',
              onAction: () => context.go('/cases'),
            ),
          );
        }

        return _CaseDetailContent(detail: detail);
      },
    );
  }
}

class _CaseDetailContent extends StatelessWidget {
  const _CaseDetailContent({required this.detail});

  final CaseDetailRecord detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ConsoleSectionHeader(
          eyebrow: 'Case workspace',
          title: detail.caseRecord.caseId,
          description:
              'Read-only evidence workspace for ${detail.issueRecord.fingerprint}. The case detail prioritizes quick incident comprehension before deeper logs and snapshot payloads.',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: () {
                context.go(
                  CasesQuery(
                    issueId: detail.caseRecord.issueId,
                    projectId: detail.caseRecord.projectId,
                  ).toLocation(),
                );
              },
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to cases'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _copyValue(
                context,
                label: 'Case ID',
                value: detail.caseRecord.caseId,
              ),
              icon: const Icon(Icons.copy_all_rounded),
              label: const Text('Copy case ID'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _CaseHero(detail: detail),
        const SizedBox(height: 16),
        if (detail.hasMissingEvidence) ...<Widget>[
          _MissingEvidenceBanner(detail: detail),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 1120;
            final Widget mainColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _NarrativeSurface(detail: detail),
                const SizedBox(height: 16),
                _TelemetrySurface(detail: detail),
                const SizedBox(height: 16),
                _SnapshotSurface(detail: detail),
              ],
            );
            final Widget sideColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _EvidenceSurface(detail: detail),
                const SizedBox(height: 16),
                _ContextSurface(detail: detail),
                const SizedBox(height: 16),
                _RecoverySurface(detail: detail),
              ],
            );

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  mainColumn,
                  const SizedBox(height: 16),
                  sideColumn,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 8, child: mainColumn),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: sideColumn),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CaseHero extends StatelessWidget {
  const _CaseHero({required this.detail});

  final CaseDetailRecord detail;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _HeroPill(label: 'Issue', value: detail.issueRecord.fingerprint),
              _HeroPill(
                label: 'Project',
                value: detail.caseRecord.projectLabel,
              ),
              _HeroPill(
                label: 'Severity',
                value: detail.caseRecord.severity.label,
              ),
              _HeroPill(label: 'Status', value: detail.caseRecord.status.label),
              _HeroPill(label: 'Detected', value: detail.detectedLabel),
              _HeroPill(
                label: 'Follow-up',
                value: detail.caseRecord.followUpId,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            detail.caseRecord.issueTitle,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            detail.customerImpact,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton(
                onPressed: () {
                  context.go(
                    IssuesQuery(
                      projectId: detail.caseRecord.projectId,
                      search: detail.issueRecord.fingerprint,
                      selectedIssueId: detail.issueRecord.issueId,
                    ).toLocation(),
                  );
                },
                child: const Text('Open parent issue'),
              ),
              OutlinedButton(
                onPressed: () => _copyValue(
                  context,
                  label: 'Follow-up ID',
                  value: detail.caseRecord.followUpId,
                ),
                child: const Text('Copy follow-up ID'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingEvidenceBanner extends StatelessWidget {
  const _MissingEvidenceBanner({required this.detail});

  final CaseDetailRecord detail;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFF8D5C00),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Some evidence is unavailable',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...detail.missingEvidenceNotes.map(
            (String note) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $note'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrativeSurface extends StatelessWidget {
  const _NarrativeSurface({required this.detail});

  final CaseDetailRecord detail;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Incident narrative',
      description:
          'The case timeline is ordered to explain what happened, when evidence was captured, and why the incident matters before diving into raw telemetry.',
      child: Column(
        children: detail.narrative
            .map((CaseNarrativeStep step) => _NarrativeTile(step: step))
            .toList(),
      ),
    );
  }
}

class _NarrativeTile extends StatelessWidget {
  const _NarrativeTile({required this.step});

  final CaseNarrativeStep step;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 72,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              step.label,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  step.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(step.description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetrySurface extends StatelessWidget {
  const _TelemetrySurface({required this.detail});

  final CaseDetailRecord detail;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Telemetry and traces',
      description:
          'Stack traces and console logs are kept in copyable, bounded viewers so investigation stays tooling-like instead of devolving into wrapped prose.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CodePanel(
            title: 'Trace summary',
            body: detail.traceSummary,
            onCopy: () => _copyValue(
              context,
              label: 'Trace summary',
              value: detail.traceSummary,
            ),
          ),
          const SizedBox(height: 16),
          _CodePanel(
            title: 'Stack trace',
            body: detail.traceBody,
            onCopy: () => _copyValue(
              context,
              label: 'Stack trace',
              value: detail.traceBody,
            ),
          ),
          const SizedBox(height: 16),
          ConsoleSurface(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Console log',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyValue(
                        context,
                        label: 'Console log',
                        value: detail.consoleLogs
                            .map(
                              (CaseLogEntry entry) =>
                                  '[${entry.timeLabel}] ${entry.level.name.toUpperCase()} ${entry.message}',
                            )
                            .join('\n'),
                      ),
                      icon: const Icon(Icons.copy_all_rounded),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (detail.consoleLogs.isEmpty)
                  const Text(
                    'No console log lines were preserved for this case.',
                  )
                else
                  Column(
                    children: detail.consoleLogs
                        .map((CaseLogEntry entry) => _LogTile(entry: entry))
                        .toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotSurface extends StatelessWidget {
  const _SnapshotSurface({required this.detail});

  final CaseDetailRecord detail;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Snapshot inspector',
      description:
          'Captured recovery payloads stay read-only and copyable so operators can inspect structure without mutating monitored project data.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            detail.snapshotTitle,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _CodePanel(
            title: 'Snapshot payload',
            body: detail.snapshotJson,
            onCopy: () => _copyValue(
              context,
              label: 'Snapshot payload',
              value: detail.snapshotJson,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceSurface extends StatelessWidget {
  const _EvidenceSurface({required this.detail});

  final CaseDetailRecord detail;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Case evidence',
      description:
          'Screenshots and supporting assets are easy to inspect first because they usually provide the fastest operational context.',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = constraints.maxWidth >= 420 ? 2 : 1;
          if (detail.evidenceAssets.isEmpty) {
            return const ConsoleStateView.empty(
              title: 'No evidence assets',
              message:
                  'This case does not currently have seeded screenshots or attachment metadata.',
            );
          }

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: detail.evidenceAssets.map((CaseEvidenceAsset asset) {
              final double width = columns == 2
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return SizedBox(
                width: width,
                child: _EvidenceCard(asset: asset),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.asset});

  final CaseEvidenceAsset asset;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ({Color background, Color foreground, IconData icon}) palette =
        switch (asset.status) {
          CaseAssetStatus.available => (
            background: colorScheme.primaryContainer,
            foreground: colorScheme.onPrimaryContainer,
            icon: asset.type == CaseAssetType.screenshot
                ? Icons.image_outlined
                : asset.type == CaseAssetType.snapshot
                ? Icons.data_object_rounded
                : Icons.attach_file_rounded,
          ),
          CaseAssetStatus.expired => (
            background: const Color(0xFFFFF4E5),
            foreground: const Color(0xFF8D5C00),
            icon: Icons.history_toggle_off_rounded,
          ),
          CaseAssetStatus.missing => (
            background: const Color(0xFFFDECEA),
            foreground: const Color(0xFFB3261E),
            icon: Icons.hide_image_outlined,
          ),
        };

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _showAssetDialog(context, asset),
      child: Ink(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        palette.background,
                        palette.background.withValues(alpha: 0.45),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Icon(
                      palette.icon,
                      color: palette.foreground,
                      size: 42,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                asset.label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(asset.caption, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              Text(
                '${asset.capturedLabel} · ${asset.sourceLabel}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextSurface extends StatelessWidget {
  const _ContextSurface({required this.detail});

  final CaseDetailRecord detail;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Structured context',
      description:
          'High-signal context fields stay condensed so investigators can confirm user, environment, and release metadata without scanning the raw trace first.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: detail.contextFields
            .map((CaseContextField field) => _ContextRow(field: field))
            .toList(),
      ),
    );
  }
}

class _RecoverySurface extends StatelessWidget {
  const _RecoverySurface({required this.detail});

  final CaseDetailRecord detail;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: 'Recovery hints',
      description:
          'The workspace stays read-only, but any captured replay or support guidance is surfaced directly beside the evidence bundle.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: detail.recoveryHints
            .map(
              (String hint) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('• $hint'),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _CodePanel extends StatelessWidget {
  const _CodePanel({
    required this.title,
    required this.body,
    required this.onCopy,
  });

  final String title;
  final String body;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.value});

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

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final CaseLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final ({Color background, Color foreground}) palette =
        switch (entry.level) {
          CaseLogLevel.error => (
            background: const Color(0xFFFDECEA),
            foreground: const Color(0xFFB3261E),
          ),
          CaseLogLevel.warning => (
            background: const Color(0xFFFFF4E5),
            foreground: const Color(0xFF8D5C00),
          ),
          CaseLogLevel.info => (
            background: Theme.of(context).colorScheme.primaryContainer,
            foreground: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              entry.timeLabel,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(entry.message)),
        ],
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({required this.field});

  final CaseContextField field;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              field.label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(field.value)),
        ],
      ),
    );
  }
}

Future<void> _copyValue(
  BuildContext context, {
  required String label,
  required String value,
}) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$label copied')));
}

Future<void> _showAssetDialog(
  BuildContext context,
  CaseEvidenceAsset asset,
) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(asset.label),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    asset.type == CaseAssetType.screenshot
                        ? Icons.image_outlined
                        : asset.type == CaseAssetType.snapshot
                        ? Icons.data_object_rounded
                        : Icons.attach_file_rounded,
                    size: 56,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(asset.caption),
              const SizedBox(height: 12),
              SelectableText('${asset.capturedLabel} · ${asset.sourceLabel}'),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
