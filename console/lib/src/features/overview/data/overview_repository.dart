import 'package:arm_console/src/features/arm_data/data/arm_telemetry_gateway.dart';
import 'package:arm_console/src/features/overview/domain/overview_models.dart';

abstract interface class OverviewRepository {
  Future<OverviewSnapshot> load({
    required OverviewQuery query,
    required List<OverviewProjectReference> activeProjects,
  });
}

class AdaptiveOverviewRepository implements OverviewRepository {
  const AdaptiveOverviewRepository({ArmTelemetryGateway? gateway})
    : this._(gateway);

  const AdaptiveOverviewRepository._(this._gateway);

  final ArmTelemetryGateway? _gateway;

  static final ArmTelemetryGateway _defaultGateway =
      FirebaseArmTelemetryGateway();

  ArmTelemetryGateway get _telemetryGateway => _gateway ?? _defaultGateway;

  @override
  Future<OverviewSnapshot> load({
    required OverviewQuery query,
    required List<OverviewProjectReference> activeProjects,
  }) async {
    final _OverviewProjectPartition partition = _partitionProjects(
      activeProjects,
    );
    if (partition.remoteProjects.isEmpty) {
      return const InMemoryOverviewRepository().load(
        query: query,
        activeProjects: activeProjects,
      );
    }

    final List<OverviewSnapshot> partialSnapshots = <OverviewSnapshot>[];
    if (partition.seededProjects.isNotEmpty) {
      partialSnapshots.add(
        await const InMemoryOverviewRepository().load(
          query: query,
          activeProjects: partition.seededProjects,
        ),
      );
    }

    partialSnapshots.add(
      await _loadRemote(query: query, activeProjects: partition.remoteProjects),
    );

    return _mergeSnapshots(
      query: query,
      activeProjects: activeProjects,
      partialSnapshots: partialSnapshots,
    );
  }

  Future<OverviewSnapshot> _loadRemote({
    required OverviewQuery query,
    required List<OverviewProjectReference> activeProjects,
  }) async {
    final DateTime since = _sinceForOverviewRange(query.dateRange);
    final List<ArmProjectTelemetry> telemetry = await _telemetryGateway
        .loadProjectTelemetry(
          projects: activeProjects
              .map(
                (OverviewProjectReference project) => ArmMonitoredProject(
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

    int criticalIssues = 0;
    int openCases = 0;
    int freshIncidents = 0;
    int healthyProjects = 0;
    int criticalMix = 0;
    int highMix = 0;
    int mediumMix = 0;
    final List<OverviewQueueItem> queueItems = <OverviewQueueItem>[];
    final List<OverviewPostureCard> postureCards = <OverviewPostureCard>[];
    final List<int> issueTrendValues = List<int>.filled(7, 0);
    final List<int> severityTrendValues = List<int>.filled(7, 0);

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

      int projectCriticalIssues = 0;
      for (final ArmIssueDocument issue in projectTelemetry.issues) {
        final OverviewSeverity severity = _mapOverviewSeverity(issue.severity);
        final ArmCaseDocument? latestCase = latestCasesByIssue[issue.issueId];
        if (severity == OverviewSeverity.critical) {
          criticalIssues += 1;
          projectCriticalIssues += 1;
          criticalMix += 1;
        } else if (severity == OverviewSeverity.high) {
          highMix += 1;
        } else {
          mediumMix += 1;
        }

        if (_allowsOverviewSeverity(query.severityFilter, severity)) {
          queueItems.add(
            OverviewQueueItem(
              title: _overviewIssueTitle(issue, latestCase),
              subtitle:
                  '${issue.caseCount} linked case${issue.caseCount == 1 ? '' : 's'} · ${query.dateRange.label}',
              projectLabel: projectTelemetry.project.name,
              severity: severity,
              routePath:
                  '/issues?project=${projectTelemetry.project.id}&issueId=${issue.issueId}',
              incidentCount: issue.caseCount,
            ),
          );
        }

        _accumulateBucket(issueTrendValues, issue.lastSeenAt, since);
      }

      final int projectOpenCases = projectTelemetry.cases.where((
        ArmCaseDocument item,
      ) {
        return _deriveOverviewCaseStatus(item) != _OverviewCaseStatus.stale;
      }).length;
      openCases += projectOpenCases;
      freshIncidents += projectTelemetry.issues.where((ArmIssueDocument issue) {
        return !issue.firstSeenAt.isBefore(since);
      }).length;
      if (projectCriticalIssues == 0) {
        healthyProjects += 1;
      }

      for (final ArmCaseDocument caseDocument in projectTelemetry.cases) {
        final OverviewSeverity severity = _mapOverviewSeverity(
          caseDocument.severity,
        );
        if (severity != OverviewSeverity.medium) {
          _accumulateBucket(severityTrendValues, caseDocument.createdAt, since);
        }
      }

      postureCards.add(
        _buildPostureCard(
          projectTelemetry: projectTelemetry,
          criticalIssueCount: projectCriticalIssues,
          openCaseCount: projectOpenCases,
        ),
      );
    }

    queueItems.sort((OverviewQueueItem left, OverviewQueueItem right) {
      final int severityCompare = _overviewSeverityRank(
        right.severity,
      ).compareTo(_overviewSeverityRank(left.severity));
      if (severityCompare != 0) {
        return severityCompare;
      }
      return right.incidentCount.compareTo(left.incidentCount);
    });

    final OverviewSeverityMix severityMix = switch (query.severityFilter) {
      OverviewSeverityFilter.criticalOnly => OverviewSeverityMix(
        critical: criticalMix,
        high: 0,
        medium: 0,
      ),
      OverviewSeverityFilter.criticalAndHigh => OverviewSeverityMix(
        critical: criticalMix,
        high: highMix,
        medium: mediumMix,
      ),
    };

    return OverviewSnapshot(
      query: query,
      activeProjects: activeProjects,
      counts: OverviewCounts(
        criticalIssues: criticalIssues,
        openCases: openCases,
        freshIncidents: freshIncidents,
        healthyProjects: healthyProjects,
      ),
      urgentItems: queueItems.take(5).toList(),
      postureCards: postureCards.take(4).toList(),
      issueVolumeTrend: OverviewTrendSeries(
        title: 'Issue volume',
        subtitle: 'Escalation-worthy fingerprints by day.',
        targetPath: '/issues',
        points: _toOverviewTrendPoints(issueTrendValues),
      ),
      severityTrend: OverviewTrendSeries(
        title: 'Severity pressure',
        subtitle: 'Critical and high-severity case pressure over time.',
        targetPath: '/reports',
        points: _toOverviewTrendPoints(severityTrendValues),
      ),
      severityMix: severityMix,
      overloaded: queueItems.length >= 4 || criticalIssues >= 10,
    );
  }
}

class InMemoryOverviewRepository implements OverviewRepository {
  const InMemoryOverviewRepository();

  @override
  Future<OverviewSnapshot> load({
    required OverviewQuery query,
    required List<OverviewProjectReference> activeProjects,
  }) async {
    final int multiplier = query.dateRange.multiplier;
    int criticalIssues = 0;
    int openCases = 0;
    int freshIncidents = 0;
    int healthyProjects = 0;
    int criticalMix = 0;
    int highMix = 0;
    int mediumMix = 0;

    final List<OverviewQueueItem> queueItems = <OverviewQueueItem>[];
    final List<OverviewPostureCard> postureCards = <OverviewPostureCard>[];
    final List<int> issueTrendValues = <int>[0, 0, 0, 0, 0, 0, 0];
    final List<int> severityTrendValues = <int>[0, 0, 0, 0, 0, 0, 0];

    for (final OverviewProjectReference project in activeProjects) {
      final _ProjectSeed seed =
          _projectSeeds[project.id] ?? _emptySeed(project.id);
      criticalIssues += seed.criticalIssues * multiplier;
      openCases += seed.openCases * multiplier;
      freshIncidents += seed.freshIncidents * multiplier;
      if (seed.criticalIssues == 0) {
        healthyProjects += 1;
      }

      criticalMix += seed.severityMix.critical * multiplier;
      highMix += seed.severityMix.high * multiplier;
      mediumMix += seed.severityMix.medium * multiplier;

      if (_allowsSeverity(query.severityFilter, seed.primarySeverity)) {
        queueItems.addAll(
          seed.queueItems.map(
            (_QueueSeed queue) => OverviewQueueItem(
              title: queue.title,
              subtitle: '${queue.subtitle} · ${query.dateRange.label}',
              projectLabel: project.name,
              severity: queue.severity,
              routePath: queue.routePath,
              incidentCount: queue.incidentCount * multiplier,
            ),
          ),
        );
      }

      postureCards.addAll(
        seed.postureCards.map(
          (_PostureSeed posture) => OverviewPostureCard(
            title: posture.title,
            description: posture.description,
            targetPath: posture.targetPath,
            tone: posture.tone,
          ),
        ),
      );

      for (int index = 0; index < issueTrendValues.length; index++) {
        issueTrendValues[index] += seed.issueTrend[index] * multiplier;
        severityTrendValues[index] += seed.severityTrend[index] * multiplier;
      }
    }

    final List<OverviewQueueItem> filteredQueueItems =
        queueItems
            .where(
              (OverviewQueueItem item) =>
                  _allowsSeverity(query.severityFilter, item.severity),
            )
            .toList()
          ..sort((OverviewQueueItem left, OverviewQueueItem right) {
            final int severityCompare = _severityRank(
              right.severity,
            ).compareTo(_severityRank(left.severity));
            if (severityCompare != 0) {
              return severityCompare;
            }
            return right.incidentCount.compareTo(left.incidentCount);
          });

    final OverviewSeverityMix severityMix = switch (query.severityFilter) {
      OverviewSeverityFilter.criticalOnly => OverviewSeverityMix(
        critical: criticalMix,
        high: 0,
        medium: 0,
      ),
      OverviewSeverityFilter.criticalAndHigh => OverviewSeverityMix(
        critical: criticalMix,
        high: highMix,
        medium: mediumMix,
      ),
    };

    return OverviewSnapshot(
      query: query,
      activeProjects: activeProjects,
      counts: OverviewCounts(
        criticalIssues: criticalIssues,
        openCases: openCases,
        freshIncidents: freshIncidents,
        healthyProjects: healthyProjects,
      ),
      urgentItems: filteredQueueItems.take(5).toList(),
      postureCards: postureCards.take(4).toList(),
      issueVolumeTrend: OverviewTrendSeries(
        title: 'Issue volume',
        subtitle: 'Escalation-worthy fingerprints by day.',
        targetPath: '/issues',
        points: _toTrendPoints(issueTrendValues),
      ),
      severityTrend: OverviewTrendSeries(
        title: 'Severity pressure',
        subtitle: 'Critical and high-severity case pressure over time.',
        targetPath: '/reports',
        points: _toTrendPoints(severityTrendValues),
      ),
      severityMix: severityMix,
      overloaded: filteredQueueItems.length >= 4 || criticalIssues >= 10,
    );
  }

  bool _allowsSeverity(
    OverviewSeverityFilter filter,
    OverviewSeverity severity,
  ) {
    return switch (filter) {
      OverviewSeverityFilter.criticalOnly =>
        severity == OverviewSeverity.critical,
      OverviewSeverityFilter.criticalAndHigh =>
        severity != OverviewSeverity.medium,
    };
  }

  int _severityRank(OverviewSeverity severity) {
    return switch (severity) {
      OverviewSeverity.critical => 3,
      OverviewSeverity.high => 2,
      OverviewSeverity.medium => 1,
    };
  }

  List<OverviewTrendPoint> _toTrendPoints(List<int> values) {
    return List<OverviewTrendPoint>.generate(values.length, (int index) {
      return OverviewTrendPoint(
        label: 'Day ${index + 1}',
        value: values[index],
      );
    });
  }
}

class _OverviewProjectPartition {
  const _OverviewProjectPartition({
    required this.remoteProjects,
    required this.seededProjects,
  });

  final List<OverviewProjectReference> remoteProjects;
  final List<OverviewProjectReference> seededProjects;
}

_OverviewProjectPartition _partitionProjects(
  List<OverviewProjectReference> projects,
) {
  final List<OverviewProjectReference> remoteProjects =
      <OverviewProjectReference>[];
  final List<OverviewProjectReference> seededProjects =
      <OverviewProjectReference>[];
  for (final OverviewProjectReference project in projects) {
    if (isRemoteCapableConfig(project.firebaseConfig)) {
      remoteProjects.add(project);
    } else {
      seededProjects.add(project);
    }
  }
  return _OverviewProjectPartition(
    remoteProjects: remoteProjects,
    seededProjects: seededProjects,
  );
}

OverviewSnapshot _mergeSnapshots({
  required OverviewQuery query,
  required List<OverviewProjectReference> activeProjects,
  required List<OverviewSnapshot> partialSnapshots,
}) {
  if (partialSnapshots.length == 1) {
    return partialSnapshots.single;
  }

  final int criticalIssues = partialSnapshots.fold(
    0,
    (int sum, OverviewSnapshot snapshot) =>
        sum + snapshot.counts.criticalIssues,
  );
  final int openCases = partialSnapshots.fold(
    0,
    (int sum, OverviewSnapshot snapshot) => sum + snapshot.counts.openCases,
  );
  final int freshIncidents = partialSnapshots.fold(
    0,
    (int sum, OverviewSnapshot snapshot) =>
        sum + snapshot.counts.freshIncidents,
  );
  final int healthyProjects = partialSnapshots.fold(
    0,
    (int sum, OverviewSnapshot snapshot) =>
        sum + snapshot.counts.healthyProjects,
  );
  final List<OverviewQueueItem> urgentItems =
      partialSnapshots
          .expand((OverviewSnapshot snapshot) => snapshot.urgentItems)
          .toList()
        ..sort((OverviewQueueItem left, OverviewQueueItem right) {
          final int severityCompare = _overviewSeverityRank(
            right.severity,
          ).compareTo(_overviewSeverityRank(left.severity));
          if (severityCompare != 0) {
            return severityCompare;
          }
          return right.incidentCount.compareTo(left.incidentCount);
        });
  final List<OverviewPostureCard> postureCards = partialSnapshots
      .expand((OverviewSnapshot snapshot) => snapshot.postureCards)
      .take(4)
      .toList();
  final List<int> issueTrendValues = List<int>.filled(7, 0);
  final List<int> severityTrendValues = List<int>.filled(7, 0);
  for (final OverviewSnapshot snapshot in partialSnapshots) {
    for (int index = 0; index < 7; index++) {
      issueTrendValues[index] += snapshot.issueVolumeTrend.points[index].value;
      severityTrendValues[index] += snapshot.severityTrend.points[index].value;
    }
  }

  final OverviewSeverityMix severityMix = OverviewSeverityMix(
    critical: partialSnapshots.fold(
      0,
      (int sum, OverviewSnapshot snapshot) =>
          sum + snapshot.severityMix.critical,
    ),
    high: partialSnapshots.fold(
      0,
      (int sum, OverviewSnapshot snapshot) => sum + snapshot.severityMix.high,
    ),
    medium: partialSnapshots.fold(
      0,
      (int sum, OverviewSnapshot snapshot) => sum + snapshot.severityMix.medium,
    ),
  );

  return OverviewSnapshot(
    query: query,
    activeProjects: activeProjects,
    counts: OverviewCounts(
      criticalIssues: criticalIssues,
      openCases: openCases,
      freshIncidents: freshIncidents,
      healthyProjects: healthyProjects,
    ),
    urgentItems: urgentItems.take(5).toList(),
    postureCards: postureCards,
    issueVolumeTrend: OverviewTrendSeries(
      title: 'Issue volume',
      subtitle: 'Escalation-worthy fingerprints by day.',
      targetPath: '/issues',
      points: _toOverviewTrendPoints(issueTrendValues),
    ),
    severityTrend: OverviewTrendSeries(
      title: 'Severity pressure',
      subtitle: 'Critical and high-severity case pressure over time.',
      targetPath: '/reports',
      points: _toOverviewTrendPoints(severityTrendValues),
    ),
    severityMix: severityMix,
    overloaded: urgentItems.length >= 4 || criticalIssues >= 10,
  );
}

DateTime _sinceForOverviewRange(OverviewDateRange range) {
  return switch (range) {
    OverviewDateRange.last24Hours => DateTime.now().subtract(
      const Duration(hours: 24),
    ),
    OverviewDateRange.last7Days => DateTime.now().subtract(
      const Duration(days: 7),
    ),
    OverviewDateRange.last30Days => DateTime.now().subtract(
      const Duration(days: 30),
    ),
  };
}

OverviewSeverity _mapOverviewSeverity(String rawSeverity) {
  return switch (rawSeverity) {
    'critical' || 'serious' => OverviewSeverity.critical,
    'moderate' => OverviewSeverity.high,
    _ => OverviewSeverity.medium,
  };
}

bool _allowsOverviewSeverity(
  OverviewSeverityFilter filter,
  OverviewSeverity severity,
) {
  return switch (filter) {
    OverviewSeverityFilter.criticalOnly =>
      severity == OverviewSeverity.critical,
    OverviewSeverityFilter.criticalAndHigh =>
      severity != OverviewSeverity.medium,
  };
}

int _overviewSeverityRank(OverviewSeverity severity) {
  return switch (severity) {
    OverviewSeverity.critical => 3,
    OverviewSeverity.high => 2,
    OverviewSeverity.medium => 1,
  };
}

List<OverviewTrendPoint> _toOverviewTrendPoints(List<int> values) {
  return List<OverviewTrendPoint>.generate(values.length, (int index) {
    return OverviewTrendPoint(label: 'Day ${index + 1}', value: values[index]);
  });
}

void _accumulateBucket(List<int> buckets, DateTime timestamp, DateTime since) {
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

String _overviewIssueTitle(
  ArmIssueDocument issue,
  ArmCaseDocument? latestCase,
) {
  final String feature = issue.feature.trim();
  final String operation = issue.operation.trim();
  if (feature.isNotEmpty && operation.isNotEmpty) {
    return '${_overviewHeadline(feature)} ${_overviewHeadline(operation)} incident';
  }
  if (latestCase != null && latestCase.message.trim().isNotEmpty) {
    return latestCase.message.trim();
  }
  if (feature.isNotEmpty) {
    return '${_overviewHeadline(feature)} incident';
  }
  return issue.issueId;
}

String _overviewHeadline(String value) {
  return value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((String part) => part.isNotEmpty)
      .map((String part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

enum _OverviewCaseStatus { active, stale }

_OverviewCaseStatus _deriveOverviewCaseStatus(ArmCaseDocument caseDocument) {
  final int ageHours = DateTime.now()
      .difference(caseDocument.createdAt)
      .inHours;
  if (caseDocument.handled && ageHours > 24) {
    return _OverviewCaseStatus.stale;
  }
  return _OverviewCaseStatus.active;
}

OverviewPostureCard _buildPostureCard({
  required ArmProjectTelemetry projectTelemetry,
  required int criticalIssueCount,
  required int openCaseCount,
}) {
  if (criticalIssueCount > 0) {
    return OverviewPostureCard(
      title: '${projectTelemetry.project.name} is carrying critical pressure',
      description:
          '$criticalIssueCount critical issue${criticalIssueCount == 1 ? '' : 's'} and $openCaseCount active case${openCaseCount == 1 ? '' : 's'} are still in the current window.',
      targetPath:
          '/issues?project=${projectTelemetry.project.id}&severity=critical',
      tone: OverviewPostureTone.critical,
    );
  }
  if (openCaseCount > 0) {
    return OverviewPostureCard(
      title: '${projectTelemetry.project.name} still has active case churn',
      description:
          '$openCaseCount case${openCaseCount == 1 ? '' : 's'} remain in review even without a critical fingerprint cluster.',
      targetPath: '/cases?project=${projectTelemetry.project.id}',
      tone: OverviewPostureTone.attention,
    );
  }
  return OverviewPostureCard(
    title: '${projectTelemetry.project.name} is currently calm',
    description:
        'No critical fingerprints or active case churn landed in the selected window.',
    targetPath: '/reports?project=${projectTelemetry.project.id}',
    tone: OverviewPostureTone.positive,
  );
}

class _ProjectSeed {
  const _ProjectSeed({
    required this.criticalIssues,
    required this.openCases,
    required this.freshIncidents,
    required this.severityMix,
    required this.primarySeverity,
    required this.queueItems,
    required this.postureCards,
    required this.issueTrend,
    required this.severityTrend,
  });

  final int criticalIssues;
  final int openCases;
  final int freshIncidents;
  final OverviewSeverityMix severityMix;
  final OverviewSeverity primarySeverity;
  final List<_QueueSeed> queueItems;
  final List<_PostureSeed> postureCards;
  final List<int> issueTrend;
  final List<int> severityTrend;
}

class _QueueSeed {
  const _QueueSeed({
    required this.title,
    required this.subtitle,
    required this.severity,
    required this.routePath,
    required this.incidentCount,
  });

  final String title;
  final String subtitle;
  final OverviewSeverity severity;
  final String routePath;
  final int incidentCount;
}

class _PostureSeed {
  const _PostureSeed({
    required this.title,
    required this.description,
    required this.targetPath,
    required this.tone,
  });

  final String title;
  final String description;
  final String targetPath;
  final OverviewPostureTone tone;
}

const Map<String, _ProjectSeed> _projectSeeds = <String, _ProjectSeed>{
  'core-platform': _ProjectSeed(
    criticalIssues: 4,
    openCases: 11,
    freshIncidents: 3,
    severityMix: OverviewSeverityMix(critical: 4, high: 5, medium: 2),
    primarySeverity: OverviewSeverity.critical,
    queueItems: <_QueueSeed>[
      _QueueSeed(
        title: 'Repeated save failures in Core platform',
        subtitle: 'Integrity-risking cases are still open',
        severity: OverviewSeverity.critical,
        routePath:
            '/issues?q=saveDraft%2Fnetwork-timeout&issueId=issue-save-draft-timeout',
        incidentCount: 11,
      ),
      _QueueSeed(
        title: 'Snapshot recovery gap in Checkout',
        subtitle: 'Recovery payloads missing in recent cases',
        severity: OverviewSeverity.high,
        routePath: '/cases?issueId=issue-checkout-missing-snapshot',
        incidentCount: 4,
      ),
    ],
    postureCards: <_PostureSeed>[
      _PostureSeed(
        title: 'Fresh incident spike',
        description: 'Case volume doubled after the latest release window.',
        targetPath: '/reports',
        tone: OverviewPostureTone.attention,
      ),
      _PostureSeed(
        title: 'Data integrity watch',
        description:
            'Recovery hints exist, but unresolved cases are still stacked.',
        targetPath: '/cases?issueId=issue-checkout-missing-snapshot',
        tone: OverviewPostureTone.critical,
      ),
    ],
    issueTrend: <int>[2, 3, 5, 4, 6, 7, 5],
    severityTrend: <int>[1, 2, 3, 3, 4, 5, 4],
  ),
  'customer-ops': _ProjectSeed(
    criticalIssues: 2,
    openCases: 8,
    freshIncidents: 2,
    severityMix: OverviewSeverityMix(critical: 2, high: 4, medium: 3),
    primarySeverity: OverviewSeverity.high,
    queueItems: <_QueueSeed>[
      _QueueSeed(
        title: 'Session expiry loop in Customer Operations',
        subtitle: 'Users are bouncing back to sign-in repeatedly',
        severity: OverviewSeverity.high,
        routePath:
            '/issues?q=auth%2Fsession-expired&issueId=issue-auth-session-expired',
        incidentCount: 8,
      ),
    ],
    postureCards: <_PostureSeed>[
      _PostureSeed(
        title: 'Stale unresolved cases',
        description:
            'High-priority incidents have not been revisited this morning.',
        targetPath: '/cases?issueId=issue-auth-session-expired',
        tone: OverviewPostureTone.attention,
      ),
    ],
    issueTrend: <int>[1, 2, 2, 3, 3, 4, 3],
    severityTrend: <int>[1, 1, 2, 2, 2, 3, 2],
  ),
  'innovation-lab': _ProjectSeed(
    criticalIssues: 0,
    openCases: 1,
    freshIncidents: 0,
    severityMix: OverviewSeverityMix(critical: 0, high: 0, medium: 1),
    primarySeverity: OverviewSeverity.medium,
    queueItems: <_QueueSeed>[],
    postureCards: <_PostureSeed>[
      _PostureSeed(
        title: 'Calm sandbox workspace',
        description:
            'No high-severity alerts are active in the current window.',
        targetPath: '/reports',
        tone: OverviewPostureTone.positive,
      ),
    ],
    issueTrend: <int>[0, 0, 1, 0, 1, 0, 0],
    severityTrend: <int>[0, 0, 0, 0, 1, 0, 0],
  ),
};

_ProjectSeed _emptySeed(String id) {
  return const _ProjectSeed(
    criticalIssues: 0,
    openCases: 0,
    freshIncidents: 0,
    severityMix: OverviewSeverityMix(critical: 0, high: 0, medium: 0),
    primarySeverity: OverviewSeverity.medium,
    queueItems: <_QueueSeed>[],
    postureCards: <_PostureSeed>[],
    issueTrend: <int>[0, 0, 0, 0, 0, 0, 0],
    severityTrend: <int>[0, 0, 0, 0, 0, 0, 0],
  );
}
