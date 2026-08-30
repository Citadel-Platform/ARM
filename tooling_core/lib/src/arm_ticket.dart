import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';

/// What an end user is asking about, on their way out of an error dialog.
///
/// Deliberately small. Everything technical is already captured on the case
/// log this points at, and asking a person who has just hit a bug to describe
/// a stack trace is asking them to do the SDK's job.
@immutable
class ArmTicketRequest {
  const ArmTicketRequest({
    required this.title,
    required this.description,
    this.contact,
    this.caseId,
    this.issueId,
    this.sessionId,
  });

  final String title;

  /// Markdown, as the person wrote it. Rendered by whoever reads it, never
  /// pre-rendered here.
  final String description;

  /// How to reach them back — an address or a number, as they typed it.
  ///
  /// Never verified by the client, and the platform does not treat it as
  /// though it were: it is what pegs the ticket to a person, not a claim about
  /// who they are.
  final String? contact;

  /// The evidence this ticket is about, when it was opened from an error
  /// dialog. Absent when somebody opened it from a menu with nothing failing.
  final String? caseId;
  final String? issueId;
  final String? sessionId;
}

/// Opens a ticket from the client's own device.
///
/// A seam rather than a client, so an application can decide where a ticket
/// goes — and so an app with no ticket store configured refuses visibly rather
/// than showing a person a form that discards what they wrote.
abstract interface class ArmTicketSink {
  /// Returns the id of the ticket that was opened.
  Future<String> open(ArmTicketRequest request);
}

String buildArmTicketId() {
  final Random random = Random();
  final int now = DateTime.now().toUtc().microsecondsSinceEpoch;
  final String suffix = (random.nextInt(1 << 32) ^ now)
      .toUnsigned(32)
      .toRadixString(16)
      .padLeft(8, '0');
  return 'ticket_${now.toRadixString(16)}$suffix';
}

/// The stored shape of a ticket, as the ARM service reads it back.
///
/// The whole ticket is one JSON payload in a single field, exactly as the
/// service writes it: the history is the document, and a partial write of a
/// history is a history with a hole in it. `status` and `updatedAt` are
/// duplicated out of the payload so a listing can be ordered and filtered
/// without decoding every ticket in the project.
///
/// The timestamps inside the payload are the device's own clock, which is the
/// only clock a client has. [indexedUpdatedAt] is what the server stamps, and
/// is what ordering uses.
Map<String, dynamic> buildArmTicketDocumentMap({
  required String ticketId,
  required String updateId,
  required ArmTicketRequest request,
  required DateTime createdAt,
  required Object indexedUpdatedAt,
  String createdBy = 'citadel_arm_client',
}) {
  final String timestamp = createdAt.toUtc().toIso8601String();
  final Map<String, Object?> payload = <String, Object?>{
    'ticketId': ticketId,
    'title': request.title,
    'description': request.description,
    'status': 'open',
    'createdAt': timestamp,
    'updatedAt': timestamp,
    'createdBy': createdBy,
    if (request.contact != null && request.contact!.trim().isNotEmpty)
      'reporterContact': request.contact!.trim(),
    'caseIds': <String>[
      if (request.caseId != null && request.caseId!.isNotEmpty) request.caseId!,
    ],
    if (request.issueId != null && request.issueId!.isNotEmpty)
      'issueId': request.issueId,
    if (request.sessionId != null && request.sessionId!.isNotEmpty)
      'sessionId': request.sessionId,
    // Nobody named, which is to say readable by anybody holding the link —
    // and a public link is served without the evidence coordinates above.
    'allowlist': <String>[],
    'updates': <Object?>[
      <String, Object?>{
        'updateId': updateId,
        'authorKind': 'endUser',
        'authorLabel': request.contact?.trim().isNotEmpty == true
            ? request.contact!.trim()
            : 'Customer',
        'body': request.description,
        'createdAt': timestamp,
        'attachments': <Object?>[],
      },
    ],
    'attachments': <Object?>[],
  };
  return <String, dynamic>{
    'ticketId': ticketId,
    'ticket': jsonEncode(payload),
    'status': 'open',
    'updatedAt': indexedUpdatedAt,
  };
}
