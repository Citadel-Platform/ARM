import 'package:arm_console/src/features/projects/domain/project_models.dart';

enum OverviewDateRange {
  last24Hours('Last 24 hours', 1),
  last7Days('Last 7 days', 3),
  last30Days('Last 30 days', 7);

  const OverviewDateRange(this.label, this.multiplier);

  final String label;
  final int multiplier;
}

enum OverviewSeverityFilter {
  criticalOnly('Critical only'),
  criticalAndHigh('Critical and high');

  const OverviewSeverityFilter(this.label);

  final String label;
}

enum OverviewSeverity { critical, high, medium }

extension OverviewSeverityLabel on OverviewSeverity {
  String get label {
    return switch (this) {
      OverviewSeverity.critical => 'Critical',
      OverviewSeverity.high => 'High',
      OverviewSeverity.medium => 'Medium',
    };
  }
}

class DashboardScope {
  const DashboardScope.allProjects()
    : projectId = null,
      isAllProjects = true;

  const DashboardScope.project(this.projectId) : isAllProjects = false;

  final String? projectId;
  final bool isAllProjects;
}

class OverviewProjectReference {
  const OverviewProjectReference({
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

class OverviewQuery {
  const OverviewQuery({
    required this.dateRange,
    required this.severityFilter,
    required this.scope,
  });

  final OverviewDateRange dateRange;
  final OverviewSeverityFilter severityFilter;
  final DashboardScope scope;

  OverviewQuery copyWith({
    OverviewDateRange? dateRange,
    OverviewSeverityFilter? severityFilter,
    DashboardScope? scope,
  }) {
    return OverviewQuery(
      dateRange: dateRange ?? this.dateRange,
      severityFilter: severityFilter ?? this.severityFilter,
      scope: scope ?? this.scope,
    );
  }
}

class OverviewCounts {
  const OverviewCounts({
    required this.criticalIssues,
    required this.openCases,
    required this.freshIncidents,
    required this.healthyProjects,
  });

  final int criticalIssues;
  final int openCases;
  final int freshIncidents;
  final int healthyProjects;
}

class OverviewTrendPoint {
  const OverviewTrendPoint({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;
}

class OverviewTrendSeries {
  const OverviewTrendSeries({
    required this.title,
    required this.subtitle,
    required this.targetPath,
    required this.points,
  });

  final String title;
  final String subtitle;
  final String targetPath;
  final List<OverviewTrendPoint> points;
}

class OverviewQueueItem {
  const OverviewQueueItem({
    required this.title,
    required this.subtitle,
    required this.projectLabel,
    required this.severity,
    required this.routePath,
    required this.incidentCount,
  });

  final String title;
  final String subtitle;
  final String projectLabel;
  final OverviewSeverity severity;
  final String routePath;
  final int incidentCount;
}

enum OverviewPostureTone { neutral, attention, critical, positive }

class OverviewPostureCard {
  const OverviewPostureCard({
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

class OverviewSeverityMix {
  const OverviewSeverityMix({
    required this.critical,
    required this.high,
    required this.medium,
  });

  final int critical;
  final int high;
  final int medium;

  int get total => critical + high + medium;
}

class OverviewSnapshot {
  const OverviewSnapshot({
    required this.query,
    required this.activeProjects,
    required this.counts,
    required this.urgentItems,
    required this.postureCards,
    required this.issueVolumeTrend,
    required this.severityTrend,
    required this.severityMix,
    required this.overloaded,
  });

  final OverviewQuery query;
  final List<OverviewProjectReference> activeProjects;
  final OverviewCounts counts;
  final List<OverviewQueueItem> urgentItems;
  final List<OverviewPostureCard> postureCards;
  final OverviewTrendSeries issueVolumeTrend;
  final OverviewTrendSeries severityTrend;
  final OverviewSeverityMix severityMix;
  final bool overloaded;

  bool get isEmpty =>
      counts.criticalIssues == 0 &&
      counts.openCases == 0 &&
      counts.freshIncidents == 0 &&
      urgentItems.isEmpty &&
      postureCards.isEmpty;
}
