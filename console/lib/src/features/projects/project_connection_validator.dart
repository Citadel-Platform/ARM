import 'package:arm_console/src/features/projects/domain/project_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

abstract interface class ProjectConnectionValidator {
  Future<ProjectValidationResult> validate(ProjectDraft draft);
}

class InMemoryProjectConnectionValidator implements ProjectConnectionValidator {
  const InMemoryProjectConnectionValidator();

  @override
  Future<ProjectValidationResult> validate(ProjectDraft draft) async {
    final List<String> errors = draft.validationErrors();
    if (errors.isNotEmpty) {
      return ProjectValidationResult.fromFormErrors(errors);
    }

    final DateTime checkedAt = DateTime.now();
    return ProjectValidationResult(
      status: ProjectConnectionStatus.warning,
      summary:
          'Local preview mode skipped remote Firebase validation. Save is still available for UI iteration.',
      checkedAt: checkedAt,
      checks: const <ProjectValidationCheck>[
        ProjectValidationCheck(
          label: 'Local preview',
          status: ProjectValidationCheckStatus.warning,
          message:
              'Remote Firestore and Storage probes only run when the console Firebase bootstrap is active.',
        ),
      ],
    );
  }
}

class FirebaseProjectConnectionValidator implements ProjectConnectionValidator {
  const FirebaseProjectConnectionValidator();

  @override
  Future<ProjectValidationResult> validate(ProjectDraft draft) async {
    final List<String> errors = draft.validationErrors();
    if (errors.isNotEmpty) {
      return ProjectValidationResult.fromFormErrors(errors);
    }

    final DateTime checkedAt = DateTime.now();
    final List<ProjectValidationCheck> checks = <ProjectValidationCheck>[
      const ProjectValidationCheck(
        label: 'Configuration completeness',
        status: ProjectValidationCheckStatus.success,
        message: 'Required Firebase client fields are present.',
      ),
    ];

    final String appName =
        'arm-console-validation-${draft.id}-${checkedAt.microsecondsSinceEpoch}';
    FirebaseApp? validationApp;

    try {
      validationApp = await Firebase.initializeApp(
        name: appName,
        options: FirebaseOptions(
          apiKey: draft.firebaseConfig.apiKey,
          appId: draft.firebaseConfig.appId,
          messagingSenderId: draft.firebaseConfig.messagingSenderId,
          projectId: draft.firebaseConfig.projectId,
          authDomain: draft.firebaseConfig.authDomain,
          databaseURL: draft.firebaseConfig.databaseUrl,
          storageBucket: draft.firebaseConfig.storageBucket,
          measurementId: draft.firebaseConfig.measurementId,
          androidClientId: draft.firebaseConfig.androidClientId,
          iosClientId: draft.firebaseConfig.iosClientId,
          iosBundleId: draft.firebaseConfig.iosBundleId,
        ),
      );
      checks.add(
        const ProjectValidationCheck(
          label: 'Firebase app bootstrap',
          status: ProjectValidationCheckStatus.success,
          message: 'Secondary Firebase app initialized successfully.',
        ),
      );

      await FirebaseFirestore.instanceFor(app: validationApp)
          .collection('__arm_console_probe__')
          .limit(1)
          .get();
      checks.add(
        const ProjectValidationCheck(
          label: 'Firestore read probe',
          status: ProjectValidationCheckStatus.success,
          message: 'Firestore accepted a read-only probe request.',
        ),
      );

      final String? storageBucket = draft.firebaseConfig.storageBucket;
      if (storageBucket == null || storageBucket.trim().isEmpty) {
        checks.add(
          const ProjectValidationCheck(
            label: 'Storage read probe',
            status: ProjectValidationCheckStatus.warning,
            message:
                'No storage bucket was supplied, so screenshot and asset reads could not be checked yet.',
          ),
        );
      } else {
        final FirebaseStorage storage = FirebaseStorage.instanceFor(
          app: validationApp,
          bucket: _bucketUri(storageBucket),
        );
        await storage.ref().list(const ListOptions(maxResults: 1));
        checks.add(
          const ProjectValidationCheck(
            label: 'Storage read probe',
            status: ProjectValidationCheckStatus.success,
            message: 'Cloud Storage accepted a read-only list request.',
          ),
        );
      }
    } on FirebaseException catch (error) {
      checks.add(
        ProjectValidationCheck(
          label: 'Remote validation',
          status: ProjectValidationCheckStatus.failure,
          message: _firebaseErrorMessage(error),
        ),
      );
    } finally {
      if (validationApp != null) {
        await validationApp.delete();
      }
    }

    final bool hasFailure = checks.any(
      (ProjectValidationCheck check) =>
          check.status == ProjectValidationCheckStatus.failure,
    );
    final bool hasWarning = checks.any(
      (ProjectValidationCheck check) =>
          check.status == ProjectValidationCheckStatus.warning,
    );

    return ProjectValidationResult(
      status: hasFailure
          ? ProjectConnectionStatus.failed
          : hasWarning
          ? ProjectConnectionStatus.warning
          : ProjectConnectionStatus.healthy,
      summary: hasFailure
          ? 'Connection validation failed. Check the failed probe details before saving monitored-project access.'
          : hasWarning
          ? 'Connection validation completed with warnings. Firestore is reachable, but some optional checks still need attention.'
          : 'Connection validation passed for the monitored project configuration.',
      checkedAt: checkedAt,
      checks: checks,
    );
  }

  String _firebaseErrorMessage(FirebaseException error) {
    final String baseMessage = switch (error.code) {
      'permission-denied' =>
        'The configured Firebase resources rejected read access. Confirm this account can read ARM telemetry and evidence.',
      'storage/unauthorized' =>
        'Cloud Storage rejected the read probe. Confirm screenshot and asset reads are allowed for this configuration.',
      _ =>
        error.message ?? 'Firebase rejected the connection probe.',
    };
    return '${error.code}: $baseMessage';
  }

  String _bucketUri(String bucket) {
    return bucket.startsWith('gs://') ? bucket : 'gs://$bucket';
  }
}
