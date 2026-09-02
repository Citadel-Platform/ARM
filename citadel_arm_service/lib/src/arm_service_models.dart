import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'arm_service_models.freezed.dart';

const int armDefaultPageSize = 25;
const int armMaximumPageSize = 100;

enum ArmIssueStatus {
  open,
  investigating,
  triaging,
  monitoring,
  resolved,
  closed,
}

enum ArmCaseStatus {
  newCase,
  acknowledged,
  triaging,
  monitoring,
  resolved,
  closed,
}

/// How serious a fault is held to be.
///
/// Held apart from status throughout. Status is where triage got to; severity
/// is how bad the thing is, and a case can be resolved and still have been
/// critical. A capture arrives with the severity the SDK derived from the
/// exception, and the person reading it is the one who knows whether that was
/// right — so it is operator-changeable, and the change is recorded beside the
/// captured value rather than over it.
enum ArmSeverity { critical, high, medium, low }

enum ArmPrivateOperation {
  listIssues,
  listCases,
  getCaseDetail,
  updateIssueStatus,
  updateCaseStatus,
  updateCaseSeverity,
  updateIssueTags,
  listTickets,
  getTicket,
  createTicket,
  updateTicketStatus,
  appendTicketUpdate,
  updateTicketAccess,
  readAlerting,
  writePolicy,
  deletePolicy,
  writeChannel,
  deleteChannel,
  testChannel,
}

enum ArmServiceErrorCode {
  invalidArgument,
  unauthenticated,
  permissionDenied,
  notFound,
  failedPrecondition,
  unavailable,
  internal,
}

@freezed
abstract class ArmPageCursor with _$ArmPageCursor {
  const factory ArmPageCursor({
    required DateTime timestamp,
    required String documentId,
  }) = _ArmPageCursor;
}

@freezed
abstract class ArmIssueRecord with _$ArmIssueRecord {
  const factory ArmIssueRecord({
    required String issueId,
    required String severity,
    required String category,
    required String feature,
    required String operation,
    required DateTime firstSeenAt,
    required DateTime lastSeenAt,
    required int caseCount,
    String? firstCaseId,
    String? lastCaseId,
    ArmIssueStatus? status,
    String? appVersion,
    String? buildNumber,
    String? releaseChannel,

    /// Which of the client's environments this was seen in.
    ///
    /// One `citadel-arm` database holds all four — production, staging, test
    /// and dev — distinguished by this rather than by four databases, because
    /// Citadel compares them: the same fault in staging and in production is
    /// one question, and four stores would make it a join nothing can do. See
    /// DECISIONS.md 02/09/26.
    ///
    /// Nullable, and read as "not recorded" rather than defaulted to
    /// production. A record written before this existed came from an unknown
    /// environment, and calling it production would put staging noise in front
    /// of somebody looking at a live incident.
    String? environment,

    /// What this fingerprint is, in the project's own words.
    ///
    /// One list, whether a policy assigned it or a person did. Somebody
    /// triaging a fault cares that it is a regression, not which of the two
    /// said so; where a tag came from belongs in the fingerprint's history.
    ///
    /// Ordered and deduplicated on write, so a tag set is comparable between
    /// two reads of the same fingerprint.
    @Default(<String>[]) List<String> tags,
  }) = _ArmIssueRecord;
}

@freezed
abstract class ArmCaseRecord with _$ArmCaseRecord {
  const factory ArmCaseRecord({
    required String caseId,
    required String issueId,
    required String fingerprint,
    required String severity,
    required String category,
    required String feature,
    required String operation,
    required String message,
    required String errorType,
    required String stackTrace,
    required String sessionId,
    required bool handled,
    required DateTime createdAt,
    @Default(<String, Object?>{}) Map<String, Object?> context,
    @Default(<String, Object?>{}) Map<String, Object?> tags,
    @Default(<Map<String, Object?>>[]) List<Map<String, Object?>> breadcrumbs,
    String? errorName,
    Map<String, Object?>? errorData,
    Map<String, Object?>? recoverySnapshot,
    Map<String, Object?>? screenshot,
    ArmCaseStatus? status,

    /// Which of the client's environments this occurrence came from. See
    /// [ArmIssueRecord.environment]; null means it was not recorded.
    String? environment,
    String? appVersion,
    String? buildNumber,
    String? releaseChannel,

    /// The severity an operator set, when one did.
    ///
    /// Beside [severity] rather than over it: `severity` is what the capture
    /// arrived with, and losing that would make "did we treat this as urgent,
    /// and were we right to" unanswerable afterwards.
    String? operatorSeverity,
    String? severityUpdatedBy,
    DateTime? severityUpdatedAt,
  }) = _ArmCaseRecord;
}

@freezed
abstract class ArmIssueQuery with _$ArmIssueQuery {
  const factory ArmIssueQuery({
    DateTime? since,

    /// Restrict to one of the client's environments.
    ///
    /// Null means every environment, which is what an operator looking at a
    /// client as a whole wants. Filtering is opt-in rather than defaulted to
    /// production: a default would hide staging faults from the page that
    /// exists to show faults, and nothing would say it had.
    String? environment,
    @Default(armDefaultPageSize) int pageSize,
    ArmPageCursor? cursor,
  }) = _ArmIssueQuery;
}

@freezed
abstract class ArmCaseQuery with _$ArmCaseQuery {
  const factory ArmCaseQuery({
    DateTime? since,
    String? issueId,

    /// Restrict to one of the client's environments. Null means every one.
    String? environment,
    @Default(armDefaultPageSize) int pageSize,
    ArmPageCursor? cursor,
  }) = _ArmCaseQuery;
}

@freezed
abstract class ArmIssuePage with _$ArmIssuePage {
  const factory ArmIssuePage({
    required String projectId,
    @Default(<ArmIssueRecord>[]) List<ArmIssueRecord> issues,
    String? nextPageToken,
  }) = _ArmIssuePage;
}

@freezed
abstract class ArmCasePage with _$ArmCasePage {
  const factory ArmCasePage({
    required String projectId,
    @Default(<ArmCaseRecord>[]) List<ArmCaseRecord> cases,
    String? nextPageToken,
  }) = _ArmCasePage;
}

@freezed
abstract class ArmIssuePageSlice with _$ArmIssuePageSlice {
  const factory ArmIssuePageSlice({
    @Default(<ArmIssueRecord>[]) List<ArmIssueRecord> issues,
    @Default(false) bool hasMore,
  }) = _ArmIssuePageSlice;
}

@freezed
abstract class ArmCasePageSlice with _$ArmCasePageSlice {
  const factory ArmCasePageSlice({
    @Default(<ArmCaseRecord>[]) List<ArmCaseRecord> cases,
    @Default(false) bool hasMore,
  }) = _ArmCasePageSlice;
}

@freezed
abstract class ArmCaseDetail with _$ArmCaseDetail {
  const factory ArmCaseDetail({
    required String projectId,
    required ArmCaseRecord caseRecord,
    required ArmIssueRecord issue,
  }) = _ArmCaseDetail;
}

@freezed
abstract class ArmIssueStatusPatch with _$ArmIssueStatusPatch {
  const factory ArmIssueStatusPatch({required ArmIssueStatus status}) =
      _ArmIssueStatusPatch;
}

@freezed
abstract class ArmCaseStatusPatch with _$ArmCaseStatusPatch {
  const factory ArmCaseStatusPatch({required ArmCaseStatus status}) =
      _ArmCaseStatusPatch;
}

@freezed
abstract class ArmCaseSeverityPatch with _$ArmCaseSeverityPatch {
  const factory ArmCaseSeverityPatch({required ArmSeverity severity}) =
      _ArmCaseSeverityPatch;
}

/// A tag change, as a whole set rather than an add and a remove.
///
/// Two operators editing the same fingerprint's tags at once would otherwise
/// interleave into a set neither of them chose. Sending the whole set makes
/// the last write win visibly instead of silently.
@freezed
abstract class ArmIssueTagsPatch with _$ArmIssueTagsPatch {
  const factory ArmIssueTagsPatch({@Default(<String>[]) List<String> tags}) =
      _ArmIssueTagsPatch;
}

@freezed
abstract class ArmAuthorizedPrincipal with _$ArmAuthorizedPrincipal {
  const factory ArmAuthorizedPrincipal({
    required String actorId,
    String? actorEmail,
  }) = _ArmAuthorizedPrincipal;
}

@freezed
abstract class ArmAuthorizationRequest with _$ArmAuthorizationRequest {
  const factory ArmAuthorizationRequest({
    required String requestId,
    required ArmPrivateOperation operation,
    required String projectId,
    required String authorizationHeader,

    /// Actor coordinates forwarded by the calling Platform API. They are only
    /// trustworthy once the caller itself has been verified.
    String? forwardedActorId,
    String? forwardedActorEmail,
  }) = _ArmAuthorizationRequest;
}

@freezed
abstract class ArmIssueStatusMutation with _$ArmIssueStatusMutation {
  const factory ArmIssueStatusMutation({
    required ArmIssueStatus status,
    required String updatedBy,
    @Default('citadel_platform_operator') String statusSource,
  }) = _ArmIssueStatusMutation;
}

/// An operator's triage decision on a case.
///
/// It deliberately carries no `handled` flag. Whether the application caught
/// the error is capture evidence recorded at the boundary; overwriting it from
/// a triage command would destroy that record.
@freezed
abstract class ArmCaseStatusMutation with _$ArmCaseStatusMutation {
  const factory ArmCaseStatusMutation({
    required ArmCaseStatus status,
    required String updatedBy,
    @Default('citadel_platform_operator') String statusSource,
  }) = _ArmCaseStatusMutation;
}

@freezed
abstract class ArmCaseSeverityMutation with _$ArmCaseSeverityMutation {
  const factory ArmCaseSeverityMutation({
    required ArmSeverity severity,
    required String updatedBy,
    @Default('citadel_platform_operator') String severitySource,
  }) = _ArmCaseSeverityMutation;
}

@freezed
abstract class ArmIssueTagsMutation with _$ArmIssueTagsMutation {
  const factory ArmIssueTagsMutation({
    required List<String> tags,
    required String updatedBy,
    @Default('citadel_platform_operator') String tagSource,
  }) = _ArmIssueTagsMutation;
}

@freezed
abstract class ArmServiceError with _$ArmServiceError {
  const factory ArmServiceError({
    required ArmServiceErrorCode code,
    required String message,
    required String requestId,
    @Default(false) bool retryable,
    @Default(<String, String>{}) Map<String, String> details,
  }) = _ArmServiceError;
}

typedef ArmPrivateRequestAuthorizer =
    FutureOr<ArmAuthorizedPrincipal?> Function(ArmAuthorizationRequest request);

// ---------------------------------------------------------------------------
// Alerting: policies and notification channels (Feature 1.4.6)
// ---------------------------------------------------------------------------

/// Which field of a fingerprint a rule looks at.
///
/// A closed set, because a rule naming a field nothing stores is a rule that
/// silently never matches — and a policy that never matches looks exactly like
/// one that is working and finding nothing.
enum ArmPolicyField {
  title,
  severity,
  errorType,
  status,
  releaseVersion,
  caseCount,
}

/// How a rule compares.
enum ArmPolicyOperator {
  contains,
  notContains,
  equals,
  notEquals,
  startsWith,
  atLeast,
}

/// How a rule joins the one before it.
///
/// Flat, left to right. Groups are deliberately not modelled: a stored shape
/// the evaluator cannot evaluate is worse than one that admits it does not
/// nest, and adding nesting later is a change to the model and the evaluator
/// together rather than to the model alone.
enum ArmPolicyJoin { and, or }

enum ArmChannelType { email, whatsApp, webhook }

@freezed
abstract class ArmPolicyRule with _$ArmPolicyRule {
  const factory ArmPolicyRule({
    @Default(ArmPolicyJoin.and) ArmPolicyJoin join,
    required ArmPolicyField field,
    required ArmPolicyOperator operator,
    required String value,
  }) = _ArmPolicyRule;
}

/// What a policy does when a fingerprint matches it.
///
/// Tagging happens whether or not anybody is notified, which is why the
/// channel list may be empty and the tag list may not: a policy that neither
/// tags nor notifies is a rule nobody can observe running.
@freezed
abstract class ArmPolicyRecord with _$ArmPolicyRecord {
  const factory ArmPolicyRecord({
    required String policyId,
    required String displayName,
    @Default(true) bool enabled,
    @Default(<ArmPolicyRule>[]) List<ArmPolicyRule> rules,
    @Default(<String>[]) List<String> tags,
    @Default(<String>[]) List<String> channelIds,
    DateTime? updatedAt,
    String? updatedBy,
  }) = _ArmPolicyRecord;
}

/// Where a matching fingerprint is sent.
///
/// Recipients are typed to the channel — addresses for email, numbers for
/// WhatsApp, one URL for a webhook — and validated against that type rather
/// than accepted as strings, because a malformed recipient is a notification
/// nobody receives and nobody knows was not received.
@freezed
abstract class ArmNotificationChannel with _$ArmNotificationChannel {
  const factory ArmNotificationChannel({
    required String channelId,
    required String displayName,
    required ArmChannelType type,
    @Default(<String>[]) List<String> recipients,
    @Default(true) bool enabled,
    DateTime? lastTestedAt,
    String? lastTestOutcome,
    DateTime? updatedAt,
    String? updatedBy,
  }) = _ArmNotificationChannel;
}

@freezed
abstract class ArmAlertingConfiguration with _$ArmAlertingConfiguration {
  const factory ArmAlertingConfiguration({
    required String projectId,
    @Default(<ArmPolicyRecord>[]) List<ArmPolicyRecord> policies,
    @Default(<ArmNotificationChannel>[]) List<ArmNotificationChannel> channels,
  }) = _ArmAlertingConfiguration;
}

/// What happened when a channel was tested.
///
/// Names the recipients it reached rather than reporting a bare boolean: a
/// test that "succeeded" without saying where it went proves the code path
/// and not the configuration, and the configuration is the thing that is
/// usually wrong.
@freezed
abstract class ArmChannelTestOutcome with _$ArmChannelTestOutcome {
  const factory ArmChannelTestOutcome({
    required String channelId,
    required bool delivered,
    required DateTime testedAt,
    @Default(<String>[]) List<String> reached,
    String? reason,
  }) = _ArmChannelTestOutcome;
}

/// Sends a message on a channel.
///
/// A seam rather than a client, so what has to be testable is the rule about
/// which recipients a test reaches, not anybody's transport. Absent, the
/// service says it cannot test rather than reporting a delivery that did not
/// happen.
typedef ArmChannelSender =
    Future<ArmChannelTestOutcome> Function(
      ArmNotificationChannel channel,
      String body,
    );

// ---------------------------------------------------------------------------
// Tickets (Feature 1.5)
// ---------------------------------------------------------------------------

/// Where a ticket has got to.
///
/// Four states, and deliberately not the six a case has: a case's status is
/// triage of evidence, and a ticket's is a promise to a person who is waiting.
/// `investigating` and `inProgress` are both "we are on it", kept apart
/// because the first means nobody knows what is wrong yet and the second means
/// somebody is fixing it, and a customer reads those very differently.
enum ArmTicketStatus { open, investigating, inProgress, closed }

/// Who wrote an entry in a ticket's history.
///
/// Recorded rather than inferred from the address: the same person may write
/// as a customer on one ticket and as an operator on another, and a history
/// that guessed would attribute a promise to the wrong side of it.
enum ArmTicketAuthorKind { endUser, operator }

/// One file on a ticket or one of its updates.
///
/// The bytes are never here. A ticket document is read by the Console, by the
/// public ticket route and by anybody the allowlist admits, and an image
/// inlined into it would be copied into every one of those reads.
@freezed
abstract class ArmTicketAttachment with _$ArmTicketAttachment {
  const factory ArmTicketAttachment({
    required String attachmentId,
    required String fileName,
    required String contentType,
    required int sizeBytes,

    /// Where the bytes are, in the project's own storage. Resolved to a
    /// time-limited URL at read time by whoever is allowed to read it, never
    /// stored as one.
    ///
    /// Absent on the public view of a ticket. A bucket and a key are Citadel's
    /// storage layout, not a customer's business, and the id above is the only
    /// handle a reader needs to ask for a file they are allowed to have.
    String? storagePath,
  }) = _ArmTicketAttachment;
}

/// One timestamped entry in a ticket's history.
///
/// Markdown, because both sides write into the same thread and a customer
/// pasting a log needs it to survive. Rendered by the reader, never by the
/// writer: a stored rendering is a stored decision about how much HTML to
/// trust.
@freezed
abstract class ArmTicketUpdate with _$ArmTicketUpdate {
  const factory ArmTicketUpdate({
    required String updateId,
    required ArmTicketAuthorKind authorKind,

    /// How the author is named to a reader. An operator's address, or what the
    /// customer gave when they opened the ticket.
    required String authorLabel,
    required String body,
    required DateTime createdAt,
    @Default(<ArmTicketAttachment>[]) List<ArmTicketAttachment> attachments,
  }) = _ArmTicketUpdate;
}

/// A support ticket: one person waiting, and everything said to them.
///
/// Pegged to evidence rather than containing it. A ticket names the case logs
/// and the fingerprint it is about, so that "which faults did customers
/// actually write in about" is answerable — and so that the evidence itself
/// stays in one place, under the redaction the Console already applies.
@freezed
abstract class ArmTicketRecord with _$ArmTicketRecord {
  const factory ArmTicketRecord({
    required String ticketId,
    required String title,
    required String description,
    required ArmTicketStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// Who opened it, as they identified themselves. An address or a number
    /// typed into an error dialog — never verified, and never treated as
    /// though it were.
    String? reporterContact,

    /// Whether Citadel or a person opened it. `citadel_arm_client` for one
    /// raised from an error dialog.
    required String createdBy,

    /// The evidence this ticket is about.
    @Default(<String>[]) List<String> caseIds,
    String? issueId,
    String? sessionId,

    /// Who may read it, beyond anybody with the link.
    ///
    /// Empty means the link is the access control, and a ticket in that state
    /// is served without its evidence coordinates: a public link carries the
    /// conversation, never the stack trace and session it points at.
    @Default(<String>[]) List<String> allowlist,
    @Default(<ArmTicketUpdate>[]) List<ArmTicketUpdate> updates,
    @Default(<ArmTicketAttachment>[]) List<ArmTicketAttachment> attachments,
    String? statusUpdatedBy,
    DateTime? statusUpdatedAt,
  }) = _ArmTicketRecord;
}

/// Whether a ticket's link alone is enough to read it.
extension ArmTicketAccessModel on ArmTicketRecord {
  bool get isPublicByLink => allowlist.isEmpty;
}

@freezed
abstract class ArmTicketQuery with _$ArmTicketQuery {
  const factory ArmTicketQuery({
    ArmTicketStatus? status,
    String? issueId,
    @Default(armDefaultPageSize) int pageSize,
    ArmPageCursor? cursor,
  }) = _ArmTicketQuery;
}

@freezed
abstract class ArmTicketPage with _$ArmTicketPage {
  const factory ArmTicketPage({
    required String projectId,
    @Default(<ArmTicketRecord>[]) List<ArmTicketRecord> tickets,
    String? nextPageToken,
  }) = _ArmTicketPage;
}

@freezed
abstract class ArmTicketPageSlice with _$ArmTicketPageSlice {
  const factory ArmTicketPageSlice({
    @Default(<ArmTicketRecord>[]) List<ArmTicketRecord> tickets,
    @Default(false) bool hasMore,
  }) = _ArmTicketPageSlice;
}

/// What is needed to open a ticket.
///
/// The id is not here: it is minted by the service, because a caller that
/// chooses ticket ids can overwrite somebody else's ticket by choosing theirs.
@freezed
abstract class ArmTicketDraft with _$ArmTicketDraft {
  const factory ArmTicketDraft({
    required String title,
    required String description,
    String? reporterContact,
    @Default(<String>[]) List<String> caseIds,
    String? issueId,
    String? sessionId,
    @Default(<String>[]) List<String> allowlist,
    @Default(<ArmTicketAttachment>[]) List<ArmTicketAttachment> attachments,
  }) = _ArmTicketDraft;
}

/// One entry somebody is adding to a ticket's history.
@freezed
abstract class ArmTicketUpdateDraft with _$ArmTicketUpdateDraft {
  const factory ArmTicketUpdateDraft({
    required ArmTicketAuthorKind authorKind,
    required String body,
    @Default(<ArmTicketAttachment>[]) List<ArmTicketAttachment> attachments,
  }) = _ArmTicketUpdateDraft;
}

@freezed
abstract class ArmTicketStatusPatch with _$ArmTicketStatusPatch {
  const factory ArmTicketStatusPatch({required ArmTicketStatus status}) =
      _ArmTicketStatusPatch;
}

/// A whole allowlist, for the same reason a tag change is a whole set: two
/// operators adding one address each would otherwise interleave into a list
/// neither of them chose.
@freezed
abstract class ArmTicketAccessPatch with _$ArmTicketAccessPatch {
  const factory ArmTicketAccessPatch({
    @Default(<String>[]) List<String> allowlist,
  }) = _ArmTicketAccessPatch;
}
