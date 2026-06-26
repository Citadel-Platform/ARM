import 'dart:convert';
import 'dart:math' as math;

import 'package:arm_console/src/features/arm_data/data/arm_telemetry_gateway.dart';
import 'package:arm_console/src/features/cases/case_detail_models.dart';
import 'package:arm_console/src/features/explorer/domain/explorer_models.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';

abstract interface class ExplorerRepository {
  Future<IssuesResult> loadIssues({
    required IssuesQuery query,
    required List<ConsoleProject> visibleProjects,
  });

  Future<CasesResult> loadCases({
    required CasesQuery query,
    required List<ConsoleProject> visibleProjects,
  });

  Future<CaseDetailRecord?> loadCaseDetail({
    required String caseId,
    required List<ConsoleProject> visibleProjects,
  });
}

class InMemoryExplorerRepository implements ExplorerRepository {
  const InMemoryExplorerRepository();

  @override
  Future<IssuesResult> loadIssues({
    required IssuesQuery query,
    required List<ConsoleProject> visibleProjects,
  }) async {
    final Set<String> visibleProjectIds = visibleProjects
        .map((ConsoleProject project) => project.id)
        .toSet();
    return _buildIssuesResult(
      records: _issues
          .where(
            (IssueRecord issue) => visibleProjectIds.contains(issue.projectId),
          )
          .toList(),
      query: query,
    );
  }

  @override
  Future<CasesResult> loadCases({
    required CasesQuery query,
    required List<ConsoleProject> visibleProjects,
  }) async {
    final Set<String> visibleProjectIds = visibleProjects
        .map((ConsoleProject project) => project.id)
        .toSet();
    final List<IssueRecord> scopedIssues = _issues
        .where(
          (IssueRecord issue) => visibleProjectIds.contains(issue.projectId),
        )
        .toList();
    return _buildCasesResult(
      records: _cases
          .where(
            (CaseRecord record) => visibleProjectIds.contains(record.projectId),
          )
          .toList(),
      issues: scopedIssues,
      query: query,
    );
  }

  @override
  Future<CaseDetailRecord?> loadCaseDetail({
    required String caseId,
    required List<ConsoleProject> visibleProjects,
  }) async {
    final Set<String> visibleProjectIds = visibleProjects
        .map((ConsoleProject project) => project.id)
        .toSet();
    return _loadSeededCaseDetail(
      caseId: caseId,
      visibleProjectIds: visibleProjectIds,
    );
  }
}

class AdaptiveExplorerRepository implements ExplorerRepository {
  const AdaptiveExplorerRepository({ArmTelemetryGateway? gateway})
    : this._(gateway);

  const AdaptiveExplorerRepository._(this._gateway);

  final ArmTelemetryGateway? _gateway;

  static final ArmTelemetryGateway _defaultGateway =
      FirebaseArmTelemetryGateway();

  ArmTelemetryGateway get _telemetryGateway => _gateway ?? _defaultGateway;

  @override
  Future<IssuesResult> loadIssues({
    required IssuesQuery query,
    required List<ConsoleProject> visibleProjects,
  }) async {
    final _ProjectPartition partition = _partitionProjects(visibleProjects);
    final List<IssueRecord> combinedIssues = <IssueRecord>[
      ..._issues.where(
        (IssueRecord issue) =>
            partition.seededProjectIds.contains(issue.projectId),
      ),
    ];

    if (partition.remoteProjects.isNotEmpty) {
      final List<ArmProjectTelemetry> telemetry = await _telemetryGateway
          .loadProjectTelemetry(
            projects: partition.remoteProjects,
            issueSince: _sinceForExplorerRange(query.range),
            caseSince: _sinceForExplorerRange(query.range),
          );
      for (final ArmProjectTelemetry projectTelemetry in telemetry) {
        combinedIssues.addAll(_mapRemoteIssues(projectTelemetry));
      }
    }

    return _buildIssuesResult(records: combinedIssues, query: query);
  }

  @override
  Future<CasesResult> loadCases({
    required CasesQuery query,
    required List<ConsoleProject> visibleProjects,
  }) async {
    final _ProjectPartition partition = _partitionProjects(visibleProjects);
    final List<IssueRecord> combinedIssues = <IssueRecord>[
      ..._issues.where(
        (IssueRecord issue) =>
            partition.seededProjectIds.contains(issue.projectId),
      ),
    ];
    final List<CaseRecord> combinedCases = <CaseRecord>[
      ..._cases.where(
        (CaseRecord record) =>
            partition.seededProjectIds.contains(record.projectId),
      ),
    ];

    if (partition.remoteProjects.isNotEmpty) {
      final List<ArmProjectTelemetry> telemetry = await _telemetryGateway
          .loadProjectTelemetry(
            projects: partition.remoteProjects,
            issueSince: _sinceForExplorerRange(query.range),
            caseSince: _sinceForExplorerRange(query.range),
          );
      for (final ArmProjectTelemetry projectTelemetry in telemetry) {
        combinedIssues.addAll(_mapRemoteIssues(projectTelemetry));
        combinedCases.addAll(_mapRemoteCases(projectTelemetry));
      }
    }

    return _buildCasesResult(
      records: combinedCases,
      issues: combinedIssues,
      query: query,
    );
  }

  @override
  Future<CaseDetailRecord?> loadCaseDetail({
    required String caseId,
    required List<ConsoleProject> visibleProjects,
  }) async {
    final _ProjectPartition partition = _partitionProjects(visibleProjects);

    if (partition.remoteProjects.isNotEmpty) {
      final ArmCaseDetailBundle? remoteDetail = await _telemetryGateway
          .loadCaseDetail(projects: partition.remoteProjects, caseId: caseId);
      if (remoteDetail != null) {
        return _mapRemoteCaseDetail(remoteDetail);
      }
    }

    if (partition.seededProjectIds.isEmpty) {
      return null;
    }
    return _loadSeededCaseDetail(
      caseId: caseId,
      visibleProjectIds: partition.seededProjectIds,
    );
  }
}

IssuesResult _buildIssuesResult({
  required List<IssueRecord> records,
  required IssuesQuery query,
}) {
  final List<IssueRecord> filtered = records
      .where(
        (IssueRecord issue) =>
            query.projectId == null || issue.projectId == query.projectId,
      )
      .where(
        (IssueRecord issue) =>
            issue.lastSeenMinutesAgo <= query.range.maxAgeMinutes,
      )
      .where((IssueRecord issue) => query.severityFilter.allows(issue.severity))
      .where((IssueRecord issue) => query.status.allows(issue.status))
      .where((IssueRecord issue) => _matchesIssueSearch(issue, query.search))
      .toList();

  filtered.sort((IssueRecord left, IssueRecord right) {
    return switch (query.sort) {
      IssueSort.latestActivity => left.lastSeenMinutesAgo.compareTo(
        right.lastSeenMinutesAgo,
      ),
      IssueSort.severity =>
        right.severity.rank.compareTo(left.severity.rank) != 0
            ? right.severity.rank.compareTo(left.severity.rank)
            : left.lastSeenMinutesAgo.compareTo(right.lastSeenMinutesAgo),
      IssueSort.firstSeen => right.firstSeenMinutesAgo.compareTo(
        left.firstSeenMinutesAgo,
      ),
      IssueSort.caseCount => right.totalCases.compareTo(left.totalCases),
    };
  });

  final IssueRecord? selectedIssue = query.selectedIssueId == null
      ? null
      : filtered.cast<IssueRecord?>().firstWhere(
          (IssueRecord? issue) => issue?.issueId == query.selectedIssueId,
          orElse: () => null,
        );

  return IssuesResult(
    records: _slicePage(filtered, query.page, query.pageSize),
    totalCount: filtered.length,
    currentPage: _clampPage(filtered.length, query.page, query.pageSize),
    totalPages: _pageCount(filtered.length, query.pageSize),
    selectedIssue: selectedIssue,
  );
}

CasesResult _buildCasesResult({
  required List<CaseRecord> records,
  required List<IssueRecord> issues,
  required CasesQuery query,
}) {
  final List<CaseRecord> filtered = records
      .where(
        (CaseRecord record) =>
            query.projectId == null || record.projectId == query.projectId,
      )
      .where(
        (CaseRecord record) =>
            record.reportedMinutesAgo <= query.range.maxAgeMinutes,
      )
      .where(
        (CaseRecord record) => query.severityFilter.allows(record.severity),
      )
      .where(
        (CaseRecord record) =>
            query.issueId == null || record.issueId == query.issueId,
      )
      .where((CaseRecord record) => _matchesCaseSearch(record, query.search))
      .toList();

  filtered.sort((CaseRecord left, CaseRecord right) {
    return switch (query.sort) {
      CaseSort.reportedAt => left.reportedMinutesAgo.compareTo(
        right.reportedMinutesAgo,
      ),
      CaseSort.severity =>
        right.severity.rank.compareTo(left.severity.rank) != 0
            ? right.severity.rank.compareTo(left.severity.rank)
            : left.reportedMinutesAgo.compareTo(right.reportedMinutesAgo),
      CaseSort.caseId => right.caseId.compareTo(left.caseId),
    };
  });

  final CaseRecord? selectedCase = query.selectedCase == null
      ? null
      : filtered.cast<CaseRecord?>().firstWhere(
          (CaseRecord? record) => record?.caseId == query.selectedCase,
          orElse: () => null,
        );

  final IssueRecord? issueFilterIssue = query.issueId == null
      ? null
      : issues.cast<IssueRecord?>().firstWhere(
          (IssueRecord? issue) => issue?.issueId == query.issueId,
          orElse: () => null,
        );

  return CasesResult(
    records: _slicePage(filtered, query.page, query.pageSize),
    totalCount: filtered.length,
    currentPage: _clampPage(filtered.length, query.page, query.pageSize),
    totalPages: _pageCount(filtered.length, query.pageSize),
    selectedCase: selectedCase,
    issueFilterIssue: issueFilterIssue,
  );
}

CaseDetailRecord? _loadSeededCaseDetail({
  required String caseId,
  required Set<String> visibleProjectIds,
}) {
  final CaseRecord? caseRecord = _cases.cast<CaseRecord?>().firstWhere(
    (CaseRecord? record) =>
        record != null &&
        visibleProjectIds.contains(record.projectId) &&
        record.caseId == caseId,
    orElse: () => null,
  );
  if (caseRecord == null) {
    return null;
  }

  final IssueRecord issueRecord = _issues.firstWhere(
    (IssueRecord issue) => issue.issueId == caseRecord.issueId,
  );
  final _CaseDetailSeed? seed = _caseDetails[caseId];
  if (seed == null) {
    return _fallbackCaseDetail(caseRecord, issueRecord);
  }

  return CaseDetailRecord(
    caseRecord: caseRecord,
    issueRecord: issueRecord,
    environmentLabel: seed.environmentLabel,
    detectedLabel: seed.detectedLabel,
    lastUpdatedLabel: seed.lastUpdatedLabel,
    customerImpact: seed.customerImpact,
    narrative: seed.narrative,
    traceSummary: seed.traceSummary,
    traceBody: seed.traceBody,
    consoleLogs: seed.consoleLogs,
    contextFields: seed.contextFields,
    snapshotTitle: seed.snapshotTitle,
    snapshotJson: seed.snapshotJson,
    recoveryHints: seed.recoveryHints,
    evidenceAssets: seed.evidenceAssets,
    missingEvidenceNotes: seed.missingEvidenceNotes,
  );
}

List<IssueRecord> _mapRemoteIssues(ArmProjectTelemetry telemetry) {
  final Map<String, List<ArmCaseDocument>> casesByIssue =
      <String, List<ArmCaseDocument>>{};
  for (final ArmCaseDocument caseDocument in telemetry.cases) {
    casesByIssue
        .putIfAbsent(caseDocument.issueId, () => <ArmCaseDocument>[])
        .add(caseDocument);
  }

  return telemetry.issues.map((ArmIssueDocument issue) {
    final List<ArmCaseDocument> issueCases =
        casesByIssue[issue.issueId] ?? const <ArmCaseDocument>[];
    final ArmCaseDocument? latestCase = _latestCase(issueCases);
    final ExplorerSeverity severity = _mapSeverity(issue.severity);
    final int lastSeenMinutesAgo = _minutesSince(issue.lastSeenAt);
    return IssueRecord(
      issueId: issue.issueId,
      fingerprint: _issueFingerprint(issue, latestCase),
      title: _issueTitle(issue, latestCase),
      projectId: telemetry.project.id,
      projectLabel: telemetry.project.shellLabel,
      severity: severity,
      status: _deriveIssueLifecycle(
        issue: issue,
        latestCase: latestCase,
        lastSeenMinutesAgo: lastSeenMinutesAgo,
      ),
      firstSeenMinutesAgo: _minutesSince(issue.firstSeenAt),
      lastSeenMinutesAgo: lastSeenMinutesAgo,
      totalCases: issue.caseCount,
      urgencyLabel: _urgencyLabel(severity),
    );
  }).toList();
}

List<CaseRecord> _mapRemoteCases(ArmProjectTelemetry telemetry) {
  final Map<String, ArmIssueDocument> issuesById = <String, ArmIssueDocument>{
    for (final ArmIssueDocument issue in telemetry.issues) issue.issueId: issue,
  };

  return telemetry.cases.map((ArmCaseDocument caseDocument) {
    final ArmIssueDocument? issue = issuesById[caseDocument.issueId];
    return CaseRecord(
      caseId: caseDocument.caseId,
      issueId: caseDocument.issueId,
      issueFingerprint: _issueFingerprint(issue, caseDocument),
      issueTitle: _issueTitle(issue, caseDocument),
      projectId: telemetry.project.id,
      projectLabel: telemetry.project.shellLabel,
      severity: _mapSeverity(caseDocument.severity),
      reportedMinutesAgo: _minutesSince(caseDocument.createdAt),
      status: _deriveCaseStatus(caseDocument),
      followUpId: _followUpId(caseDocument),
      evidenceCount: _evidenceCount(caseDocument),
    );
  }).toList();
}

CaseDetailRecord _mapRemoteCaseDetail(ArmCaseDetailBundle detail) {
  final IssueRecord issueRecord = _mapRemoteIssues(
    ArmProjectTelemetry(
      project: detail.project,
      issues: <ArmIssueDocument>[detail.issue],
      cases: <ArmCaseDocument>[detail.caseDocument],
    ),
  ).single;
  final CaseRecord caseRecord = _mapRemoteCases(
    ArmProjectTelemetry(
      project: detail.project,
      issues: <ArmIssueDocument>[detail.issue],
      cases: <ArmCaseDocument>[detail.caseDocument],
    ),
  ).single;
  final Map<String, Object?> snapshotData =
      detail.caseDocument.recoverySnapshot ?? detail.caseDocument.context;

  return CaseDetailRecord(
    caseRecord: caseRecord,
    issueRecord: issueRecord,
    environmentLabel: _environmentLabel(detail.project, detail.caseDocument),
    detectedLabel: caseRecord.reportedLabel,
    lastUpdatedLabel: issueRecord.lastSeenLabel,
    customerImpact: _customerImpact(caseRecord),
    narrative: _buildNarrative(detail.caseDocument),
    traceSummary: _traceSummary(detail.caseDocument),
    traceBody: detail.caseDocument.stackTrace.isEmpty
        ? detail.caseDocument.message
        : detail.caseDocument.stackTrace,
    consoleLogs: _buildConsoleLogs(detail.caseDocument),
    contextFields: _buildContextFields(detail.caseDocument),
    snapshotTitle: detail.caseDocument.recoverySnapshot == null
        ? 'Captured request context'
        : 'Recovery snapshot',
    snapshotJson: const JsonEncoder.withIndent('  ').convert(snapshotData),
    recoveryHints: _buildRecoveryHints(detail.caseDocument),
    evidenceAssets: _buildEvidenceAssets(detail.caseDocument),
    missingEvidenceNotes: _buildMissingEvidenceNotes(detail.caseDocument),
  );
}

class _ProjectPartition {
  const _ProjectPartition({
    required this.remoteProjects,
    required this.seededProjectIds,
  });

  final List<ArmMonitoredProject> remoteProjects;
  final Set<String> seededProjectIds;
}

_ProjectPartition _partitionProjects(List<ConsoleProject> visibleProjects) {
  final List<ArmMonitoredProject> remoteProjects = <ArmMonitoredProject>[];
  final Set<String> seededProjectIds = <String>{};
  for (final ConsoleProject project in visibleProjects) {
    if (isRemoteCapableConfig(project.firebaseConfig)) {
      remoteProjects.add(
        ArmMonitoredProject(
          id: project.id,
          name: project.name,
          environmentLabel: project.environmentLabel,
          firebaseConfig: project.firebaseConfig,
        ),
      );
    } else {
      seededProjectIds.add(project.id);
    }
  }
  return _ProjectPartition(
    remoteProjects: remoteProjects,
    seededProjectIds: seededProjectIds,
  );
}

DateTime _sinceForExplorerRange(ExplorerDateRange range) {
  return DateTime.now().subtract(Duration(minutes: range.maxAgeMinutes));
}

ArmCaseDocument? _latestCase(List<ArmCaseDocument> cases) {
  if (cases.isEmpty) {
    return null;
  }
  return cases.reduce(
    (ArmCaseDocument left, ArmCaseDocument right) =>
        left.createdAt.isAfter(right.createdAt) ? left : right,
  );
}

ExplorerSeverity _mapSeverity(String rawSeverity) {
  return switch (rawSeverity) {
    'critical' || 'serious' => ExplorerSeverity.critical,
    'moderate' => ExplorerSeverity.high,
    _ => ExplorerSeverity.medium,
  };
}

IssueLifecycle _deriveIssueLifecycle({
  required ArmIssueDocument issue,
  required ArmCaseDocument? latestCase,
  required int lastSeenMinutesAgo,
}) {
  if (latestCase == null) {
    return IssueLifecycle.open;
  }
  if (latestCase.handled && lastSeenMinutesAgo > 24 * 60) {
    return IssueLifecycle.monitoring;
  }
  if (!latestCase.handled &&
      (lastSeenMinutesAgo <= 60 || issue.caseCount >= 5)) {
    return IssueLifecycle.open;
  }
  return IssueLifecycle.investigating;
}

CaseTriageStatus _deriveCaseStatus(ArmCaseDocument caseDocument) {
  final int ageMinutes = _minutesSince(caseDocument.createdAt);
  if (!caseDocument.handled && ageMinutes <= 30) {
    return CaseTriageStatus.newCase;
  }
  if (!caseDocument.handled) {
    return CaseTriageStatus.triaging;
  }
  if (ageMinutes <= 24 * 60) {
    return CaseTriageStatus.awaitingFollowUp;
  }
  return CaseTriageStatus.stale;
}

int _minutesSince(DateTime timestamp) {
  return DateTime.now().difference(timestamp).inMinutes.clamp(0, 365 * 24 * 60);
}

String _urgencyLabel(ExplorerSeverity severity) {
  return switch (severity) {
    ExplorerSeverity.critical => 'Immediate',
    ExplorerSeverity.high => 'Elevated',
    ExplorerSeverity.medium => 'Watching',
  };
}

String _issueFingerprint(
  ArmIssueDocument? issue,
  ArmCaseDocument? caseDocument,
) {
  final String fingerprint = caseDocument?.fingerprint.trim() ?? '';
  if (fingerprint.isNotEmpty) {
    return fingerprint;
  }
  final String feature =
      issue?.feature.trim() ?? caseDocument?.feature.trim() ?? '';
  final String operation =
      issue?.operation.trim() ?? caseDocument?.operation.trim() ?? '';
  if (feature.isNotEmpty && operation.isNotEmpty) {
    return '$feature/$operation';
  }
  if (feature.isNotEmpty) {
    return feature;
  }
  if (operation.isNotEmpty) {
    return operation;
  }
  return issue?.issueId ?? caseDocument?.issueId ?? 'unknown-issue';
}

String _issueTitle(ArmIssueDocument? issue, ArmCaseDocument? caseDocument) {
  final String feature =
      issue?.feature.trim() ?? caseDocument?.feature.trim() ?? '';
  final String operation =
      issue?.operation.trim() ?? caseDocument?.operation.trim() ?? '';
  if (feature.isNotEmpty && operation.isNotEmpty) {
    return '${_headline(feature)} ${_headline(operation)} incident';
  }
  if (feature.isNotEmpty) {
    return '${_headline(feature)} incident';
  }
  final String message = caseDocument?.message.trim() ?? '';
  if (message.isNotEmpty) {
    return message;
  }
  return _issueFingerprint(issue, caseDocument);
}

String _headline(String value) {
  final String normalized = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (normalized.isEmpty) {
    return value;
  }
  return normalized
      .split(RegExp(r'\s+'))
      .map((String part) {
        if (part.isEmpty) {
          return part;
        }
        return '${part[0].toUpperCase()}${part.substring(1)}';
      })
      .join(' ');
}

String _followUpId(ArmCaseDocument caseDocument) {
  final String sessionId = caseDocument.sessionId.trim();
  return sessionId.isEmpty ? caseDocument.caseId : sessionId;
}

int _evidenceCount(ArmCaseDocument caseDocument) {
  int count = 0;
  if ((caseDocument.screenshot?['path'] as String? ?? '').isNotEmpty) {
    count += 1;
  }
  if (caseDocument.recoverySnapshot != null &&
      caseDocument.recoverySnapshot!.isNotEmpty) {
    count += 1;
  }
  if (caseDocument.breadcrumbs.isNotEmpty) {
    count += 1;
  }
  if (caseDocument.stackTrace.trim().isNotEmpty) {
    count += 1;
  }
  if (caseDocument.context.isNotEmpty || caseDocument.tags.isNotEmpty) {
    count += 1;
  }
  return count;
}

String _environmentLabel(
  ArmMonitoredProject project,
  ArmCaseDocument caseDocument,
) {
  final String raw = (caseDocument.context['environment'] as String? ?? '')
      .trim();
  if (raw.isEmpty) {
    return project.environmentLabel;
  }
  return _headline(raw);
}

String _customerImpact(CaseRecord caseRecord) {
  return switch (caseRecord.severity) {
    ExplorerSeverity.critical =>
      'This incident should be treated as customer-visible operational risk until the failing path is reproduced and contained.',
    ExplorerSeverity.high =>
      'This incident is degrading a meaningful workflow and should stay in active triage until the recovery path is confirmed.',
    ExplorerSeverity.medium =>
      'This incident is currently lower urgency, but the captured evidence should still be reviewed before it turns into repeat churn.',
  };
}

List<CaseNarrativeStep> _buildNarrative(ArmCaseDocument caseDocument) {
  return <CaseNarrativeStep>[
    CaseNarrativeStep(
      label: 'Detection',
      title: _traceSummary(caseDocument),
      description:
          'ARM captured the incident in ${caseDocument.feature.isEmpty ? 'the monitored flow' : _headline(caseDocument.feature)} at ${caseDocument.createdAt.toLocal()}.',
    ),
    CaseNarrativeStep(
      label: 'Context',
      title: caseDocument.operation.isEmpty
          ? 'Operation context captured'
          : '${_headline(caseDocument.operation)} context captured',
      description:
          'Session, route, and breadcrumb context were stored with the case so the operator can replay the failure path quickly.',
    ),
    CaseNarrativeStep(
      label: 'Recovery',
      title: caseDocument.handled
          ? 'The monitored app handled the failure'
          : 'The monitored app did not recover automatically',
      description: caseDocument.recoverySnapshot == null
          ? 'No recovery snapshot was attached to this case.'
          : 'A recovery snapshot was attached and can be inspected from the snapshot panel.',
    ),
  ];
}

String _traceSummary(ArmCaseDocument caseDocument) {
  final String errorType = caseDocument.errorType.trim();
  if (errorType.isNotEmpty) {
    return errorType;
  }
  final String message = caseDocument.message.trim();
  if (message.isNotEmpty) {
    return message;
  }
  return 'ARM incident trace';
}

List<CaseLogEntry> _buildConsoleLogs(ArmCaseDocument caseDocument) {
  if (caseDocument.breadcrumbs.isEmpty) {
    return <CaseLogEntry>[
      CaseLogEntry(
        timeLabel: caseDocument.createdAt.toLocal().toString(),
        level: CaseLogLevel.info,
        message: 'ARM recorded the case without breadcrumb telemetry.',
      ),
    ];
  }

  return caseDocument.breadcrumbs.map((Map<String, Object?> breadcrumb) {
    final String level = (breadcrumb['level'] as String? ?? '').toLowerCase();
    return CaseLogEntry(
      timeLabel: (breadcrumb['timestamp'] as String? ?? '').replaceFirst(
        'T',
        ' ',
      ),
      level: switch (level) {
        'warning' => CaseLogLevel.warning,
        'error' => CaseLogLevel.error,
        _ => CaseLogLevel.info,
      },
      message: (breadcrumb['message'] as String? ?? 'Breadcrumb captured')
          .trim(),
    );
  }).toList();
}

List<CaseContextField> _buildContextFields(ArmCaseDocument caseDocument) {
  final Map<String, Object?> combined = <String, Object?>{
    ...caseDocument.context,
    ...caseDocument.tags.map(
      (String key, Object? value) => MapEntry('tag:$key', value),
    ),
  };
  final List<String> keys = combined.keys.toList()..sort();
  return keys.map((String key) {
    final Object? value = combined[key];
    final String rendered = switch (value) {
      null => 'null',
      String text => text,
      num number => '$number',
      bool boolean => '$boolean',
      _ => const JsonEncoder.withIndent('  ').convert(value),
    };
    return CaseContextField(label: key, value: rendered);
  }).toList();
}

List<String> _buildRecoveryHints(ArmCaseDocument caseDocument) {
  return <String>[
    if (caseDocument.handled)
      'The monitored app reported that the failure path was handled. Confirm whether the customer-facing workflow actually recovered.'
    else
      'The monitored app did not mark this failure as handled. Reproduce the path and confirm whether the user can safely continue.',
    if (caseDocument.recoverySnapshot != null)
      'A recovery snapshot is attached. Compare it with the failing request context before attempting data repair.'
    else
      'No recovery snapshot is attached. Use the captured context and breadcrumbs to reconstruct the failing state.',
    if ((caseDocument.screenshot?['path'] as String? ?? '').isNotEmpty)
      'A screenshot asset path was captured. Verify the image still exists in the monitored project bucket if visual evidence is needed.'
    else
      'No screenshot metadata was captured for this case.',
  ];
}

List<CaseEvidenceAsset> _buildEvidenceAssets(ArmCaseDocument caseDocument) {
  final List<CaseEvidenceAsset> assets = <CaseEvidenceAsset>[];
  final String screenshotPath =
      (caseDocument.screenshot?['path'] as String? ?? '').trim();
  if (screenshotPath.isNotEmpty) {
    assets.add(
      CaseEvidenceAsset(
        id: 'screenshot-${caseDocument.caseId}',
        label: 'Captured screenshot',
        caption: screenshotPath,
        type: CaseAssetType.screenshot,
        status: CaseAssetStatus.available,
        capturedLabel: caseDocument.createdAt.toLocal().toString(),
        sourceLabel: 'Cloud Storage metadata',
      ),
    );
  }
  if (caseDocument.recoverySnapshot != null &&
      caseDocument.recoverySnapshot!.isNotEmpty) {
    assets.add(
      CaseEvidenceAsset(
        id: 'snapshot-${caseDocument.caseId}',
        label: 'Recovery snapshot',
        caption: 'Serialized recovery payload captured alongside the incident.',
        type: CaseAssetType.snapshot,
        status: CaseAssetStatus.available,
        capturedLabel: caseDocument.createdAt.toLocal().toString(),
        sourceLabel: 'Firestore recoverySnapshot',
      ),
    );
  }
  if (caseDocument.breadcrumbs.isNotEmpty) {
    assets.add(
      CaseEvidenceAsset(
        id: 'breadcrumbs-${caseDocument.caseId}',
        label: 'Breadcrumb trace',
        caption:
            '${caseDocument.breadcrumbs.length} breadcrumb entries retained.',
        type: CaseAssetType.attachment,
        status: CaseAssetStatus.available,
        capturedLabel: caseDocument.createdAt.toLocal().toString(),
        sourceLabel: 'ARM breadcrumb buffer',
      ),
    );
  }
  return assets;
}

List<String> _buildMissingEvidenceNotes(ArmCaseDocument caseDocument) {
  final List<String> notes = <String>[];
  if ((caseDocument.screenshot?['path'] as String? ?? '').trim().isEmpty) {
    notes.add('No screenshot metadata was captured for this case.');
  }
  if (caseDocument.recoverySnapshot == null ||
      caseDocument.recoverySnapshot!.isEmpty) {
    notes.add('No recovery snapshot was attached to this case.');
  }
  if (caseDocument.breadcrumbs.isEmpty) {
    notes.add('No breadcrumbs were stored for this incident.');
  }
  return notes;
}

List<T> _slicePage<T>(List<T> values, int page, int pageSize) {
  if (values.isEmpty) {
    return <T>[];
  }
  final int currentPage = _clampPage(values.length, page, pageSize);
  final int start = (currentPage - 1) * pageSize;
  final int end = math.min(start + pageSize, values.length);
  return values.sublist(start, end);
}

int _pageCount(int totalCount, int pageSize) {
  if (totalCount == 0) {
    return 1;
  }
  return (totalCount / pageSize).ceil();
}

int _clampPage(int totalCount, int page, int pageSize) {
  final int totalPages = _pageCount(totalCount, pageSize);
  return page.clamp(1, totalPages);
}

bool _matchesIssueSearch(IssueRecord issue, String search) {
  if (search.isEmpty) {
    return true;
  }
  final String normalized = search.toLowerCase();
  return issue.fingerprint.toLowerCase().contains(normalized) ||
      issue.title.toLowerCase().contains(normalized) ||
      issue.projectLabel.toLowerCase().contains(normalized);
}

bool _matchesCaseSearch(CaseRecord record, String search) {
  if (search.isEmpty) {
    return true;
  }
  final String normalized = search.toLowerCase();
  return record.caseId.toLowerCase().contains(normalized) ||
      record.followUpId.toLowerCase().contains(normalized) ||
      record.issueFingerprint.toLowerCase().contains(normalized) ||
      record.issueTitle.toLowerCase().contains(normalized);
}

const List<IssueRecord> _issues = <IssueRecord>[
  IssueRecord(
    issueId: 'issue-save-draft-timeout',
    fingerprint: 'saveDraft/network-timeout',
    title: 'Repeated save failures in Core platform',
    projectId: 'core-platform',
    projectLabel: 'Core platform · Production',
    severity: ExplorerSeverity.critical,
    status: IssueLifecycle.open,
    firstSeenMinutesAgo: 3 * 24 * 60,
    lastSeenMinutesAgo: 4,
    totalCases: 11,
    urgencyLabel: 'Immediate',
  ),
  IssueRecord(
    issueId: 'issue-auth-session-expired',
    fingerprint: 'auth/session-expired',
    title: 'Session expiry loop in Customer Operations',
    projectId: 'customer-ops',
    projectLabel: 'Customer Operations · Production',
    severity: ExplorerSeverity.high,
    status: IssueLifecycle.investigating,
    firstSeenMinutesAgo: 2 * 24 * 60,
    lastSeenMinutesAgo: 14,
    totalCases: 8,
    urgencyLabel: 'Elevated',
  ),
  IssueRecord(
    issueId: 'issue-checkout-missing-snapshot',
    fingerprint: 'checkout/missing-snapshot',
    title: 'Snapshot recovery gap in Checkout',
    projectId: 'core-platform',
    projectLabel: 'Core platform · Production',
    severity: ExplorerSeverity.high,
    status: IssueLifecycle.open,
    firstSeenMinutesAgo: 18 * 60,
    lastSeenMinutesAgo: 39,
    totalCases: 4,
    urgencyLabel: 'Elevated',
  ),
  IssueRecord(
    issueId: 'issue-profile-invalid-country',
    fingerprint: 'profile/invalid-country',
    title: 'Profile form rejects a valid country payload',
    projectId: 'customer-ops',
    projectLabel: 'Customer Operations · Production',
    severity: ExplorerSeverity.medium,
    status: IssueLifecycle.monitoring,
    firstSeenMinutesAgo: 6 * 24 * 60,
    lastSeenMinutesAgo: 5 * 60,
    totalCases: 3,
    urgencyLabel: 'Watching',
  ),
  IssueRecord(
    issueId: 'issue-sandbox-replay-desync',
    fingerprint: 'sandbox/replay-desync',
    title: 'Replay desync in Innovation Lab preview runs',
    projectId: 'innovation-lab',
    projectLabel: 'Innovation Lab · Sandbox',
    severity: ExplorerSeverity.medium,
    status: IssueLifecycle.monitoring,
    firstSeenMinutesAgo: 8 * 24 * 60,
    lastSeenMinutesAgo: 9 * 60,
    totalCases: 2,
    urgencyLabel: 'Watching',
  ),
  IssueRecord(
    issueId: 'issue-billing-export-timeout',
    fingerprint: 'billing/export-timeout',
    title: 'Billing export times out before CSV generation',
    projectId: 'customer-ops',
    projectLabel: 'Customer Operations · Production',
    severity: ExplorerSeverity.high,
    status: IssueLifecycle.investigating,
    firstSeenMinutesAgo: 26 * 60,
    lastSeenMinutesAgo: 2 * 60,
    totalCases: 5,
    urgencyLabel: 'Elevated',
  ),
];

const List<CaseRecord> _cases = <CaseRecord>[
  CaseRecord(
    caseId: 'ARM-2026-00412',
    issueId: 'issue-save-draft-timeout',
    issueFingerprint: 'saveDraft/network-timeout',
    issueTitle: 'Repeated save failures in Core platform',
    projectId: 'core-platform',
    projectLabel: 'Core platform · Production',
    severity: ExplorerSeverity.critical,
    reportedMinutesAgo: 2,
    status: CaseTriageStatus.newCase,
    followUpId: 'SUP-2218',
    evidenceCount: 5,
  ),
  CaseRecord(
    caseId: 'ARM-2026-00411',
    issueId: 'issue-save-draft-timeout',
    issueFingerprint: 'saveDraft/network-timeout',
    issueTitle: 'Repeated save failures in Core platform',
    projectId: 'core-platform',
    projectLabel: 'Core platform · Production',
    severity: ExplorerSeverity.critical,
    reportedMinutesAgo: 7,
    status: CaseTriageStatus.triaging,
    followUpId: 'SUP-2217',
    evidenceCount: 4,
  ),
  CaseRecord(
    caseId: 'ARM-2026-00410',
    issueId: 'issue-auth-session-expired',
    issueFingerprint: 'auth/session-expired',
    issueTitle: 'Session expiry loop in Customer Operations',
    projectId: 'customer-ops',
    projectLabel: 'Customer Operations · Production',
    severity: ExplorerSeverity.high,
    reportedMinutesAgo: 21,
    status: CaseTriageStatus.triaging,
    followUpId: 'SUP-2216',
    evidenceCount: 3,
  ),
  CaseRecord(
    caseId: 'ARM-2026-00409',
    issueId: 'issue-checkout-missing-snapshot',
    issueFingerprint: 'checkout/missing-snapshot',
    issueTitle: 'Snapshot recovery gap in Checkout',
    projectId: 'core-platform',
    projectLabel: 'Core platform · Production',
    severity: ExplorerSeverity.high,
    reportedMinutesAgo: 54,
    status: CaseTriageStatus.awaitingFollowUp,
    followUpId: 'SUP-2215',
    evidenceCount: 7,
  ),
  CaseRecord(
    caseId: 'ARM-2026-00408',
    issueId: 'issue-billing-export-timeout',
    issueFingerprint: 'billing/export-timeout',
    issueTitle: 'Billing export times out before CSV generation',
    projectId: 'customer-ops',
    projectLabel: 'Customer Operations · Production',
    severity: ExplorerSeverity.high,
    reportedMinutesAgo: 79,
    status: CaseTriageStatus.triaging,
    followUpId: 'SUP-2214',
    evidenceCount: 2,
  ),
  CaseRecord(
    caseId: 'ARM-2026-00407',
    issueId: 'issue-auth-session-expired',
    issueFingerprint: 'auth/session-expired',
    issueTitle: 'Session expiry loop in Customer Operations',
    projectId: 'customer-ops',
    projectLabel: 'Customer Operations · Production',
    severity: ExplorerSeverity.high,
    reportedMinutesAgo: 3 * 60,
    status: CaseTriageStatus.awaitingFollowUp,
    followUpId: 'SUP-2213',
    evidenceCount: 4,
  ),
  CaseRecord(
    caseId: 'ARM-2026-00406',
    issueId: 'issue-profile-invalid-country',
    issueFingerprint: 'profile/invalid-country',
    issueTitle: 'Profile form rejects a valid country payload',
    projectId: 'customer-ops',
    projectLabel: 'Customer Operations · Production',
    severity: ExplorerSeverity.medium,
    reportedMinutesAgo: 6 * 60,
    status: CaseTriageStatus.stale,
    followUpId: 'SUP-2212',
    evidenceCount: 2,
  ),
  CaseRecord(
    caseId: 'ARM-2026-00405',
    issueId: 'issue-sandbox-replay-desync',
    issueFingerprint: 'sandbox/replay-desync',
    issueTitle: 'Replay desync in Innovation Lab preview runs',
    projectId: 'innovation-lab',
    projectLabel: 'Innovation Lab · Sandbox',
    severity: ExplorerSeverity.medium,
    reportedMinutesAgo: 13 * 60,
    status: CaseTriageStatus.stale,
    followUpId: 'SUP-2211',
    evidenceCount: 1,
  ),
  CaseRecord(
    caseId: 'ARM-2026-00404',
    issueId: 'issue-billing-export-timeout',
    issueFingerprint: 'billing/export-timeout',
    issueTitle: 'Billing export times out before CSV generation',
    projectId: 'customer-ops',
    projectLabel: 'Customer Operations · Production',
    severity: ExplorerSeverity.high,
    reportedMinutesAgo: 26 * 60,
    status: CaseTriageStatus.awaitingFollowUp,
    followUpId: 'SUP-2210',
    evidenceCount: 3,
  ),
];

class _CaseDetailSeed {
  const _CaseDetailSeed({
    required this.environmentLabel,
    required this.detectedLabel,
    required this.lastUpdatedLabel,
    required this.customerImpact,
    required this.narrative,
    required this.traceSummary,
    required this.traceBody,
    required this.consoleLogs,
    required this.contextFields,
    required this.snapshotTitle,
    required this.snapshotJson,
    required this.recoveryHints,
    required this.evidenceAssets,
    required this.missingEvidenceNotes,
  });

  final String environmentLabel;
  final String detectedLabel;
  final String lastUpdatedLabel;
  final String customerImpact;
  final List<CaseNarrativeStep> narrative;
  final String traceSummary;
  final String traceBody;
  final List<CaseLogEntry> consoleLogs;
  final List<CaseContextField> contextFields;
  final String snapshotTitle;
  final String snapshotJson;
  final List<String> recoveryHints;
  final List<CaseEvidenceAsset> evidenceAssets;
  final List<String> missingEvidenceNotes;
}

const Map<String, _CaseDetailSeed> _caseDetails = <String, _CaseDetailSeed>{
  'ARM-2026-00412': _CaseDetailSeed(
    environmentLabel: 'Production',
    detectedLabel: 'Detected 2 min ago',
    lastUpdatedLabel: 'Last updated 1 min ago',
    customerImpact:
        'Save attempts are timing out before the draft mutation completes, blocking checkout-side recovery for active sessions.',
    narrative: <CaseNarrativeStep>[
      CaseNarrativeStep(
        label: '08:42',
        title: 'First timeout reported',
        description:
            'The client retried three times before surfacing the ARM case and capturing browser plus API evidence.',
      ),
      CaseNarrativeStep(
        label: '08:43',
        title: 'Recovery snapshot captured',
        description:
            'The console recorded the unsaved draft payload and user session metadata to preserve a recovery path.',
      ),
      CaseNarrativeStep(
        label: '08:44',
        title: 'Repeated cluster matched',
        description:
            'The case linked into the existing saveDraft issue after the request signature matched the current critical fingerprint.',
      ),
    ],
    traceSummary: 'DioException timeout while awaiting draft persistence.',
    traceBody:
        'DioException [connection timeout]: The request connection took longer than 5000ms.\n'
        '#0      DraftRepository.saveDraft (package:customer_portal/src/data/draft_repository.dart:91)\n'
        '#1      CheckoutController.persistDraft (package:customer_portal/src/features/checkout/checkout_controller.dart:144)\n'
        '#2      CheckoutController._flushAutosaveQueue (package:customer_portal/src/features/checkout/checkout_controller.dart:209)\n'
        '#3      _RootZone.runUnaryGuarded (dart:async/zone.dart:1778)\n',
    consoleLogs: <CaseLogEntry>[
      CaseLogEntry(
        timeLabel: '08:42:13',
        level: CaseLogLevel.error,
        message: 'POST /drafts/save timed out after 5000ms',
      ),
      CaseLogEntry(
        timeLabel: '08:42:13',
        level: CaseLogLevel.warning,
        message: 'Autosave queue retained 1 pending draft for recovery',
      ),
      CaseLogEntry(
        timeLabel: '08:42:14',
        level: CaseLogLevel.info,
        message:
            'ARM evidence upload completed with screenshot and snapshot payload',
      ),
    ],
    contextFields: <CaseContextField>[
      CaseContextField(label: 'User', value: 'customer-1024'),
      CaseContextField(label: 'Checkout step', value: 'Shipping method'),
      CaseContextField(label: 'Browser', value: 'Chrome 137 on macOS'),
      CaseContextField(
        label: 'Release',
        value: 'customer-ops@2026.06.01+14',
      ),
      CaseContextField(label: 'Region', value: 'asia-southeast1'),
    ],
    snapshotTitle: 'Recovered draft snapshot',
    snapshotJson:
        '{\n'
        '  "draftId": "draft-88412",\n'
        '  "cartId": "cart-4881",\n'
        '  "step": "shipping_method",\n'
        '  "lineItems": 3,\n'
        '  "retryable": true,\n'
        '  "network": {\n'
        '    "attempt": 4,\n'
        '    "timeoutMs": 5000,\n'
        '    "endpoint": "/drafts/save"\n'
        '  }\n'
        '}',
    recoveryHints: <String>[
      'Replay the saved draft payload before asking support to rebuild the cart manually.',
      'Check the draft persistence service in asia-southeast1 for elevated connection timeout rates.',
      'Do not clear the user session until the follow-up confirms the draft was restored.',
    ],
    evidenceAssets: <CaseEvidenceAsset>[
      CaseEvidenceAsset(
        id: 'asset-checkout-screenshot',
        label: 'Checkout screenshot',
        caption:
            'Customer was stuck on the shipping method step after the autosave toast disappeared.',
        type: CaseAssetType.screenshot,
        status: CaseAssetStatus.available,
        capturedLabel: 'Captured 08:42',
        sourceLabel: 'Chrome web capture',
      ),
      CaseEvidenceAsset(
        id: 'asset-network-har',
        label: 'Request evidence bundle',
        caption:
            'Sanitized request/response metadata for the timed-out draft mutation.',
        type: CaseAssetType.attachment,
        status: CaseAssetStatus.available,
        capturedLabel: 'Captured 08:42',
        sourceLabel: 'ARM collector',
      ),
    ],
    missingEvidenceNotes: <String>[],
  ),
  'ARM-2026-00409': _CaseDetailSeed(
    environmentLabel: 'Production',
    detectedLabel: 'Detected 54 min ago',
    lastUpdatedLabel: 'Last updated 29 min ago',
    customerImpact:
        'The recovery snapshot was partially written, leaving support without a complete payload for replay.',
    narrative: <CaseNarrativeStep>[
      CaseNarrativeStep(
        label: '07:51',
        title: 'Snapshot capture started',
        description:
            'The checkout recovery job attempted to persist a snapshot after the payment retry failed.',
      ),
      CaseNarrativeStep(
        label: '07:52',
        title: 'Storage write interrupted',
        description:
            'The case retained trace metadata but the screenshot object expired before ARM could confirm upload.',
      ),
      CaseNarrativeStep(
        label: '08:16',
        title: 'Support follow-up requested',
        description:
            'A manual replay is still possible, but only with the partial recovery fields preserved in ARM.',
      ),
    ],
    traceSummary:
        'Recovery snapshot write aborted while finalizing object metadata.',
    traceBody:
        'StateError: Snapshot metadata missing storage generation.\n'
        '#0      RecoverySnapshotWriter.finalize (package:core_platform/src/recovery/snapshot_writer.dart:133)\n'
        '#1      CheckoutRecoveryService.capture (package:core_platform/src/recovery/checkout_recovery_service.dart:74)\n'
        '#2      _RootZone.runUnaryGuarded (dart:async/zone.dart:1778)\n',
    consoleLogs: <CaseLogEntry>[
      CaseLogEntry(
        timeLabel: '07:52:08',
        level: CaseLogLevel.warning,
        message: 'Screenshot asset upload expired before metadata finalize',
      ),
      CaseLogEntry(
        timeLabel: '07:52:08',
        level: CaseLogLevel.error,
        message: 'Snapshot finalize aborted: missing storage generation',
      ),
    ],
    contextFields: <CaseContextField>[
      CaseContextField(label: 'Project', value: 'Core platform'),
      CaseContextField(label: 'Recovery mode', value: 'Payment retry'),
      CaseContextField(label: 'Region', value: 'us-central1'),
      CaseContextField(label: 'Release', value: 'core-platform@2026.06.01+11'),
    ],
    snapshotTitle: 'Partial recovery snapshot',
    snapshotJson:
        '{\n'
        '  "snapshotId": "snap-55219",\n'
        '  "status": "partial",\n'
        '  "missing": ["screenshot", "storageGeneration"],\n'
        '  "recovery": {\n'
        '    "customerId": "customer-771",\n'
        '    "cartId": "cart-9821"\n'
        '  }\n'
        '}',
    recoveryHints: <String>[
      'Use the partial recovery object to locate the affected cart before retrying screenshot capture.',
      'Check Cloud Storage object lifecycle settings for early expiration on recovery captures.',
    ],
    evidenceAssets: <CaseEvidenceAsset>[
      CaseEvidenceAsset(
        id: 'asset-partial-snapshot',
        label: 'Snapshot payload',
        caption:
            'The snapshot JSON is intact even though the screenshot upload expired.',
        type: CaseAssetType.snapshot,
        status: CaseAssetStatus.available,
        capturedLabel: 'Captured 07:52',
        sourceLabel: 'Checkout recovery',
      ),
      CaseEvidenceAsset(
        id: 'asset-expired-screenshot',
        label: 'Checkout screenshot',
        caption:
            'The storage object expired before the console could reopen it.',
        type: CaseAssetType.screenshot,
        status: CaseAssetStatus.expired,
        capturedLabel: 'Expired after 15 min',
        sourceLabel: 'Cloud Storage',
      ),
    ],
    missingEvidenceNotes: <String>[
      'The primary screenshot evidence expired before ARM could confirm the upload.',
      'Only partial snapshot metadata is available for replay.',
    ],
  ),
};

CaseDetailRecord _fallbackCaseDetail(
  CaseRecord caseRecord,
  IssueRecord issueRecord,
) {
  return CaseDetailRecord(
    caseRecord: caseRecord,
    issueRecord: issueRecord,
    environmentLabel: caseRecord.projectLabel,
    detectedLabel: 'Detected ${caseRecord.reportedLabel}',
    lastUpdatedLabel: 'Last updated ${caseRecord.reportedLabel}',
    customerImpact:
        'Detailed evidence has not been hydrated for this seeded case yet, but the case remains visible for routing and read-only validation.',
    narrative: <CaseNarrativeStep>[
      CaseNarrativeStep(
        label: 'Pending',
        title: 'Detail payload unavailable',
        description:
            'The case metadata loaded successfully, but the full detail bundle has not been generated in the seeded repository.',
      ),
    ],
    traceSummary: 'No detailed trace was captured for this seeded case.',
    traceBody: 'No stack trace available.',
    consoleLogs: const <CaseLogEntry>[],
    contextFields: <CaseContextField>[
      CaseContextField(label: 'Issue', value: issueRecord.fingerprint),
      CaseContextField(label: 'Follow-up ID', value: caseRecord.followUpId),
    ],
    snapshotTitle: 'No snapshot captured',
    snapshotJson: '{\n  "status": "unavailable"\n}',
    recoveryHints: const <String>[
      'Use the linked issue and follow-up ID to continue investigation until the full evidence bundle is available.',
    ],
    evidenceAssets: const <CaseEvidenceAsset>[],
    missingEvidenceNotes: const <String>[
      'No seeded screenshot or attachment assets are available for this case.',
    ],
  );
}
