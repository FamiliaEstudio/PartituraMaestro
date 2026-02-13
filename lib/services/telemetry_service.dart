import 'package:flutter/foundation.dart';

import '../config/build_config.dart';

class TelemetryService {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  Future<void> initialize() async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _recordError(details.exceptionAsString(), details.stack);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _recordError(error.toString(), stack);
      return true;
    };
  }

  void _recordError(String message, StackTrace? stack) {
    if (BuildConfig.crashlyticsEnabled) {
      // Placeholder para integração opcional com Crashlytics/Sentry.
      debugPrint('[telemetry][remote] $message\n$stack');
      return;
    }

    if (kDebugMode) {
      debugPrint('[telemetry][local] $message\n$stack');
    }
  }
}
