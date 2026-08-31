import 'arm_service_models.dart';

/// Whether somebody may read a ticket, and on what basis.
///
/// Three outcomes rather than a boolean, because "not yet" and "no" are
/// different answers to the reader and to whoever has to build the screen: one
/// asks them to prove who they are, the other tells them this is not theirs.
enum ArmTicketAccessOutcome { granted, verificationRequired, denied }

/// The decision, with the sentence a reader is shown.
typedef ArmTicketAccessDecision = ({
  ArmTicketAccessOutcome outcome,
  String reason,
});

/// Who may read this ticket, given who is asking.
///
/// The rule the 30/08/26 review settled: a ticket with no allowlist is public
/// by link and carries the conversation without the evidence it points at; a
/// ticket with an allowlist is readable only by an address on it that has been
/// *verified*. An unverified address typed into a box is not an access
/// control — anybody who can guess a colleague's address would hold the
/// ticket, and a support ticket carries a stack trace, a session id and a
/// customer's own words.
///
/// [viewerVerified] is what separates the two: it means something outside this
/// function proved the address, never that somebody typed it.
ArmTicketAccessDecision armTicketAccess({
  required ArmTicketRecord ticket,
  String? viewerEmail,
  bool viewerVerified = false,
}) {
  if (ticket.isPublicByLink) {
    return (
      outcome: ArmTicketAccessOutcome.granted,
      reason: 'Anybody with the link may read this ticket.',
    );
  }
  final String? address = viewerEmail?.trim().toLowerCase();
  if (address == null || address.isEmpty || !viewerVerified) {
    return (
      outcome: ArmTicketAccessOutcome.verificationRequired,
      reason:
          'This ticket is restricted to named addresses, so reading it means '
          'proving the address is yours.',
    );
  }
  if (!ticket.allowlist.contains(address)) {
    return (
      outcome: ArmTicketAccessOutcome.denied,
      // Deliberately does not say who is on the list. The list is a set of
      // people's addresses, and confirming or denying one of them is the
      // question this refusal exists to avoid answering.
      reason: 'This ticket is not shared with that address.',
    );
  }
  return (
    outcome: ArmTicketAccessOutcome.granted,
    reason: 'This address is named on the ticket.',
  );
}

/// A ticket as somebody holding only its link may read it.
///
/// The conversation, and nothing that points at evidence: the case logs, the
/// fingerprint and the session are removed, because a public URL that resolves
/// to a stack trace is the first support ticket becoming the first leak. The
/// reporter's own address goes too — a public link should not publish the
/// contact details of the person who wrote in — and an entry they wrote is
/// attributed to `Customer` rather than to their address.
///
/// Attachments stay, because a customer who sent a screenshot should see that
/// it arrived, but their storage paths do not: where a file sits in the
/// project's own storage is Citadel's layout, and a reader needs only the id
/// to ask for one.
ArmTicketRecord armPublicTicketView(ArmTicketRecord ticket) {
  return ticket.copyWith(
    caseIds: const <String>[],
    issueId: null,
    sessionId: null,
    reporterContact: null,
    createdBy: ticket.createdBy.contains('@') ? 'Citadel' : ticket.createdBy,
    attachments: _publicAttachments(ticket.attachments),
    updates: <ArmTicketUpdate>[
      for (final ArmTicketUpdate update in ticket.updates)
        update.copyWith(
          authorLabel: update.authorKind == ArmTicketAuthorKind.endUser
              ? 'Customer'
              : update.authorLabel,
          attachments: _publicAttachments(update.attachments),
        ),
    ],
  );
}

List<ArmTicketAttachment> _publicAttachments(
  List<ArmTicketAttachment> attachments,
) => <ArmTicketAttachment>[
  for (final ArmTicketAttachment attachment in attachments)
    attachment.copyWith(storagePath: null),
];
