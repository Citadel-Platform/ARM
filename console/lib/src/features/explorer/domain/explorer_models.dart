import 'package:flutter/foundation.dart';

const int defaultExplorerPageSize = 5;

enum ExplorerSeverity {
  critical('Critical', 'critical', 3),
  high('High', 'high', 2),
  medium('Medium', 'medium', 1);

  const ExplorerSeverity(this.label, this.key, this.rank);

  final String label;
  final String key;
  final int rank;

  static ExplorerSeverity? fromKey(String key) {
    for (final ExplorerSeverity severity in ExplorerSeverity.values) {
      if (severity.key == key) {
        return severity;
      }
    }
    return null;
  }
}

enum ExplorerSeverityFilter {
  all('All severities', 'all'),
  criticalAndHigh('Critical + high', 'critical-high'),
  criticalOnly('Critical only', 'critical'),
  highOnly('High only', 'high'),
  mediumOnly('Medium only', 'medium');

  const ExplorerSeverityFilter(this.label, this.key);

  final String label;
  final String key;

  bool allows(ExplorerSeverity severity) {
    return switch (this) {
      ExplorerSeverityFilter.all => true,
      ExplorerSeverityFilter.criticalAndHigh =>
        severity == ExplorerSeverity.critical ||
        severity == ExplorerSeverity.high,
      ExplorerSeverityFilter.criticalOnly =>
        severity == ExplorerSeverity.critical,
      ExplorerSeverityFilter.highOnly => severity == ExplorerSeverity.high,
      ExplorerSeverityFilter.mediumOnly => severity == ExplorerSeverity.medium,
    };
  }

  static ExplorerSeverityFilter fromKey(String? key) {
    for (final ExplorerSeverityFilter filter in ExplorerSeverityFilter.values) {
      if (filter.key == key) {
        return filter;
      }
    }
    return ExplorerSeverityFilter.all;
  }
}

enum ExplorerDateRange {
  last24Hours('Last 24 hours', '24h', 24 * 60),
  last7Days('Last 7 days', '7d', 7 * 24 * 60),
  last30Days('Last 30 days', '30d', 30 * 24 * 60);

  const ExplorerDateRange(this.label, this.key, this.maxAgeMinutes);

  final String label;
  final String key;
  final int maxAgeMinutes;

  static ExplorerDateRange fromKey(String? key) {
    for (final ExplorerDateRange range in ExplorerDateRange.values) {
      if (range.key == key) {
        return range;
      }
    }
    return ExplorerDateRange.last7Days;
  }
}

enum IssueLifecycle {
  open('Open', 'open'),
  investigating('Investigating', 'investigating'),
  monitoring('Monitoring', 'monitoring');

  const IssueLifecycle(this.label, this.key);

  final String label;
  final String key;

  static IssueLifecycle? fromKey(String key) {
    for (final IssueLifecycle status in IssueLifecycle.values) {
      if (status.key == key) {
        return status;
      }
    }
    return null;
  }
}

enum IssueStatusFilter {
  all('All statuses', 'all'),
  open('Open only', 'open'),
  investigating('Investigating', 'investigating'),
  monitoring('Monitoring', 'monitoring');

  const IssueStatusFilter(this.label, this.key);

  final String label;
  final String key;

  bool allows(IssueLifecycle status) {
    return switch (this) {
      IssueStatusFilter.all => true,
      IssueStatusFilter.open => status == IssueLifecycle.open,
      IssueStatusFilter.investigating =>
        status == IssueLifecycle.investigating,
      IssueStatusFilter.monitoring => status == IssueLifecycle.monitoring,
    };
  }

  static IssueStatusFilter fromKey(String? key) {
    for (final IssueStatusFilter filter in IssueStatusFilter.values) {
      if (filter.key == key) {
        return filter;
      }
    }
    return IssueStatusFilter.all;
  }
}

enum IssueSort {
  latestActivity('Latest activity', 'latest'),
  severity('Severity', 'severity'),
  firstSeen('First seen', 'firstSeen'),
  caseCount('Linked cases', 'caseCount');

  const IssueSort(this.label, this.key);

  final String label;
  final String key;

  static IssueSort fromKey(String? key) {
    for (final IssueSort sort in IssueSort.values) {
      if (sort.key == key) {
        return sort;
      }
    }
    return IssueSort.latestActivity;
  }
}

enum CaseTriageStatus {
  newCase('New', 'new'),
  triaging('Triaging', 'triaging'),
  awaitingFollowUp('Awaiting follow-up', 'awaiting'),
  stale('Stale', 'stale');

  const CaseTriageStatus(this.label, this.key);

  final String label;
  final String key;

  static CaseTriageStatus? fromKey(String key) {
    for (final CaseTriageStatus status in CaseTriageStatus.values) {
      if (status.key == key) {
        return status;
      }
    }
    return null;
  }
}

enum CaseSort {
  reportedAt('Latest reported', 'reportedAt'),
  severity('Severity', 'severity'),
  caseId('Case ID', 'caseId');

  const CaseSort(this.label, this.key);

  final String label;
  final String key;

  static CaseSort fromKey(String? key) {
    for (final CaseSort sort in CaseSort.values) {
      if (sort.key == key) {
        return sort;
      }
    }
    return CaseSort.reportedAt;
  }
}

class IssuesQuery {
  const IssuesQuery({
    this.projectId,
    this.search = '',
    this.severityFilter = ExplorerSeverityFilter.all,
    this.range = ExplorerDateRange.last7Days,
    this.status = IssueStatusFilter.all,
    this.sort = IssueSort.latestActivity,
    this.page = 1,
    this.pageSize = defaultExplorerPageSize,
    this.selectedIssueId,
  });

  final String? projectId;
  final String search;
  final ExplorerSeverityFilter severityFilter;
  final ExplorerDateRange range;
  final IssueStatusFilter status;
  final IssueSort sort;
  final int page;
  final int pageSize;
  final String? selectedIssueId;

  factory IssuesQuery.fromUri(Uri uri) {
    return IssuesQuery(
      projectId: _emptyToNull(uri.queryParameters['project']),
      search: _normalizeSearch(uri.queryParameters['q']),
      severityFilter: ExplorerSeverityFilter.fromKey(
        uri.queryParameters['severity'],
      ),
      range: ExplorerDateRange.fromKey(uri.queryParameters['range']),
      status: IssueStatusFilter.fromKey(uri.queryParameters['status']),
      sort: IssueSort.fromKey(uri.queryParameters['sort']),
      page: _parsePage(uri.queryParameters['page']),
      selectedIssueId:
          _emptyToNull(uri.queryParameters['issueId']) ??
          _emptyToNull(uri.queryParameters['selectedIssue']),
    );
  }

  IssuesQuery copyWith({
    String? projectId,
    bool clearProject = false,
    String? search,
    ExplorerSeverityFilter? severityFilter,
    ExplorerDateRange? range,
    IssueStatusFilter? status,
    IssueSort? sort,
    int? page,
    int? pageSize,
    String? selectedIssueId,
    bool clearSelectedIssue = false,
  }) {
    return IssuesQuery(
      projectId: clearProject ? null : projectId ?? this.projectId,
      search: search ?? this.search,
      severityFilter: severityFilter ?? this.severityFilter,
      range: range ?? this.range,
      status: status ?? this.status,
      sort: sort ?? this.sort,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      selectedIssueId:
          clearSelectedIssue
              ? null
              : selectedIssueId ?? this.selectedIssueId,
    );
  }

  String toLocation() {
    final Map<String, String> queryParameters = <String, String>{};
    if (projectId != null) {
      queryParameters['project'] = projectId!;
    }
    if (search.isNotEmpty) {
      queryParameters['q'] = search;
    }
    if (severityFilter != ExplorerSeverityFilter.all) {
      queryParameters['severity'] = severityFilter.key;
    }
    if (range != ExplorerDateRange.last7Days) {
      queryParameters['range'] = range.key;
    }
    if (status != IssueStatusFilter.all) {
      queryParameters['status'] = status.key;
    }
    if (sort != IssueSort.latestActivity) {
      queryParameters['sort'] = sort.key;
    }
    if (page > 1) {
      queryParameters['page'] = '$page';
    }
    if (selectedIssueId != null) {
      queryParameters['issueId'] = selectedIssueId!;
    }
    return Uri(
      path: '/issues',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }
}

class CasesQuery {
  const CasesQuery({
    this.projectId,
    this.search = '',
    this.severityFilter = ExplorerSeverityFilter.all,
    this.range = ExplorerDateRange.last7Days,
    this.sort = CaseSort.reportedAt,
    this.page = 1,
    this.pageSize = defaultExplorerPageSize,
    this.issueId,
    this.selectedCase,
  });

  final String? projectId;
  final String search;
  final ExplorerSeverityFilter severityFilter;
  final ExplorerDateRange range;
  final CaseSort sort;
  final int page;
  final int pageSize;
  final String? issueId;
  final String? selectedCase;

  factory CasesQuery.fromUri(Uri uri) {
    return CasesQuery(
      projectId: _emptyToNull(uri.queryParameters['project']),
      search: _normalizeSearch(uri.queryParameters['q']),
      severityFilter: ExplorerSeverityFilter.fromKey(
        uri.queryParameters['severity'],
      ),
      range: ExplorerDateRange.fromKey(uri.queryParameters['range']),
      sort: CaseSort.fromKey(uri.queryParameters['sort']),
      page: _parsePage(uri.queryParameters['page']),
      issueId:
          _emptyToNull(uri.queryParameters['issueId']) ??
          _emptyToNull(uri.queryParameters['issue']),
      selectedCase: _emptyToNull(uri.queryParameters['selectedCase']),
    );
  }

  CasesQuery copyWith({
    String? projectId,
    bool clearProject = false,
    String? search,
    ExplorerSeverityFilter? severityFilter,
    ExplorerDateRange? range,
    CaseSort? sort,
    int? page,
    int? pageSize,
    String? issueId,
    bool clearIssueId = false,
    String? selectedCase,
    bool clearSelectedCase = false,
  }) {
    return CasesQuery(
      projectId: clearProject ? null : projectId ?? this.projectId,
      search: search ?? this.search,
      severityFilter: severityFilter ?? this.severityFilter,
      range: range ?? this.range,
      sort: sort ?? this.sort,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      issueId: clearIssueId ? null : issueId ?? this.issueId,
      selectedCase:
          clearSelectedCase ? null : selectedCase ?? this.selectedCase,
    );
  }

  String toLocation() {
    final Map<String, String> queryParameters = <String, String>{};
    if (projectId != null) {
      queryParameters['project'] = projectId!;
    }
    if (search.isNotEmpty) {
      queryParameters['q'] = search;
    }
    if (severityFilter != ExplorerSeverityFilter.all) {
      queryParameters['severity'] = severityFilter.key;
    }
    if (range != ExplorerDateRange.last7Days) {
      queryParameters['range'] = range.key;
    }
    if (sort != CaseSort.reportedAt) {
      queryParameters['sort'] = sort.key;
    }
    if (page > 1) {
      queryParameters['page'] = '$page';
    }
    if (issueId != null) {
      queryParameters['issueId'] = issueId!;
    }
    if (selectedCase != null) {
      queryParameters['selectedCase'] = selectedCase!;
    }
    return Uri(
      path: '/cases',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }
}

class IssueRecord {
  const IssueRecord({
    required this.issueId,
    required this.fingerprint,
    required this.title,
    required this.projectId,
    required this.projectLabel,
    required this.severity,
    required this.status,
    required this.firstSeenMinutesAgo,
    required this.lastSeenMinutesAgo,
    required this.totalCases,
    required this.urgencyLabel,
  });

  final String issueId;
  final String fingerprint;
  final String title;
  final String projectId;
  final String projectLabel;
  final ExplorerSeverity severity;
  final IssueLifecycle status;
  final int firstSeenMinutesAgo;
  final int lastSeenMinutesAgo;
  final int totalCases;
  final String urgencyLabel;

  String get firstSeenLabel => formatRelativeMinutes(firstSeenMinutesAgo);
  String get lastSeenLabel => formatRelativeMinutes(lastSeenMinutesAgo);
}

class CaseRecord {
  const CaseRecord({
    required this.caseId,
    required this.issueId,
    required this.issueFingerprint,
    required this.issueTitle,
    required this.projectId,
    required this.projectLabel,
    required this.severity,
    required this.reportedMinutesAgo,
    required this.status,
    required this.followUpId,
    required this.evidenceCount,
  });

  final String caseId;
  final String issueId;
  final String issueFingerprint;
  final String issueTitle;
  final String projectId;
  final String projectLabel;
  final ExplorerSeverity severity;
  final int reportedMinutesAgo;
  final CaseTriageStatus status;
  final String followUpId;
  final int evidenceCount;

  String get reportedLabel => formatRelativeMinutes(reportedMinutesAgo);
}

class IssuesResult {
  const IssuesResult({
    required this.records,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
    this.selectedIssue,
  });

  final List<IssueRecord> records;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final IssueRecord? selectedIssue;
}

class CasesResult {
  const CasesResult({
    required this.records,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
    this.selectedCase,
    this.issueFilterIssue,
  });

  final List<CaseRecord> records;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final CaseRecord? selectedCase;
  final IssueRecord? issueFilterIssue;
}

String formatRelativeMinutes(int minutes) {
  if (minutes < 60) {
    return '$minutes min ago';
  }
  if (minutes < 24 * 60) {
    final int hours = minutes ~/ 60;
    return '$hours h ago';
  }
  final int days = minutes ~/ (24 * 60);
  return '$days d ago';
}

int _parsePage(String? rawPage) {
  final int? parsed = int.tryParse(rawPage ?? '');
  if (parsed == null || parsed < 1) {
    return 1;
  }
  return parsed;
}

String _normalizeSearch(String? rawSearch) => rawSearch?.trim() ?? '';

String? _emptyToNull(String? value) {
  final String trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

bool isSameLocation(String left, String right) {
  final Uri leftUri = Uri.parse(left);
  final Uri rightUri = Uri.parse(right);
  return leftUri.path == rightUri.path &&
      mapEquals(leftUri.queryParameters, rightUri.queryParameters);
}
