import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseArmSink implements ArmSink {
  FirebaseArmSink({
    required FirebaseFirestore firestore,
    FirebaseStorage? storage,
    this.issuesCollection = 'armIssues',
    this.casesCollection = 'armCases',
    this.screenshotPrefix = 'arm/cases',
  }) : _firestore = firestore,
       _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseStorage? _storage;
  final String issuesCollection;
  final String casesCollection;
  final String screenshotPrefix;

  @override
  Future<ArmCaptureResult> record(ArmCaptureRequest request) async {
    final issueId = buildArmIssueId(request.fingerprint);
    final caseId = buildArmCaseId();
    final issueRef = _firestore.collection(issuesCollection).doc(issueId);
    final caseRef = _firestore.collection(casesCollection).doc(caseId);
    final screenshotPath = request.screenshot == null
        ? null
        : '$screenshotPrefix/$issueId/$caseId/${request.screenshot!.name}.${request.screenshot!.extension}';

    await _firestore.runTransaction((transaction) async {
      final issueSnapshot = await transaction.get(issueRef);
      final now = FieldValue.serverTimestamp();
      final existingIssue = issueSnapshot.data();
      final existingCount =
          (existingIssue == null ? null : existingIssue['caseCount'] as num?)
              ?.toInt() ??
          0;
      final firstSeenAt = issueSnapshot.exists
          ? (existingIssue == null ? null : existingIssue['firstSeenAt']) ?? now
          : now;
      final firstCaseId = issueSnapshot.exists
          ? ((existingIssue == null ? null : existingIssue['firstCaseId'])
                    as String?) ??
                caseId
          : caseId;

      // Merged so the capture path only writes capture-owned fields. A plain
      // set replaces the document, which would erase operator triage such as
      // `status` and `statusUpdatedBy` each time the issue recurred.
      transaction.set(
        issueRef,
        buildArmIssueDocumentMap(
          issueId: issueId,
          caseId: caseId,
          request: request,
          firstSeenAt: firstSeenAt,
          lastSeenAt: now,
          firstCaseId: firstCaseId,
          caseCount: existingCount + 1,
        ),
        SetOptions(merge: true),
      );

      transaction.set(
        caseRef,
        buildArmCaseDocumentMap(
          caseId: caseId,
          issueId: issueId,
          request: request,
          createdAt: now,
          screenshotPath: screenshotPath,
        ),
      );
    });

    if (request.screenshot != null &&
        _storage != null &&
        screenshotPath != null) {
      try {
        final ref = _storage.ref(screenshotPath);
        await ref.putData(
          request.screenshot!.bytes,
          SettableMetadata(contentType: request.screenshot!.contentType),
        );
      } catch (_) {}
    }

    return ArmCaptureResult(
      caseId: caseId,
      issueId: issueId,
      fingerprint: request.fingerprint,
      severity: request.severity,
      caseIdExposed: request.severity.exposesCaseId,
    );
  }
}

/// Opens a ticket in the same database the case logs are written to.
///
/// The same path the SDK already writes evidence on, and for the same reason:
/// the application is signed in to its own Firebase project, and a ticket is
/// the client's conversation with their own customer. Nothing new is exposed
/// to the device — it writes a ticket beside the case log it is about.
class FirebaseArmTicketSink implements ArmTicketSink {
  FirebaseArmTicketSink({
    required FirebaseFirestore firestore,
    this.ticketsCollection = 'armTickets',
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;
  final String ticketsCollection;

  @override
  Future<String> open(ArmTicketRequest request) async {
    final String ticketId = buildArmTicketId();
    await _firestore
        .collection(ticketsCollection)
        .doc(ticketId)
        .set(
          buildArmTicketDocumentMap(
            ticketId: ticketId,
            updateId: '${ticketId}_1',
            request: request,
            createdAt: DateTime.now().toUtc(),
            indexedUpdatedAt: FieldValue.serverTimestamp(),
          ),
        );
    return ticketId;
  }
}
