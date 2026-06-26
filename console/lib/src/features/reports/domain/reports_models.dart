import 'package:arm_console/src/features/explorer/domain/explorer_models.dart';
import 'package:arm_console/src/features/projects/domain/project_models.dart';

enum ReportEnvironmentFilter {
  all('All environments', 'all'),
  production('Production only', 'prod'),
  staging('Staging only', 'staging');

  const ReportEnvironmentFilter(this.label, this.key);

  final String label;
  final String key;

  static ReportEnvironmentFilter fromKey(String? key) {
    for (final ReportEnvironmentFilter filter in values) {
      if (filter.key == key) {
        return filter;
      }
    }
    return ReportEnvironmentFilter.all;
  }
}

class ReportsQuery {
  const ReportsQuery({
    this.projectId,
    this.range = ExplorerDateRange.last7Days,
    this.severityFilter = ExplorerSeverityFilter.all,
    this.environmentFilter = ReportEnvironmentFilter.all,
  });

  final String? projectId;
  final ExplorerDateRange range;
  final ExplorerSeverityFilter severityFilter;
  final ReportEnvironmentFilter environmentFilter;

  factory ReportsQuery.fromUri(Uri uri) {
    return ReportsQuery(
      projectId: _emptyToNull(uri.queryParameters['project']),
      range: ExplorerDateRange.fromKey(uri.queryParameters['range']),
      severityFilter: ExplorerSeverityFilter.fromKey(
        uri.queryParameters['severity'],
      ),
      environmentFilter: ReportEnvironmentFilter.fromKey(
        uri.queryParameters['environment'] ?? uri.queryParameters['env'],
      ),
    );
  }

  ReportsQuery copyWith({
    String? projectId,
    bool clearProject = false,
    ExplorerDateRange? range,
    ExplorerSeverityFilter? severityFilter,
    ReportEnvironmentFilter? environmentFilter,
  }) {
    return ReportsQuery(
      projectId: clearProject ? null : projectId ?? this.projectId,
      range: range ?? this.range,
      severityFilter: severityFilter ?? this.severityFilter,
      environmentFilter: environmentFilter ?? this.environmentFilter,
    );
  }

  String toLocation() {
    final Map<String, String> queryParameters = <String, String>{};
    if (projectId != null) {
      queryParameters['project'] = projectId!;
    }
    if (range != ExplorerDateRange.last7Days) {
      queryParameters['range'] = range.key;
    }
    if (severityFilter != ExplorerSeverityFilter.all) {
      queryParameters['severity'] = severityFilter.key;
    }
    if (environmentFilter != ReportEnvironmentFilter.all) {
      queryParameters['environment'] = environmentFilter.key;
    }
    return Uri(
      path: '/reports',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }
}

class ReportProjectReference {
  const ReportProjectReference({
    required this.id,
    required this.name,
    required this.environmentLabel,
    this.firebaseConfig,
  });

  final String id;
  final String name;
  final String environmentLabel;
  final ProjectFirebaseConfig? firebaseConfig;
}

class ReportTrendPoint {
  const ReportTrendPoint({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;
}

class ReportTrendSeries {
  const ReportTrendSeries({
    required this.title,
    required this.subtitle,
    required this.targetPath,
    required this.points,
  });

  final String title;
  final String subtitle;
  final String targetPath;
  final List<ReportTrendPoint> points;

  int get total => points.fold(0, (int sum, ReportTrendPoint point) {
    return sum + point.value;
  });
}

class ReportDistributionBucket {
  const ReportDistributionBucket({
    required this.label,
    required this.value,
    required this.targetPath,
  });

  final String label;
  final int value;
  final String targetPath;
}

class ReportRepeatOffender {
  const ReportRepeatOffender({
    required this.issueId,
    required this.fingerprint,
    required this.projectId,
    required this.projectLabel,
    required this.severity,
    required this.caseCount,
    required this.targetPath,
  });

  final String issueId;
  final String fingerprint;
  final String projectId;
  final String projectLabel;
  final ExplorerSeverity severity;
  final int caseCount;
  final String targetPath;
}

class ReportProjectHotspot {
  const ReportProjectHotspot({
    required this.projectId,
    required this.projectLabel,
    required this.environmentLabel,
    required this.issueVolume,
    required this.caseVolume,
    required this.spikeLabel,
    required this.targetPath,
  });

  final String projectId;
  final String projectLabel;
  final String environmentLabel;
  final int issueVolume;
  final int caseVolume;
  final String spikeLabel;
  final String targetPath;
}

class ReportSpike {
  const ReportSpike({
    required this.title,
    required this.projectId,
    required this.projectLabel,
    required this.severity,
    required this.changeLabel,
    required this.targetPath,
  });

  final String title;
  final String projectId;
  final String projectLabel;
  final ExplorerSeverity severity;
  final String changeLabel;
  final String targetPath;
}

class ReportsSnapshot {
  const ReportsSnapshot({
    required this.query,
    required this.activeProjects,
    required this.issueVolumeTrend,
    required this.caseFrequencyTrend,
    required this.severityDistribution,
    required this.repeatOffenders,
    required this.hotspots,
    required this.spikes,
    required this.crossProjectComparisonAvailable,
  });

  final ReportsQuery query;
  final List<ReportProjectReference> activeProjects;
  final ReportTrendSeries issueVolumeTrend;
  final ReportTrendSeries caseFrequencyTrend;
  final List<ReportDistributionBucket> severityDistribution;
  final List<ReportRepeatOffender> repeatOffenders;
  final List<ReportProjectHotspot> hotspots;
  final List<ReportSpike> spikes;
  final bool crossProjectComparisonAvailable;

  int get totalIssueVolume => issueVolumeTrend.total;
  int get totalCaseVolume => caseFrequencyTrend.total;
  int get impactedProjectCount => activeProjects.length;
}

String? _emptyToNull(String? value) {
  final String trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
