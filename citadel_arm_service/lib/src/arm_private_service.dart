import 'dart:math';

import 'arm_service_json.dart';
import 'arm_service_models.dart';

abstract interface class ArmEvidenceRepository {
  Future<ArmIssuePageSlice> listIssues({
    required String projectId,
    required ArmIssueQuery query,
  });

  Future<ArmCasePageSlice> listCases({
    required String projectId,
    required ArmCaseQuery query,
  });

  Future<ArmCaseDetail?> getCaseDetail({
    required String projectId,
    required String caseId,
  });

  Future<ArmIssueRecord?> updateIssueStatus({
    required String projectId,
    required String issueId,
    required ArmIssueStatusMutation mutation,
  });

  Future<ArmCaseRecord?> updateCaseStatus({
    required String projectId,
    required String caseId,
    required ArmCaseStatusMutation mutation,
  });

  Future<ArmCaseRecord?> updateCaseSeverity({
    required String projectId,
    required String caseId,
    required ArmCaseSeverityMutation mutation,
  });

  Future<ArmIssueRecord?> updateIssueTags({
    required String projectId,
    required String issueId,
    required ArmIssueTagsMutation mutation,
  });

  /// The tickets a project's customers and developers have opened.
  Future<ArmTicketPageSlice> listTickets({
    required String projectId,
    required ArmTicketQuery query,
  });

  Future<ArmTicketRecord?> getTicket({
    required String projectId,
    required String ticketId,
  });

  /// Writes a whole ticket.
  ///
  /// Whole rather than patched, because a ticket is read, changed and written
  /// by one caller at a time and a partial write of a history is a history
  /// with a hole in it. The service reads before it writes and the repository
  /// stores what it is given.
  Future<ArmTicketRecord> writeTicket({
    required String projectId,
    required ArmTicketRecord ticket,
  });

  /// A project's alerting policies and notification channels.
  ///
  /// Read as one document rather than two collections: they are edited
  /// together, a policy names channels by id, and a read that returned
  /// policies referencing channels it had not fetched would render a policy
  /// notifying nothing.
  Future<ArmAlertingConfiguration> readAlerting({required String projectId});

  Future<ArmAlertingConfiguration> writeAlerting({
    required String projectId,
    required ArmAlertingConfiguration configuration,
    required String updatedBy,
  });
}

final class ArmServiceException implements Exception {
  const ArmServiceException({
    required this.code,
    required this.message,
    this.retryable = false,
    this.details = const <String, String>{},
  });

  final ArmServiceErrorCode code;
  final String message;
  final bool retryable;
  final Map<String, String> details;
}

final class ArmPrivateService {
  ArmPrivateService({
    required ArmEvidenceRepository repository,
    ArmChannelSender? channelSender,
    DateTime Function()? clock,
    String Function()? generateId,
  }) : _repository = repository,
       _sender = channelSender,
       _clock = clock ?? _utcNow,
       _generateId = generateId ?? _randomResourceId;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Ticket and history-entry identifiers.
  ///
  /// Minted here rather than accepted from a caller: an id chosen by whoever
  /// is opening a ticket is an id that can be made to collide with somebody
  /// else's, and the public route accepts writes from people nobody has
  /// authenticated.
  static String _randomResourceId() {
    final Random random = Random.secure();
    const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(<int>[
      for (int index = 0; index < 20; index += 1)
        alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ]);
  }

  final ArmEvidenceRepository _repository;
  final DateTime Function() _clock;
  final String Function() _generateId;

  /// How a test message actually goes out. Absent on a deployment with no
  /// transport, and the route then says it cannot test rather than reporting a
  /// delivery that did not happen.
  final ArmChannelSender? _sender;

  Future<ArmIssuePage> listIssues({
    required String projectId,
    required ArmIssueQuery query,
  }) async {
    final target = _projectId(projectId);
    _validateIssueQuery(query);
    final slice = await _repository.listIssues(projectId: target, query: query);
    if (slice.issues.length > query.pageSize ||
        (slice.hasMore && slice.issues.isEmpty)) {
      throw _invalidRepositoryPage();
    }
    final issues = slice.issues.map(_validatedIssue).toList(growable: false)
      ..sort(_compareIssues);
    return ArmIssuePage(
      projectId: target,
      issues: issues,
      nextPageToken: slice.hasMore
          ? encodeArmPageToken(
              ArmPageCursor(
                timestamp: issues.last.lastSeenAt,
                documentId: issues.last.issueId,
              ),
            )
          : null,
    );
  }

  Future<ArmCasePage> listCases({
    required String projectId,
    required ArmCaseQuery query,
  }) async {
    final target = _projectId(projectId);
    _validateCaseQuery(query);
    final slice = await _repository.listCases(projectId: target, query: query);
    if (slice.cases.length > query.pageSize ||
        (slice.hasMore && slice.cases.isEmpty)) {
      throw _invalidRepositoryPage();
    }
    final cases = slice.cases.map(_validatedCase).toList(growable: false)
      ..sort(_compareCases);
    return ArmCasePage(
      projectId: target,
      cases: cases,
      nextPageToken: slice.hasMore
          ? encodeArmPageToken(
              ArmPageCursor(
                timestamp: cases.last.createdAt,
                documentId: cases.last.caseId,
              ),
            )
          : null,
    );
  }

  Future<ArmCaseDetail> getCaseDetail({
    required String projectId,
    required String caseId,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(caseId, 'caseId');
    final detail = await _repository.getCaseDetail(
      projectId: target,
      caseId: id,
    );
    if (detail == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM case was not found.',
      );
    }
    final caseRecord = _validatedCase(detail.caseRecord);
    final issue = _validatedIssue(detail.issue);
    if (detail.projectId != target ||
        caseRecord.caseId != id ||
        caseRecord.issueId != issue.issueId) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned inconsistent case detail.',
      );
    }
    return ArmCaseDetail(
      projectId: target,
      caseRecord: caseRecord,
      issue: issue,
    );
  }

  Future<ArmIssueRecord> updateIssueStatus({
    required String projectId,
    required String issueId,
    required ArmIssueStatus status,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(issueId, 'issueId');
    final updated = await _repository.updateIssueStatus(
      projectId: target,
      issueId: id,
      mutation: ArmIssueStatusMutation(
        status: status,
        updatedBy: _operatorEmail(principal),
      ),
    );
    if (updated == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM issue was not found.',
      );
    }
    final validated = _validatedIssue(updated);
    if (validated.issueId != id || validated.status != status) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an inconsistent issue update.',
      );
    }
    return validated;
  }

  Future<ArmCaseRecord> updateCaseStatus({
    required String projectId,
    required String caseId,
    required ArmCaseStatus status,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(caseId, 'caseId');
    final updated = await _repository.updateCaseStatus(
      projectId: target,
      caseId: id,
      mutation: ArmCaseStatusMutation(
        status: status,
        updatedBy: _operatorEmail(principal),
      ),
    );
    if (updated == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM case was not found.',
      );
    }
    final validated = _validatedCase(updated);
    if (validated.caseId != id || validated.status != status) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an inconsistent case update.',
      );
    }
    return validated;
  }

  /// An operator's judgement about how bad a fault is.
  ///
  /// Recorded beside the captured severity, never over it. Losing what the
  /// capture arrived with would make "did we treat this as urgent, and were we
  /// right to" unanswerable — which is the question asked after the incident,
  /// by somebody who was not there.
  Future<ArmCaseRecord> updateCaseSeverity({
    required String projectId,
    required String caseId,
    required ArmSeverity severity,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(caseId, 'caseId');
    final updated = await _repository.updateCaseSeverity(
      projectId: target,
      caseId: id,
      mutation: ArmCaseSeverityMutation(
        severity: severity,
        updatedBy: _operatorEmail(principal),
      ),
    );
    if (updated == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM case was not found.',
      );
    }
    final validated = _validatedCase(updated);
    if (validated.caseId != id ||
        validated.operatorSeverity != armSeverityWireName(severity)) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an inconsistent case update.',
      );
    }
    return validated;
  }

  /// The whole tag set, not an add and a remove.
  ///
  /// Two operators editing one fingerprint at once would otherwise interleave
  /// into a set neither chose. Replacing the set makes the last write win
  /// visibly rather than silently.
  Future<ArmIssueRecord> updateIssueTags({
    required String projectId,
    required String issueId,
    required List<String> tags,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(issueId, 'issueId');
    final normalized = armNormalizedTags(tags, r'$.tags');
    final updated = await _repository.updateIssueTags(
      projectId: target,
      issueId: id,
      mutation: ArmIssueTagsMutation(
        tags: normalized,
        updatedBy: _operatorEmail(principal),
      ),
    );
    if (updated == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM issue was not found.',
      );
    }
    final validated = _validatedIssue(updated);
    if (validated.issueId != id ||
        validated.tags.join(',') != normalized.join(',')) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an inconsistent issue update.',
      );
    }
    return validated;
  }

  // -------------------------------------------------------------------------
  // Tickets (Feature 1.5)
  // -------------------------------------------------------------------------

  Future<ArmTicketPage> listTickets({
    required String projectId,
    required ArmTicketQuery query,
  }) async {
    final target = _projectId(projectId);
    _pageSize(query.pageSize);
    _cursor(query.cursor);
    if (query.issueId != null) {
      _resourceId(query.issueId!, 'issueId');
    }
    final slice = await _repository.listTickets(
      projectId: target,
      query: query,
    );
    if (slice.tickets.length > query.pageSize ||
        (slice.hasMore && slice.tickets.isEmpty)) {
      throw _invalidRepositoryPage();
    }
    // Newest activity first. A ticket somebody replied to an hour ago is what
    // a person opening this page is looking for, not the one opened first.
    final tickets = slice.tickets.toList(growable: false)
      ..sort((ArmTicketRecord a, ArmTicketRecord b) {
        final int byUpdated = b.updatedAt.compareTo(a.updatedAt);
        return byUpdated != 0 ? byUpdated : a.ticketId.compareTo(b.ticketId);
      });
    return ArmTicketPage(
      projectId: target,
      tickets: tickets,
      nextPageToken: slice.hasMore
          ? encodeArmPageToken(
              ArmPageCursor(
                timestamp: tickets.last.updatedAt,
                documentId: tickets.last.ticketId,
              ),
            )
          : null,
    );
  }

  Future<ArmTicketRecord> getTicket({
    required String projectId,
    required String ticketId,
  }) async {
    final ticket = await _repository.getTicket(
      projectId: _projectId(projectId),
      ticketId: _resourceId(ticketId, 'ticketId'),
    );
    if (ticket == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM ticket was not found.',
      );
    }
    return ticket;
  }

  /// Opens a ticket.
  ///
  /// [openedBy] is who is recorded as having opened it — an operator's address
  /// when the Console opens one, `citadel_arm_client` when an error dialog
  /// does. The description becomes the first entry in the history rather than
  /// living only in a field, so a reader scrolling the conversation sees where
  /// it started instead of a thread that begins mid-sentence.
  Future<ArmTicketRecord> createTicket({
    required String projectId,
    required ArmTicketDraft draft,
    required String openedBy,
    ArmTicketAuthorKind openedAs = ArmTicketAuthorKind.operator,
  }) async {
    final target = _projectId(projectId);
    final DateTime now = _clock();
    final ArmTicketRecord ticket = ArmTicketRecord(
      ticketId: _generateId(),
      title: draft.title,
      description: draft.description,
      status: ArmTicketStatus.open,
      createdAt: now,
      updatedAt: now,
      createdBy: openedBy,
      reporterContact: draft.reporterContact,
      caseIds: draft.caseIds,
      issueId: draft.issueId,
      sessionId: draft.sessionId,
      allowlist: draft.allowlist,
      attachments: draft.attachments,
      updates: <ArmTicketUpdate>[
        ArmTicketUpdate(
          updateId: _generateId(),
          authorKind: openedAs,
          authorLabel: draft.reporterContact ?? openedBy,
          body: draft.description,
          createdAt: now,
          attachments: draft.attachments,
        ),
      ],
    );
    return _repository.writeTicket(projectId: target, ticket: ticket);
  }

  Future<ArmTicketRecord> updateTicketStatus({
    required String projectId,
    required String ticketId,
    required ArmTicketStatus status,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final String email = _operatorEmail(principal);
    final ArmTicketRecord current = await getTicket(
      projectId: target,
      ticketId: ticketId,
    );
    final DateTime now = _clock();
    return _repository.writeTicket(
      projectId: target,
      ticket: current.copyWith(
        status: status,
        statusUpdatedBy: email,
        statusUpdatedAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Appends one entry to a ticket's history.
  ///
  /// A closed ticket still accepts entries: a customer replying "it happened
  /// again" to something somebody closed is the most important message on the
  /// thread, and refusing it would send them to a second ticket that nothing
  /// links to the first.
  Future<ArmTicketRecord> appendTicketUpdate({
    required String projectId,
    required String ticketId,
    required ArmTicketUpdateDraft draft,
    required String authorLabel,
  }) async {
    final target = _projectId(projectId);
    final ArmTicketRecord current = await getTicket(
      projectId: target,
      ticketId: ticketId,
    );
    if (current.updates.length >= armMaximumTicketUpdates) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.failedPrecondition,
        message:
            'This ticket has reached the length a ticket can hold. Open a new '
            'one and link it, rather than losing what is here.',
      );
    }
    final DateTime now = _clock();
    return _repository.writeTicket(
      projectId: target,
      ticket: current.copyWith(
        updatedAt: now,
        updates: <ArmTicketUpdate>[
          ...current.updates,
          ArmTicketUpdate(
            updateId: _generateId(),
            authorKind: draft.authorKind,
            authorLabel: authorLabel,
            body: draft.body,
            createdAt: now,
            attachments: draft.attachments,
          ),
        ],
      ),
    );
  }

  /// Replaces who may read a ticket beyond anybody holding its link.
  ///
  /// Emptying the list makes the ticket public by link again, which is a
  /// widening and is why the whole list is sent: an operator removing the last
  /// address should be doing it deliberately rather than discovering it.
  Future<ArmTicketRecord> updateTicketAccess({
    required String projectId,
    required String ticketId,
    required List<String> allowlist,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    _operatorEmail(principal);
    final ArmTicketRecord current = await getTicket(
      projectId: target,
      ticketId: ticketId,
    );
    return _repository.writeTicket(
      projectId: target,
      ticket: current.copyWith(allowlist: allowlist, updatedAt: _clock()),
    );
  }

  Future<ArmAlertingConfiguration> readAlerting({
    required String projectId,
  }) async {
    return _repository.readAlerting(projectId: _projectId(projectId));
  }

  /// Adds or replaces one policy.
  ///
  /// Read-modify-write on the whole document, and the referential check is the
  /// point: a policy naming a channel that does not exist is a policy that
  /// silently notifies nobody, which looks identical to one that is working
  /// and finding nothing.
  Future<ArmAlertingConfiguration> writePolicy({
    required String projectId,
    required ArmPolicyRecord policy,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final current = await _repository.readAlerting(projectId: target);
    final Set<String> known = <String>{
      for (final ArmNotificationChannel channel in current.channels)
        channel.channelId,
    };
    for (final String channelId in policy.channelIds) {
      if (!known.contains(channelId)) {
        throw ArmServiceException(
          code: ArmServiceErrorCode.failedPrecondition,
          message: 'No notification channel named $channelId exists.',
        );
      }
    }
    final List<ArmPolicyRecord> policies = <ArmPolicyRecord>[
      for (final ArmPolicyRecord existing in current.policies)
        if (existing.policyId != policy.policyId) existing,
      policy,
    ]..sort((a, b) => a.policyId.compareTo(b.policyId));
    return _repository.writeAlerting(
      projectId: target,
      configuration: current.copyWith(policies: policies),
      updatedBy: _operatorEmail(principal),
    );
  }

  Future<ArmAlertingConfiguration> deletePolicy({
    required String projectId,
    required String policyId,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(policyId, 'policyId');
    final current = await _repository.readAlerting(projectId: target);
    if (!current.policies.any((ArmPolicyRecord p) => p.policyId == id)) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM policy was not found.',
      );
    }
    return _repository.writeAlerting(
      projectId: target,
      configuration: current.copyWith(
        policies: <ArmPolicyRecord>[
          for (final ArmPolicyRecord p in current.policies)
            if (p.policyId != id) p,
        ],
      ),
      updatedBy: _operatorEmail(principal),
    );
  }

  Future<ArmAlertingConfiguration> writeChannel({
    required String projectId,
    required ArmNotificationChannel channel,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final current = await _repository.readAlerting(projectId: target);
    final List<ArmNotificationChannel> channels = <ArmNotificationChannel>[
      for (final ArmNotificationChannel existing in current.channels)
        if (existing.channelId != channel.channelId) existing,
      channel,
    ]..sort((a, b) => a.channelId.compareTo(b.channelId));
    return _repository.writeAlerting(
      projectId: target,
      configuration: current.copyWith(channels: channels),
      updatedBy: _operatorEmail(principal),
    );
  }

  /// Removes a channel, and refuses while a policy still names it.
  ///
  /// Refused rather than cascaded: silently emptying a policy's channel list
  /// would leave a policy that looks configured and notifies nobody, which is
  /// the failure this whole surface exists to prevent.
  Future<ArmAlertingConfiguration> deleteChannel({
    required String projectId,
    required String channelId,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(channelId, 'channelId');
    final current = await _repository.readAlerting(projectId: target);
    if (!current.channels.any((ArmNotificationChannel c) => c.channelId == id)) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM notification channel was not found.',
      );
    }
    final List<String> users = <String>[
      for (final ArmPolicyRecord policy in current.policies)
        if (policy.channelIds.contains(id)) policy.policyId,
    ];
    if (users.isNotEmpty) {
      throw ArmServiceException(
        code: ArmServiceErrorCode.failedPrecondition,
        message:
            'This channel is named by ${users.join(', ')}. Remove it from '
            'those policies first.',
      );
    }
    return _repository.writeAlerting(
      projectId: target,
      configuration: current.copyWith(
        channels: <ArmNotificationChannel>[
          for (final ArmNotificationChannel c in current.channels)
            if (c.channelId != id) c,
        ],
      ),
      updatedBy: _operatorEmail(principal),
    );
  }

  /// Sends a real message on a channel and records what happened.
  ///
  /// The outcome is written back onto the channel, so the table can show when
  /// it was last proven to work. A channel that has never been tested and one
  /// that failed its last test are different facts.
  Future<ArmChannelTestOutcome> testChannel({
    required String projectId,
    required String channelId,
    required ArmAuthorizedPrincipal principal,
  }) async {
    final target = _projectId(projectId);
    final id = _resourceId(channelId, 'channelId');
    final current = await _repository.readAlerting(projectId: target);
    final ArmNotificationChannel? channel = current.channels
        .where((ArmNotificationChannel c) => c.channelId == id)
        .firstOrNull;
    if (channel == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.notFound,
        message: 'ARM notification channel was not found.',
      );
    }
    if (_sender == null) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.unavailable,
        message:
            'This deployment cannot send on a notification channel, so the '
            'channel was not tested.',
      );
    }
    if (channel.recipients.isEmpty) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.failedPrecondition,
        message: 'This channel names nobody, so a test would reach nobody.',
      );
    }
    final ArmChannelTestOutcome outcome = await _sender(
      channel,
      'Citadel ARM test message for $target. Nothing is wrong.',
    );
    await _repository.writeAlerting(
      projectId: target,
      configuration: current.copyWith(
        channels: <ArmNotificationChannel>[
          for (final ArmNotificationChannel c in current.channels)
            if (c.channelId == id)
              c.copyWith(
                lastTestedAt: outcome.testedAt,
                lastTestOutcome: outcome.delivered
                    ? 'delivered'
                    : (outcome.reason ?? 'not delivered'),
              )
            else
              c,
        ],
      ),
      updatedBy: _operatorEmail(principal),
    );
    return outcome;
  }

  void _validateIssueQuery(ArmIssueQuery query) {
    _pageSize(query.pageSize);
    _utcOrNull(query.since, 'since');
    _cursor(query.cursor);
  }

  void _validateCaseQuery(ArmCaseQuery query) {
    _pageSize(query.pageSize);
    _utcOrNull(query.since, 'since');
    _cursor(query.cursor);
    if (query.issueId != null) {
      _resourceId(query.issueId!, 'issueId');
    }
  }

  void _pageSize(int value) {
    if (value < 1 || value > armMaximumPageSize) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.invalidArgument,
        message: 'pageSize must be between 1 and 100.',
      );
    }
  }

  void _cursor(ArmPageCursor? value) {
    if (value == null) {
      return;
    }
    _utc(value.timestamp, 'pageToken.timestamp');
    _resourceId(value.documentId, 'pageToken.documentId');
  }

  String _projectId(String value) => _resourceId(value, 'projectId');

  String _resourceId(String value, String field) {
    try {
      return validateArmResourceId(value, fieldName: field);
    } on FormatException {
      throw ArmServiceException(
        code: ArmServiceErrorCode.invalidArgument,
        message: '$field is invalid.',
      );
    }
  }

  String _operatorEmail(ArmAuthorizedPrincipal principal) {
    final actorId = principal.actorId.trim();
    final email = principal.actorEmail?.trim().toLowerCase();
    if (actorId.isEmpty ||
        email == null ||
        email.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.permissionDenied,
        message: 'Authorized operator identity is incomplete.',
      );
    }
    return email;
  }

  ArmIssueRecord _validatedIssue(ArmIssueRecord value) {
    try {
      return decodeArmIssueRecord(encodeArmIssueRecord(value));
    } on FormatException {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an invalid issue record.',
      );
    }
  }

  ArmCaseRecord _validatedCase(ArmCaseRecord value) {
    try {
      return decodeArmCaseRecord(encodeArmCaseRecord(value));
    } on FormatException {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.internal,
        message: 'ARM repository returned an invalid case record.',
      );
    }
  }

  void _utcOrNull(DateTime? value, String field) {
    if (value != null) {
      _utc(value, field);
    }
  }

  void _utc(DateTime value, String field) {
    if (!value.isUtc) {
      throw ArmServiceException(
        code: ArmServiceErrorCode.invalidArgument,
        message: '$field must be UTC.',
      );
    }
  }

  int _compareIssues(ArmIssueRecord left, ArmIssueRecord right) {
    final timestamp = right.lastSeenAt.compareTo(left.lastSeenAt);
    return timestamp != 0 ? timestamp : right.issueId.compareTo(left.issueId);
  }

  int _compareCases(ArmCaseRecord left, ArmCaseRecord right) {
    final timestamp = right.createdAt.compareTo(left.createdAt);
    return timestamp != 0 ? timestamp : right.caseId.compareTo(left.caseId);
  }

  ArmServiceException _invalidRepositoryPage() => const ArmServiceException(
    code: ArmServiceErrorCode.internal,
    message: 'ARM repository returned an invalid page.',
  );
}
