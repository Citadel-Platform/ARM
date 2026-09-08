import 'package:googleapis/firestore/v1.dart' as firestore_api;

import 'arm_private_service.dart';
import 'arm_service_models.dart';

/// The database ARM reads a client's evidence out of.
///
/// One database per Citadel product in the client's own project, decided
/// 02/09/26. ARM's records used to live in the client's `(default)` database
/// beside their own business collections; a database of its own is what lets
/// the evidence runtime's IAM grant name exactly what it may read, because
/// Firestore can scope a grant to a database and cannot scope one to a
/// collection.
const String armDatabaseId = 'citadel-arm';

/// The database Helpdesk tickets live in.
///
/// Tickets were written to [armDatabaseId] until 08/09/26 because the Helpdesk
/// used to be ARM's. It became Manifold's on 07/09/26 and the storage did not
/// move with it, which left a client who bought Manifold without ARM with a
/// Helpdesk and no database to put a ticket in — `citadel-arm` is created when
/// ARM is provisioned and they had not bought ARM. The database follows the
/// product that owns the records. See DECISIONS.md 08/09/26.
const String manifoldDatabaseId = 'citadel-manifold';

/// The customer boundary a Citadel project's ARM evidence lives in.
class ArmProjectTarget {
  const ArmProjectTarget({
    required this.projectId,
    required this.customerProjectId,
    required this.databaseId,
  });

  /// The Citadel registry project identifier used on the wire.
  final String projectId;

  /// The customer Google Cloud project that owns the ARM evidence.
  final String customerProjectId;

  /// The customer Firestore database this target reads and writes.
  ///
  /// [armDatabaseId] for evidence, [manifoldDatabaseId] for Helpdesk tickets.
  /// Carried on the target rather than read from a constant at each use, so
  /// the documents root is composed from one value a test can vary.
  final String databaseId;

  String get documentsRoot =>
      'projects/$customerProjectId/databases/$databaseId/documents';
}

/// Which offering a caller is acting for when it asks to be routed.
///
/// The store this service reads is shared by two products. ARM's issues, cases
/// and alerting are evidence an SDK captured, and they exist because the client
/// bought ARM. Helpdesk tickets are a conversation with a person, they are
/// Manifold's since 07/09/26, and a ticket is opened by somebody typing what is
/// wrong — it needs no telemetry and so it needs no ARM.
///
/// Named on the call rather than inferred, because the two are indistinguishable
/// once you are inside the repository and getting it wrong is silent: a client
/// with Manifold and no ARM got a 412 on every Helpdesk load.
enum ArmRoutedOffering {
  /// Issues, cases and alerting. Requires `arm` enabled.
  evidence('ARM', 'arm', armDatabaseId),

  /// Helpdesk tickets. Requires `manifold` enabled.
  helpdesk('Manifold', 'manifold', manifoldDatabaseId);

  const ArmRoutedOffering(this.label, this.offeringKey, this.databaseId);

  /// How the offering is named to an operator in a refusal.
  final String label;

  /// The key under `offeringScope` in the registry entry.
  final String offeringKey;

  /// The customer Firestore database this offering's records live in.
  ///
  /// The two offerings this service answers for are stored apart because they
  /// are provisioned apart: each database is created only when its product is
  /// enabled, and a grant can name a database and cannot name a collection.
  final String databaseId;
}

/// Resolves a Citadel project identifier to its customer evidence boundary.
abstract interface class ArmProjectRouter {
  Future<ArmProjectTarget> resolve(
    String projectId, {
    ArmRoutedOffering offering,
  });
}

/// Reads the Citadel registry (`platform_projects`) to route ARM reads, so the
/// runtime never carries a hardcoded customer project.
final class FirestoreArmProjectRouter implements ArmProjectRouter {
  FirestoreArmProjectRouter({
    required firestore_api.FirestoreApi firestoreApi,
    required String registryProjectId,
    this.registryDatabaseId = '(default)',
    this.cacheDuration = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _firestoreApi = firestoreApi,
       _registryProjectId = registryProjectId,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final firestore_api.FirestoreApi _firestoreApi;
  final String _registryProjectId;
  final String registryDatabaseId;
  final Duration cacheDuration;
  final DateTime Function() _clock;
  final Map<String, _CachedRoute> _cache = <String, _CachedRoute>{};

  @override
  Future<ArmProjectTarget> resolve(
    String projectId, {
    ArmRoutedOffering offering = ArmRoutedOffering.evidence,
  }) async {
    final cached = _cache[projectId];
    final now = _clock();
    if (cached != null &&
        cached.expiresAt.isAfter(now) &&
        cached.offerings.contains(offering)) {
      // Rebuilt for the offering asked about rather than replayed, because the
      // database is the offering's and only the customer boundary is shared.
      // Caching a whole target would let a Helpdesk call warm the entry and an
      // evidence call then be served tickets' database.
      return ArmProjectTarget(
        projectId: projectId,
        customerProjectId: cached.customerProjectId,
        databaseId: offering.databaseId,
      );
    }

    final name =
        'projects/$_registryProjectId/databases/$registryDatabaseId/documents'
        '/platform_projects/$projectId';
    final firestore_api.Document document;
    try {
      document = await _firestoreApi.projects.databases.documents.get(name);
    } on firestore_api.DetailedApiRequestError catch (error) {
      if (error.status == 404) {
        throw const ArmServiceException(
          code: ArmServiceErrorCode.notFound,
          message: 'The project is not registered with Citadel.',
        );
      }
      throw const ArmServiceException(
        code: ArmServiceErrorCode.unavailable,
        message: 'The Citadel project registry is unavailable.',
        retryable: true,
      );
    }

    final fields = document.fields ?? const <String, firestore_api.Value>{};
    if (_string(fields['status']) != 'active') {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.failedPrecondition,
        message: 'The project is not active in the Citadel registry.',
      );
    }
    if (!_offeringEnabled(fields['offeringScope'], offering)) {
      throw ArmServiceException(
        code: ArmServiceErrorCode.failedPrecondition,
        message: '${offering.label} is not enabled for this project.',
      );
    }

    final customerProjectId =
        _string(fields['firebaseProjectId']) ?? _string(fields['gcpProjectId']);
    if (customerProjectId == null || !_isGoogleProjectId(customerProjectId)) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.failedPrecondition,
        message: 'The project has no valid customer Firebase project ID.',
      );
    }

    final target = ArmProjectTarget(
      projectId: projectId,
      customerProjectId: customerProjectId,
      // The database the offering being routed for owns.
      //
      // Records used to be written into whatever default database the client
      // already had, mixed in beside their own business collections, where
      // they could collide with a collection the client names — and where no
      // IAM grant could separate Citadel's reach from the client's own data,
      // because Firestore can scope a grant to a database and cannot scope one
      // to a collection. See DECISIONS.md 02/09/26.
      //
      // Which database is the offering's own, not this service's: evidence in
      // `citadel-arm`, tickets in `citadel-manifold`. Both are created only
      // when their product is provisioned, so reading tickets out of ARM's
      // database left a Manifold-only client with nowhere to put one.
      //
      // Not overridable. A per-project override existed while clients onboarded
      // before the split still had records in `(default)`; every client is
      // onboarded into the new topology now, so an override could only point
      // this service at a database that is not the one it writes.
      databaseId: offering.databaseId,
    );
    // Cached against the offerings actually checked on this read, not against
    // the project alone. One entry keyed by project would let a Helpdesk call
    // warm the cache and an evidence call then be served from it without ARM
    // ever having been required — the enablement check silently skipped for
    // five minutes at a time.
    final Set<ArmRoutedOffering> offerings = <ArmRoutedOffering>{
      offering,
      for (final ArmRoutedOffering other in ArmRoutedOffering.values)
        if (other != offering && _offeringEnabled(fields['offeringScope'], other))
          other,
    };
    _cache[projectId] = _CachedRoute(
      customerProjectId: customerProjectId,
      expiresAt: now.add(cacheDuration),
      offerings: offerings,
    );
    return target;
  }

  bool _offeringEnabled(
    firestore_api.Value? offeringScope,
    ArmRoutedOffering offering,
  ) {
    final scope = offeringScope
        ?.mapValue
        ?.fields?[offering.offeringKey]
        ?.mapValue
        ?.fields;
    return scope?['enabled']?.booleanValue ?? false;
  }

  String? _string(firestore_api.Value? value) {
    final text = value?.stringValue?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

bool _isGoogleProjectId(String value) =>
    RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(value);

class _CachedRoute {
  const _CachedRoute({
    required this.customerProjectId,
    required this.expiresAt,
    required this.offerings,
  });

  /// The customer project, which is the only part of a route the two offerings
  /// share. The database is derived per call from the offering asked about.
  final String customerProjectId;
  final DateTime expiresAt;

  /// The offerings this project was observed to have enabled when the entry was
  /// written. A call for an offering outside this set re-reads the registry.
  final Set<ArmRoutedOffering> offerings;
}
