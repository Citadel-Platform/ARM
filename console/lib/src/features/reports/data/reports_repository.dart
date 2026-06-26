import 'package:arm_console/src/features/arm_data/data/arm_telemetry_gateway.dart';
import 'package:arm_console/src/features/explorer/domain/explorer_models.dart';
import 'package:arm_console/src/features/reports/domain/reports_models.dart';

abstract interface class ReportsRepository {
  Future<ReportsSnapshot> load({
    required ReportsQuery query,
    required List<ReportProjectReference> activeProjects,
  });
}

class AdaptiveReportsRepository implements ReportsRepository {
  const AdaptiveReportsRepository({ArmTelemetryGateway? gateway})
    : this._(gateway);

  const AdaptiveReportsRepository._(this._gateway);

  final ArmTelemetryGateway? _gateway;

  static final ArmTelemetryGateway _defaultGateway =
      FirebaseArmTelemetryGateway();

  ArmTelemetryGateway get _telemetryGateway => _gateway ?? _defaultGateway;

  @override
  Future<ReportsSnapshot> load({
    required ReportsQuery query,
    required List<ReportProjectReference> activeProjects,
  }) async {
    final _ReportsProjectPartition partition = _partitionProjects(
      activeProjects,
    );
    if (partition.remoteProjects.isEmpty) {
      return const InMemoryReportsRepository().load(
        query: query,
        activeProjects: activeProjects,
      );
    }

    final List<ReportsSnapshot> partialSnapshots = <ReportsSnapshot>[];
    if (partition.seededProjects.isNotEmpty) {
      partialSnapshots.add(
        await const InMemoryReportsRepository().load(
          query: query,
          activeProjects: partition.seededProjects,
        ),
      );
    }
    partialSnapshots.add(
      await _loadRemote(query: query, activeProjects: partition.remoteProjects),
    );

    return _mergeReportSnapshots(
      query: query,
      activeProjects: activeProjects,
      partialSnapshots: partialSnapshots,
    );
  }

  Future<ReportsSnapshot> _loadRemote({
    required ReportsQuery query,
    required List<ReportProjectReference> activeProjects,
  }) async {
    final List<ExplorerSeverity> allowedSeverities = ExplorerSeverity.values
        .where(query.severityFilter.allows)
        .toList();
    final DateTime since = DateTime.now().subtract(
      Duration(minutes: query.range.maxAgeMinutes),
    );
    final List<String> labels = _labelsForRange(query.range);
    final List<int> issueValues = List<int>.filled(labels.length, 0);
    final List<int> caseValues = List<int>.filled(labels.length, 0);
    final Map<ExplorerSeverity, int> distributionCounts =
        <ExplorerSeverity, int>{};
    final List<ReportRepeatOffender> offenders = <ReportRepeatOffender>[];
    final List<ReportProjectHotspot> hotspots = <ReportProjectHotspot>[];
    final List<ReportSpike> spikes = <ReportSpike>[];

    final List<ArmProjectTelemetry> telemetry = await _telemetryGateway
        .loadProjectTelemetry(
          projects: activeProjects
              .map(
                (ReportProjectReference project) => ArmMonitoredProject(
                  id: project.id,
                  name: project.name,
                  environmentLabel: project.environmentLabel,
                  firebaseConfig: project.firebaseConfig!,
                ),
              )
              .toList(),
          issueSince: since,
          caseSince: since,
        );

    for (final ArmProjectTelemetry projectTelemetry in telemetry) {
      final List<ArmCaseDocument> sortedCases =
          List<ArmCaseDocument>.from(projectTelemetry.cases)..sort(
            (ArmCaseDocument left, ArmCaseDocument right) =>
                right.createdAt.compareTo(left.createdAt),
          );
      final Map<String, ArmCaseDocument> latestCasesByIssue =
          <String, ArmCaseDocument>{};
      for (final ArmCaseDocument caseDocument in sortedCases) {
        latestCasesByIssue.putIfAbsent(
          caseDocument.issueId,
          () => caseDocument,
        );
      }

      final List<ArmIssueDocument> filteredIssues = projectTelemetry.issues
          .where((ArmIssueDocument issue) {
            return query.severityFilter.allows(
              _mapReportSeverity(issue.severity),
            );
          })
          .toList();
      final List<ArmCaseDocument> filteredCases = projectTelemetry.cases.where((
        ArmCaseDocument caseDocument,
      ) {
        return query.severityFilter.allows(
          _mapReportSeverity(caseDocument.severity),
        );
      }).toList();

      for (final ArmIssueDocument issue in filteredIssues) {
        final ExplorerSeverity severity = _mapReportSeverity(issue.severity);
        distributionCounts[severity] = (distributionCounts[severity] ?? 0) + 1;
        _accumulateReportBucket(issueValues, issue.lastSeenAt, since);
        final ArmCaseDocument? latestCase = latestCasesByIssue[issue.issueId];
        offenders.add(
          ReportRepeatOffender(
            issueId: issue.issueId,
            fingerprint: _reportFingerprint(issue, latestCase),
            projectId: projectTelemetry.project.id,
            projectLabel: projectTelemetry.project.name,
            severity: severity,
            caseCount: issue.caseCount,
            targetPath: IssuesQuery(
              projectId: projectTelemetry.project.id,
              range: query.range,
              severityFilter: query.severityFilter,
              selectedIssueId: issue.issueId,
            ).toLocation(),
          ),
        );
      }

      for (final ArmCaseDocument caseDocument in filteredCases) {
        _accumulateReportBucket(caseValues, caseDocument.createdAt, since);
      }

      final int issueVolume = filteredIssues.length;
      final int caseVolume = filteredCases.length;
      hotspots.add(
        ReportProjectHotspot(
          projectId: projectTelemetry.project.id,
          projectLabel: projectTelemetry.project.name,
          environmentLabel: projectTelemetry.project.environmentLabel,
          issueVolume: issueVolume,
          caseVolume: caseVolume,
          spikeLabel: _reportSpikeLabel(caseVolume, issueVolume),
          targetPath: IssuesQuery(
            projectId: projectTelemetry.project.id,
            range: query.range,
            severityFilter: query.severityFilter,
          ).toLocation(),
        ),
      );

      final ArmIssueDocument? topIssue = filteredIssues.isEmpty
          ? null
          : (List<ArmIssueDocument>.from(filteredIssues)..sort(
                  (ArmIssueDocument left, ArmIssueDocument right) =>
                      right.caseCount.compareTo(left.caseCount),
                ))
                .first;
      if (topIssue != null) {
        final ArmCaseDocument? latestCase =
            latestCasesByIssue[topIssue.issueId];
        spikes.add(
          ReportSpike(
            title:
                '${_reportIssueTitle(topIssue, latestCase)} intensified in ${projectTelemetry.project.name}',
            projectId: projectTelemetry.project.id,
            projectLabel: projectTelemetry.project.name,
            severity: _mapReportSeverity(topIssue.severity),
            changeLabel:
                '${topIssue.caseCount} linked case${topIssue.caseCount == 1 ? '' : 's'} in range',
            targetPath: CasesQuery(
              projectId: projectTelemetry.project.id,
              range: query.range,
              severityFilter: query.severityFilter,
              issueId: topIssue.issueId,
            ).toLocation(),
          ),
        );
      }
    }

    final List<ReportDistributionBucket> distribution = allowedSeverities.map((
      ExplorerSeverity severity,
    ) {
      return ReportDistributionBucket(
        label: severity.label,
        value: distributionCounts[severity] ?? 0,
        targetPath: IssuesQuery(
          range: query.range,
          severityFilter: switch (severity) {
            ExplorerSeverity.critical => ExplorerSeverityFilter.criticalOnly,
            ExplorerSeverity.high => ExplorerSeverityFilter.highOnly,
            ExplorerSeverity.medium => ExplorerSeverityFilter.mediumOnly,
          },
          projectId: query.projectId,
        ).toLocation(),
      );
    }).toList();

    offenders.sort((ReportRepeatOffender left, ReportRepeatOffender right) {
      final int severityCompare = right.severity.rank.compareTo(
        left.severity.rank,
      );
      if (severityCompare != 0) {
        return severityCompare;
      }
      return right.caseCount.compareTo(left.caseCount);
    });
    hotspots.sort((ReportProjectHotspot left, ReportProjectHotspot right) {
      final int issueCompare = right.issueVolume.compareTo(left.issueVolume);
      if (issueCompare != 0) {
        return issueCompare;
      }
      return right.caseVolume.compareTo(left.caseVolume);
    });
    spikes.sort((ReportSpike left, ReportSpike right) {
      final int severityCompare = right.severity.rank.compareTo(
        left.severity.rank,
      );
      if (severityCompare != 0) {
        return severityCompare;
      }
      return left.projectLabel.compareTo(right.projectLabel);
    });

    return ReportsSnapshot(
      query: query,
      activeProjects: activeProjects,
      issueVolumeTrend: ReportTrendSeries(
        title: 'Issue volume',
        subtitle:
            'Repeated fingerprints by ${_rangeNarrative(query.range)} so spikes are visible before they turn into queue churn.',
        targetPath: IssuesQuery(
          range: query.range,
          severityFilter: query.severityFilter,
          projectId: query.projectId,
        ).toLocation(),
        points: _toTrendPoints(labels, issueValues),
      ),
      caseFrequencyTrend: ReportTrendSeries(
        title: 'Case frequency',
        subtitle:
            'Case creation pace helps confirm whether the current pressure is broad incident churn or a small number of repeated offenders.',
        targetPath: CasesQuery(
          range: query.range,
          severityFilter: query.severityFilter,
          projectId: query.projectId,
        ).toLocation(),
        points: _toTrendPoints(labels, caseValues),
      ),
      severityDistribution: distribution,
      repeatOffenders: offenders.take(5).toList(),
      hotspots: hotspots.take(4).toList(),
      spikes: spikes.take(4).toList(),
      crossProjectComparisonAvailable: activeProjects.length > 1,
    );
  }
}

class InMemoryReportsRepository implements ReportsRepository {
  const InMemoryReportsRepository();

  @override
  Future<ReportsSnapshot> load({
    required ReportsQuery query,
    required List<ReportProjectReference> activeProjects,
  }) async {
    final List<ExplorerSeverity> allowedSeverities = ExplorerSeverity.values
        .where(query.severityFilter.allows)
        .toList();
    final List<String> labels = _labelsForRange(query.range);
    final List<int> issueValues = List<int>.filled(labels.length, 0);
    final List<int> caseValues = List<int>.filled(labels.length, 0);
    final List<ReportDistributionBucket> distribution =
        <ReportDistributionBucket>[];
    final List<ReportRepeatOffender> offenders = <ReportRepeatOffender>[];
    final List<ReportProjectHotspot> hotspots = <ReportProjectHotspot>[];
    final List<ReportSpike> spikes = <ReportSpike>[];

    for (final ReportProjectReference project in activeProjects) {
      final _ProjectReportSeed seed = _projectSeeds[project.id] ?? _emptySeed();
      final List<int> projectIssueValues = _valuesForRange(
        query.range,
        seed.issueTrendBySeverity,
        allowedSeverities,
      );
      final List<int> projectCaseValues = _valuesForRange(
        query.range,
        seed.caseTrendBySeverity,
        allowedSeverities,
      );
      for (int index = 0; index < labels.length; index++) {
        issueValues[index] += projectIssueValues[index];
        caseValues[index] += projectCaseValues[index];
      }

      offenders.addAll(
        seed.repeatOffenders
            .where((_RepeatOffenderSeed offender) {
              return query.severityFilter.allows(offender.severity);
            })
            .map(
              (_RepeatOffenderSeed offender) => ReportRepeatOffender(
                issueId: offender.issueId,
                fingerprint: offender.fingerprint,
                projectId: project.id,
                projectLabel: project.name,
                severity: offender.severity,
                caseCount: offender.caseCount,
                targetPath: IssuesQuery(
                  projectId: project.id,
                  range: query.range,
                  severityFilter: query.severityFilter,
                  search: offender.fingerprint,
                  selectedIssueId: offender.issueId,
                ).toLocation(),
              ),
            ),
      );

      final int issueVolume = projectIssueValues.fold(
        0,
        (int sum, int value) => sum + value,
      );
      final int caseVolume = projectCaseValues.fold(
        0,
        (int sum, int value) => sum + value,
      );
      hotspots.add(
        ReportProjectHotspot(
          projectId: project.id,
          projectLabel: project.name,
          environmentLabel: project.environmentLabel,
          issueVolume: issueVolume,
          caseVolume: caseVolume,
          spikeLabel: seed.hotspotLabel,
          targetPath: IssuesQuery(
            projectId: project.id,
            range: query.range,
            severityFilter: query.severityFilter,
          ).toLocation(),
        ),
      );

      spikes.addAll(
        seed.spikes
            .where(
              (_SpikeSeed spike) => query.severityFilter.allows(spike.severity),
            )
            .map(
              (_SpikeSeed spike) => ReportSpike(
                title: spike.title,
                projectId: project.id,
                projectLabel: project.name,
                severity: spike.severity,
                changeLabel: spike.changeLabel,
                targetPath: spike.targetPath(query.range, project.id),
              ),
            ),
      );
    }

    for (final ExplorerSeverity severity in allowedSeverities) {
      final int value = activeProjects.fold(0, (
        int total,
        ReportProjectReference project,
      ) {
        final _ProjectReportSeed seed =
            _projectSeeds[project.id] ?? _emptySeed();
        return total + (seed.severityCounts[severity] ?? 0);
      });
      distribution.add(
        ReportDistributionBucket(
          label: severity.label,
          value: value,
          targetPath: IssuesQuery(
            range: query.range,
            severityFilter: switch (severity) {
              ExplorerSeverity.critical => ExplorerSeverityFilter.criticalOnly,
              ExplorerSeverity.high => ExplorerSeverityFilter.highOnly,
              ExplorerSeverity.medium => ExplorerSeverityFilter.mediumOnly,
            },
            projectId: query.projectId,
          ).toLocation(),
        ),
      );
    }

    offenders.sort((ReportRepeatOffender left, ReportRepeatOffender right) {
      final int severityCompare = right.severity.rank.compareTo(
        left.severity.rank,
      );
      if (severityCompare != 0) {
        return severityCompare;
      }
      return right.caseCount.compareTo(left.caseCount);
    });

    hotspots.sort((ReportProjectHotspot left, ReportProjectHotspot right) {
      final int issueCompare = right.issueVolume.compareTo(left.issueVolume);
      if (issueCompare != 0) {
        return issueCompare;
      }
      return right.caseVolume.compareTo(left.caseVolume);
    });

    spikes.sort((ReportSpike left, ReportSpike right) {
      final int severityCompare = right.severity.rank.compareTo(
        left.severity.rank,
      );
      if (severityCompare != 0) {
        return severityCompare;
      }
      return left.projectLabel.compareTo(right.projectLabel);
    });

    return ReportsSnapshot(
      query: query,
      activeProjects: activeProjects,
      issueVolumeTrend: ReportTrendSeries(
        title: 'Issue volume',
        subtitle:
            'Repeated fingerprints by ${_rangeNarrative(query.range)} so spikes are visible before they turn into queue churn.',
        targetPath: IssuesQuery(
          range: query.range,
          severityFilter: query.severityFilter,
          projectId: query.projectId,
        ).toLocation(),
        points: _toTrendPoints(labels, issueValues),
      ),
      caseFrequencyTrend: ReportTrendSeries(
        title: 'Case frequency',
        subtitle:
            'Case creation pace helps confirm whether the current pressure is broad incident churn or a small number of repeated offenders.',
        targetPath: CasesQuery(
          range: query.range,
          severityFilter: query.severityFilter,
          projectId: query.projectId,
        ).toLocation(),
        points: _toTrendPoints(labels, caseValues),
      ),
      severityDistribution: distribution,
      repeatOffenders: offenders.take(5).toList(),
      hotspots: hotspots.take(4).toList(),
      spikes: spikes.take(4).toList(),
      crossProjectComparisonAvailable: activeProjects.length > 1,
    );
  }

  List<ReportTrendPoint> _toTrendPoints(List<String> labels, List<int> values) {
    return List<ReportTrendPoint>.generate(labels.length, (int index) {
      return ReportTrendPoint(label: labels[index], value: values[index]);
    });
  }
}

List<ReportTrendPoint> _toTrendPoints(List<String> labels, List<int> values) {
  return List<ReportTrendPoint>.generate(labels.length, (int index) {
    return ReportTrendPoint(label: labels[index], value: values[index]);
  });
}

class _ReportsProjectPartition {
  const _ReportsProjectPartition({
    required this.remoteProjects,
    required this.seededProjects,
  });

  final List<ReportProjectReference> remoteProjects;
  final List<ReportProjectReference> seededProjects;
}

_ReportsProjectPartition _partitionProjects(
  List<ReportProjectReference> projects,
) {
  final List<ReportProjectReference> remoteProjects =
      <ReportProjectReference>[];
  final List<ReportProjectReference> seededProjects =
      <ReportProjectReference>[];
  for (final ReportProjectReference project in projects) {
    if (isRemoteCapableConfig(project.firebaseConfig)) {
      remoteProjects.add(project);
    } else {
      seededProjects.add(project);
    }
  }
  return _ReportsProjectPartition(
    remoteProjects: remoteProjects,
    seededProjects: seededProjects,
  );
}

ReportsSnapshot _mergeReportSnapshots({
  required ReportsQuery query,
  required List<ReportProjectReference> activeProjects,
  required List<ReportsSnapshot> partialSnapshots,
}) {
  if (partialSnapshots.length == 1) {
    return partialSnapshots.single;
  }

  final List<String> labels = partialSnapshots.first.issueVolumeTrend.points
      .map((ReportTrendPoint point) => point.label)
      .toList();
  final List<int> issueValues = List<int>.filled(labels.length, 0);
  final List<int> caseValues = List<int>.filled(labels.length, 0);
  final Map<String, int> distributionValues = <String, int>{};
  final List<ReportRepeatOffender> offenders = partialSnapshots
      .expand((ReportsSnapshot snapshot) => snapshot.repeatOffenders)
      .toList();
  final List<ReportProjectHotspot> hotspots = partialSnapshots
      .expand((ReportsSnapshot snapshot) => snapshot.hotspots)
      .toList();
  final List<ReportSpike> spikes = partialSnapshots
      .expand((ReportsSnapshot snapshot) => snapshot.spikes)
      .toList();

  for (final ReportsSnapshot snapshot in partialSnapshots) {
    for (int index = 0; index < labels.length; index++) {
      issueValues[index] += snapshot.issueVolumeTrend.points[index].value;
      caseValues[index] += snapshot.caseFrequencyTrend.points[index].value;
    }
    for (final ReportDistributionBucket bucket
        in snapshot.severityDistribution) {
      distributionValues[bucket.label] =
          (distributionValues[bucket.label] ?? 0) + bucket.value;
    }
  }

  final List<ReportDistributionBucket> distribution = partialSnapshots
      .first
      .severityDistribution
      .map((ReportDistributionBucket bucket) {
        return ReportDistributionBucket(
          label: bucket.label,
          value: distributionValues[bucket.label] ?? 0,
          targetPath: bucket.targetPath,
        );
      })
      .toList();

  offenders.sort((ReportRepeatOffender left, ReportRepeatOffender right) {
    final int severityCompare = right.severity.rank.compareTo(
      left.severity.rank,
    );
    if (severityCompare != 0) {
      return severityCompare;
    }
    return right.caseCount.compareTo(left.caseCount);
  });
  hotspots.sort((ReportProjectHotspot left, ReportProjectHotspot right) {
    final int issueCompare = right.issueVolume.compareTo(left.issueVolume);
    if (issueCompare != 0) {
      return issueCompare;
    }
    return right.caseVolume.compareTo(left.caseVolume);
  });
  spikes.sort((ReportSpike left, ReportSpike right) {
    final int severityCompare = right.severity.rank.compareTo(
      left.severity.rank,
    );
    if (severityCompare != 0) {
      return severityCompare;
    }
    return left.projectLabel.compareTo(right.projectLabel);
  });

  return ReportsSnapshot(
    query: query,
    activeProjects: activeProjects,
    issueVolumeTrend: ReportTrendSeries(
      title: 'Issue volume',
      subtitle:
          'Repeated fingerprints by ${_rangeNarrative(query.range)} so spikes are visible before they turn into queue churn.',
      targetPath: IssuesQuery(
        range: query.range,
        severityFilter: query.severityFilter,
        projectId: query.projectId,
      ).toLocation(),
      points: _toTrendPoints(labels, issueValues),
    ),
    caseFrequencyTrend: ReportTrendSeries(
      title: 'Case frequency',
      subtitle:
          'Case creation pace helps confirm whether the current pressure is broad incident churn or a small number of repeated offenders.',
      targetPath: CasesQuery(
        range: query.range,
        severityFilter: query.severityFilter,
        projectId: query.projectId,
      ).toLocation(),
      points: _toTrendPoints(labels, caseValues),
    ),
    severityDistribution: distribution,
    repeatOffenders: offenders.take(5).toList(),
    hotspots: hotspots.take(4).toList(),
    spikes: spikes.take(4).toList(),
    crossProjectComparisonAvailable: activeProjects.length > 1,
  );
}

ExplorerSeverity _mapReportSeverity(String rawSeverity) {
  return switch (rawSeverity) {
    'critical' || 'serious' => ExplorerSeverity.critical,
    'moderate' => ExplorerSeverity.high,
    _ => ExplorerSeverity.medium,
  };
}

void _accumulateReportBucket(
  List<int> buckets,
  DateTime timestamp,
  DateTime since,
) {
  final Duration window = DateTime.now().difference(since);
  if (window.inSeconds <= 0) {
    buckets[buckets.length - 1] += 1;
    return;
  }
  final double ratio =
      timestamp.difference(since).inMilliseconds / window.inMilliseconds;
  final int index = (ratio * buckets.length).floor().clamp(
    0,
    buckets.length - 1,
  );
  buckets[index] += 1;
}

String _reportFingerprint(ArmIssueDocument issue, ArmCaseDocument? latestCase) {
  final String fingerprint = latestCase?.fingerprint.trim() ?? '';
  if (fingerprint.isNotEmpty) {
    return fingerprint;
  }
  if (issue.feature.isNotEmpty && issue.operation.isNotEmpty) {
    return '${issue.feature}/${issue.operation}';
  }
  return issue.issueId;
}

String _reportIssueTitle(ArmIssueDocument issue, ArmCaseDocument? latestCase) {
  if (issue.feature.isNotEmpty && issue.operation.isNotEmpty) {
    return '${_reportHeadline(issue.feature)} ${_reportHeadline(issue.operation)} incident';
  }
  if (latestCase != null && latestCase.message.trim().isNotEmpty) {
    return latestCase.message.trim();
  }
  return issue.issueId;
}

String _reportHeadline(String value) {
  return value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((String part) => part.isNotEmpty)
      .map((String part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _reportSpikeLabel(int caseVolume, int issueVolume) {
  if (caseVolume == 0 && issueVolume == 0) {
    return 'Quiet window';
  }
  if (caseVolume >= issueVolume * 2 && caseVolume > 3) {
    return 'Case churn rising';
  }
  if (issueVolume > caseVolume) {
    return 'Fingerprint spread climbing';
  }
  return 'Stable but active';
}

class _ProjectReportSeed {
  const _ProjectReportSeed({
    required this.issueTrendBySeverity,
    required this.caseTrendBySeverity,
    required this.severityCounts,
    required this.repeatOffenders,
    required this.spikes,
    required this.hotspotLabel,
  });

  final Map<ExplorerSeverity, List<int>> issueTrendBySeverity;
  final Map<ExplorerSeverity, List<int>> caseTrendBySeverity;
  final Map<ExplorerSeverity, int> severityCounts;
  final List<_RepeatOffenderSeed> repeatOffenders;
  final List<_SpikeSeed> spikes;
  final String hotspotLabel;
}

class _RepeatOffenderSeed {
  const _RepeatOffenderSeed({
    required this.issueId,
    required this.fingerprint,
    required this.severity,
    required this.caseCount,
  });

  final String issueId;
  final String fingerprint;
  final ExplorerSeverity severity;
  final int caseCount;
}

class _SpikeSeed {
  const _SpikeSeed({
    required this.title,
    required this.severity,
    required this.changeLabel,
    required this.routeKind,
    this.issueId,
  });

  final String title;
  final ExplorerSeverity severity;
  final String changeLabel;
  final _SpikeRouteKind routeKind;
  final String? issueId;

  String targetPath(ExplorerDateRange range, String projectId) {
    return switch (routeKind) {
      _SpikeRouteKind.issues => IssuesQuery(
        projectId: projectId,
        range: range,
        severityFilter: switch (severity) {
          ExplorerSeverity.critical => ExplorerSeverityFilter.criticalOnly,
          ExplorerSeverity.high => ExplorerSeverityFilter.highOnly,
          ExplorerSeverity.medium => ExplorerSeverityFilter.mediumOnly,
        },
        selectedIssueId: issueId,
      ).toLocation(),
      _SpikeRouteKind.cases => CasesQuery(
        projectId: projectId,
        range: range,
        severityFilter: switch (severity) {
          ExplorerSeverity.critical => ExplorerSeverityFilter.criticalOnly,
          ExplorerSeverity.high => ExplorerSeverityFilter.highOnly,
          ExplorerSeverity.medium => ExplorerSeverityFilter.mediumOnly,
        },
        issueId: issueId,
      ).toLocation(),
    };
  }
}

enum _SpikeRouteKind { issues, cases }

const Map<String, _ProjectReportSeed> _projectSeeds =
    <String, _ProjectReportSeed>{
      'core-platform': _ProjectReportSeed(
        issueTrendBySeverity: <ExplorerSeverity, List<int>>{
          ExplorerSeverity.critical: <int>[1, 2, 2, 3, 3, 4, 3],
          ExplorerSeverity.high: <int>[1, 1, 1, 2, 2, 2, 1],
          ExplorerSeverity.medium: <int>[0, 1, 0, 1, 1, 0, 1],
        },
        caseTrendBySeverity: <ExplorerSeverity, List<int>>{
          ExplorerSeverity.critical: <int>[2, 2, 3, 3, 4, 5, 4],
          ExplorerSeverity.high: <int>[1, 1, 2, 2, 2, 3, 2],
          ExplorerSeverity.medium: <int>[0, 1, 0, 1, 1, 1, 0],
        },
        severityCounts: <ExplorerSeverity, int>{
          ExplorerSeverity.critical: 12,
          ExplorerSeverity.high: 8,
          ExplorerSeverity.medium: 4,
        },
        repeatOffenders: <_RepeatOffenderSeed>[
          _RepeatOffenderSeed(
            issueId: 'issue-save-draft-timeout',
            fingerprint: 'saveDraft/network-timeout',
            severity: ExplorerSeverity.critical,
            caseCount: 11,
          ),
          _RepeatOffenderSeed(
            issueId: 'issue-checkout-missing-snapshot',
            fingerprint: 'checkout/missing-snapshot',
            severity: ExplorerSeverity.high,
            caseCount: 4,
          ),
        ],
        spikes: <_SpikeSeed>[
          _SpikeSeed(
            title: 'Save failures spiked after the release cut',
            severity: ExplorerSeverity.critical,
            changeLabel: '+42% in the latest slice',
            routeKind: _SpikeRouteKind.cases,
            issueId: 'issue-save-draft-timeout',
          ),
          _SpikeSeed(
            title: 'Recovery payload gaps climbed in checkout',
            severity: ExplorerSeverity.high,
            changeLabel: '+3 cases over baseline',
            routeKind: _SpikeRouteKind.cases,
            issueId: 'issue-checkout-missing-snapshot',
          ),
        ],
        hotspotLabel: 'Release-linked issue churn',
      ),
      'customer-ops': _ProjectReportSeed(
        issueTrendBySeverity: <ExplorerSeverity, List<int>>{
          ExplorerSeverity.critical: <int>[0, 1, 1, 1, 1, 1, 1],
          ExplorerSeverity.high: <int>[1, 2, 2, 3, 3, 4, 3],
          ExplorerSeverity.medium: <int>[1, 1, 1, 1, 1, 2, 1],
        },
        caseTrendBySeverity: <ExplorerSeverity, List<int>>{
          ExplorerSeverity.critical: <int>[1, 1, 1, 1, 1, 2, 1],
          ExplorerSeverity.high: <int>[2, 2, 3, 3, 4, 5, 4],
          ExplorerSeverity.medium: <int>[1, 1, 1, 1, 2, 2, 1],
        },
        severityCounts: <ExplorerSeverity, int>{
          ExplorerSeverity.critical: 6,
          ExplorerSeverity.high: 11,
          ExplorerSeverity.medium: 6,
        },
        repeatOffenders: <_RepeatOffenderSeed>[
          _RepeatOffenderSeed(
            issueId: 'issue-auth-session-expired',
            fingerprint: 'auth/session-expired',
            severity: ExplorerSeverity.high,
            caseCount: 8,
          ),
          _RepeatOffenderSeed(
            issueId: 'issue-profile-invalid-country',
            fingerprint: 'profile/invalid-country',
            severity: ExplorerSeverity.medium,
            caseCount: 3,
          ),
        ],
        spikes: <_SpikeSeed>[
          _SpikeSeed(
            title: 'Session expiry loops widened after auth refresh',
            severity: ExplorerSeverity.high,
            changeLabel: '+5 repeated reports',
            routeKind: _SpikeRouteKind.issues,
            issueId: 'issue-auth-session-expired',
          ),
        ],
        hotspotLabel: 'Authentication-driven case churn',
      ),
      'innovation-lab': _ProjectReportSeed(
        issueTrendBySeverity: <ExplorerSeverity, List<int>>{
          ExplorerSeverity.critical: <int>[0, 0, 0, 0, 0, 0, 0],
          ExplorerSeverity.high: <int>[0, 0, 0, 0, 0, 1, 0],
          ExplorerSeverity.medium: <int>[0, 1, 1, 0, 1, 1, 1],
        },
        caseTrendBySeverity: <ExplorerSeverity, List<int>>{
          ExplorerSeverity.critical: <int>[0, 0, 0, 0, 0, 0, 0],
          ExplorerSeverity.high: <int>[0, 0, 0, 0, 0, 1, 0],
          ExplorerSeverity.medium: <int>[1, 1, 1, 0, 1, 1, 1],
        },
        severityCounts: <ExplorerSeverity, int>{
          ExplorerSeverity.critical: 0,
          ExplorerSeverity.high: 1,
          ExplorerSeverity.medium: 5,
        },
        repeatOffenders: <_RepeatOffenderSeed>[
          _RepeatOffenderSeed(
            issueId: 'issue-sandbox-replay-desync',
            fingerprint: 'sandbox/replay-desync',
            severity: ExplorerSeverity.medium,
            caseCount: 2,
          ),
        ],
        spikes: <_SpikeSeed>[
          _SpikeSeed(
            title: 'Replay desync reappeared in innovation previews',
            severity: ExplorerSeverity.medium,
            changeLabel: 'Low-volume but persistent',
            routeKind: _SpikeRouteKind.issues,
            issueId: 'issue-sandbox-replay-desync',
          ),
        ],
        hotspotLabel: 'Validation-only noise floor',
      ),
    };

_ProjectReportSeed _emptySeed() {
  return const _ProjectReportSeed(
    issueTrendBySeverity: <ExplorerSeverity, List<int>>{
      ExplorerSeverity.critical: <int>[0, 0, 0, 0, 0, 0, 0],
      ExplorerSeverity.high: <int>[0, 0, 0, 0, 0, 0, 0],
      ExplorerSeverity.medium: <int>[0, 0, 0, 0, 0, 0, 0],
    },
    caseTrendBySeverity: <ExplorerSeverity, List<int>>{
      ExplorerSeverity.critical: <int>[0, 0, 0, 0, 0, 0, 0],
      ExplorerSeverity.high: <int>[0, 0, 0, 0, 0, 0, 0],
      ExplorerSeverity.medium: <int>[0, 0, 0, 0, 0, 0, 0],
    },
    severityCounts: <ExplorerSeverity, int>{},
    repeatOffenders: <_RepeatOffenderSeed>[],
    spikes: <_SpikeSeed>[],
    hotspotLabel: 'No visible activity',
  );
}

List<String> _labelsForRange(ExplorerDateRange range) {
  return switch (range) {
    ExplorerDateRange.last24Hours => <String>[
      '00h',
      '04h',
      '08h',
      '12h',
      '16h',
      '20h',
    ],
    ExplorerDateRange.last7Days => <String>[
      'Day 1',
      'Day 2',
      'Day 3',
      'Day 4',
      'Day 5',
      'Day 6',
      'Day 7',
    ],
    ExplorerDateRange.last30Days => <String>[
      'Week 1',
      'Week 2',
      'Week 3',
      'Week 4',
    ],
  };
}

String _rangeNarrative(ExplorerDateRange range) {
  return switch (range) {
    ExplorerDateRange.last24Hours => '4-hour slices',
    ExplorerDateRange.last7Days => 'day',
    ExplorerDateRange.last30Days => 'week',
  };
}

List<int> _valuesForRange(
  ExplorerDateRange range,
  Map<ExplorerSeverity, List<int>> valuesBySeverity,
  List<ExplorerSeverity> allowedSeverities,
) {
  final List<int> merged = List<int>.filled(7, 0);
  for (final ExplorerSeverity severity in allowedSeverities) {
    final List<int> source =
        valuesBySeverity[severity] ?? const <int>[0, 0, 0, 0, 0, 0, 0];
    for (int index = 0; index < merged.length; index++) {
      merged[index] += source[index];
    }
  }

  return switch (range) {
    ExplorerDateRange.last24Hours => merged.sublist(1),
    ExplorerDateRange.last7Days => merged,
    ExplorerDateRange.last30Days => <int>[
      merged[0] + merged[1],
      merged[2] + merged[3],
      merged[4] + merged[5],
      merged[6] * 2,
    ],
  };
}
