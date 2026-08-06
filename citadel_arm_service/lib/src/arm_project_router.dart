import 'package:googleapis/firestore/v1.dart' as firestore_api;

import 'arm_private_service.dart';
import 'arm_service_models.dart';

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

  /// The customer Firestore database, `(default)` unless overridden.
  final String databaseId;

  String get documentsRoot =>
      'projects/$customerProjectId/databases/$databaseId/documents';
}

/// Resolves a Citadel project identifier to its customer evidence boundary.
abstract interface class ArmProjectRouter {
  Future<ArmProjectTarget> resolve(String projectId);
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
  final Map<String, _CachedTarget> _cache = <String, _CachedTarget>{};

  @override
  Future<ArmProjectTarget> resolve(String projectId) async {
    final cached = _cache[projectId];
    final now = _clock();
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.target;
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
    if (!_armEnabled(fields['offeringScope'])) {
      throw const ArmServiceException(
        code: ArmServiceErrorCode.failedPrecondition,
        message: 'ARM is not enabled for this project.',
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
      databaseId: _string(fields['firestoreDatabaseId']) ?? '(default)',
    );
    _cache[projectId] = _CachedTarget(
      target: target,
      expiresAt: now.add(cacheDuration),
    );
    return target;
  }

  bool _armEnabled(firestore_api.Value? offeringScope) {
    final arm = offeringScope?.mapValue?.fields?['arm']?.mapValue?.fields;
    return arm?['enabled']?.booleanValue ?? false;
  }

  String? _string(firestore_api.Value? value) {
    final text = value?.stringValue?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

bool _isGoogleProjectId(String value) =>
    RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(value);

class _CachedTarget {
  const _CachedTarget({required this.target, required this.expiresAt});

  final ArmProjectTarget target;
  final DateTime expiresAt;
}
