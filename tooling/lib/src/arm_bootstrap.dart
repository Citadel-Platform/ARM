import 'dart:async';

import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:flutter/foundation.dart';

import 'arm_client.dart';

class ArmBootstrap {
  const ArmBootstrap._();

  static Future<void> runGuarded({
    required ArmClient client,
    required Future<void> Function() body,
  }) async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(
        _reportSafely(
          client,
          error: details.exception,
          stackTrace: details.stack ?? StackTrace.current,
          operation: 'framework_error',
        ),
      );
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(
        _reportSafely(
          client,
          error: error,
          stackTrace: stackTrace,
          operation: 'platform_dispatcher',
        ),
      );
      return true;
    };

    await runZonedGuarded(body, (error, stackTrace) {
      unawaited(
        _reportSafely(
          client,
          error: error,
          stackTrace: stackTrace,
          operation: 'zone_uncaught',
        ),
      );
    }, zoneSpecification: client.createZoneSpecification());
  }

  static Future<void> _reportSafely(
    ArmClient client, {
    required Object error,
    required StackTrace stackTrace,
    required String operation,
  }) async {
    try {
      await client.captureException(
        error: error,
        stackTrace: stackTrace,
        feature: 'flutter',
        operation: operation,
        severity: ArmSeverity.serious,
        category: 'runtime',
      );
    } catch (_) {}
  }
}
