import 'package:arm_console/src/features/explorer/domain/explorer_models.dart';

enum CaseAssetType { screenshot, snapshot, attachment }

enum CaseAssetStatus { available, expired, missing }

enum CaseLogLevel { info, warning, error }

class CaseNarrativeStep {
  const CaseNarrativeStep({
    required this.label,
    required this.title,
    required this.description,
  });

  final String label;
  final String title;
  final String description;
}

class CaseLogEntry {
  const CaseLogEntry({
    required this.timeLabel,
    required this.level,
    required this.message,
  });

  final String timeLabel;
  final CaseLogLevel level;
  final String message;
}

class CaseContextField {
  const CaseContextField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class CaseEvidenceAsset {
  const CaseEvidenceAsset({
    required this.id,
    required this.label,
    required this.caption,
    required this.type,
    required this.status,
    required this.capturedLabel,
    required this.sourceLabel,
  });

  final String id;
  final String label;
  final String caption;
  final CaseAssetType type;
  final CaseAssetStatus status;
  final String capturedLabel;
  final String sourceLabel;
}

class CaseDetailRecord {
  const CaseDetailRecord({
    required this.caseRecord,
    required this.issueRecord,
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

  final CaseRecord caseRecord;
  final IssueRecord issueRecord;
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

  bool get hasMissingEvidence => missingEvidenceNotes.isNotEmpty;
}
