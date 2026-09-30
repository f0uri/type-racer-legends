import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase is optional: without google-services.json the game runs in guest/offline mode.
class FirebaseBoot {
  static bool available = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      available = true;
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
      final old = FlutterError.onError;
      FlutterError.onError = (details) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        old?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      available = false;
      debugPrint('Firebase unavailable, running offline/guest: $e');
    }
  }

  static void log(String msg, [Object? e, StackTrace? st]) {
    debugPrint('[log] $msg ${e ?? ''}');
    if (available && e != null) {
      try {
        FirebaseCrashlytics.instance.recordError(e, st, reason: msg);
      } catch (_) {}
    }
  }
}
