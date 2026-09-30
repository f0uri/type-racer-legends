import 'dart:convert';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import '../data/remote/firebase_boot.dart';

/// Values controlled remotely (Firebase Remote Config). Empty / null values mean "use the bundled defaults".
class RemoteSettings {
  final Set<String> killFeatures;
  final Set<String> killItems;
  final int? minSupportedVersion;
  final int? dailyCoinCap;
  final int? interstitialEveryN;
  final bool? interstitialEnabled;
  final int? rewardedDailyLimit;
  final String? maintenanceMessage;
  const RemoteSettings({this.killFeatures = const {}, this.killItems = const {}, this.minSupportedVersion, this.dailyCoinCap, this.interstitialEveryN, this.interstitialEnabled, this.rewardedDailyLimit, this.maintenanceMessage});

  static const empty = RemoteSettings();

  /// Economy overrides in the shape expected by `ContentDb.withOverrides`.
  Map<String, Map<String, dynamic>> get economyPatch => {
        if (dailyCoinCap != null) 'race': {'dailyCoinCap': dailyCoinCap},
        'ads': {
          if (interstitialEveryN != null) 'interstitialEveryNRaces': interstitialEveryN,
          if (interstitialEnabled != null) 'interstitialEnabled': interstitialEnabled,
          if (rewardedDailyLimit != null) 'rewardedDailyLimit': rewardedDailyLimit,
        },
      }..removeWhere((k, v) => v.isEmpty);

  static Set<String> _csv(String? s) => (s ?? '').split(RegExp(r'[,\s]+')).where((e) => e.isNotEmpty).toSet();

  /// Parses raw Remote Config strings (also used by tests).
  factory RemoteSettings.fromMap(Map<String, String> m) {
    int? i(String k) => int.tryParse(m[k] ?? '');
    bool? b(String k) => m[k] == 'true' ? true : (m[k] == 'false' ? false : null);
    var kf = _csv(m['kill_features']), ki = _csv(m['kill_items']);
    final json = m['kill_switch'];
    if (json != null && json.trim().startsWith('{')) {
      try {
        final o = jsonDecode(json) as Map;
        kf = {...kf, ...((o['features'] as List?) ?? const []).map((e) => e.toString())};
        ki = {...ki, ...((o['items'] as List?) ?? const []).map((e) => e.toString())};
      } catch (_) {}
    }
    final msg = m['maintenance_message'];
    return RemoteSettings(
      killFeatures: kf,
      killItems: ki,
      minSupportedVersion: i('min_supported_version'),
      dailyCoinCap: i('daily_coin_cap'),
      interstitialEveryN: i('interstitial_every_n'),
      interstitialEnabled: b('interstitial_enabled'),
      rewardedDailyLimit: i('rewarded_daily_limit'),
      maintenanceMessage: msg == null || msg.isEmpty ? null : msg,
    );
  }

  static const keys = ['kill_features', 'kill_items', 'kill_switch', 'min_supported_version', 'daily_coin_cap', 'interstitial_every_n', 'interstitial_enabled', 'rewarded_daily_limit', 'maintenance_message'];
}

class RemoteSettingsService {
  /// Fetches (at most hourly) and returns the current remote values; never throws.
  Future<RemoteSettings> fetch() async {
    if (!FirebaseBoot.available) return RemoteSettings.empty;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(fetchTimeout: const Duration(seconds: 10), minimumFetchInterval: kDebugMode ? Duration.zero : const Duration(hours: 1)));
      await rc.setDefaults({for (final k in RemoteSettings.keys) k: ''});
      await rc.fetchAndActivate();
      return RemoteSettings.fromMap({for (final k in RemoteSettings.keys) k: rc.getString(k)});
    } catch (e) {
      debugPrint('remote config unavailable: $e');
      return RemoteSettings.empty;
    }
  }
}
