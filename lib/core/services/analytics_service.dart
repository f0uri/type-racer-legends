import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import '../../data/remote/firebase_boot.dart';

/// Thin, crash-safe wrapper around Firebase Analytics. Does nothing when Firebase is not configured.
class AnalyticsService {
  /// Events recorded in this session (also used by tests).
  final List<String> recent = [];

  Future<void> log(String name, [Map<String, Object>? params]) async {
    recent.add(name);
    if (recent.length > 50) recent.removeAt(0);
    if (!FirebaseBoot.available) return;
    try {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('analytics $name failed: $e');
    }
  }

  Future<void> setUserProps({String? country, int? level, String? rank}) async {
    if (!FirebaseBoot.available) return;
    try {
      if (country != null && country.isNotEmpty) await FirebaseAnalytics.instance.setUserProperty(name: 'country', value: country);
      if (level != null) await FirebaseAnalytics.instance.setUserProperty(name: 'level', value: '$level');
      if (rank != null) await FirebaseAnalytics.instance.setUserProperty(name: 'rank', value: rank);
    } catch (_) {}
  }
}
