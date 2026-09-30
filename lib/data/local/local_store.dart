import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/config/app_config.dart';
import '../../core/util/misc.dart';
import '../models/profile.dart';

/// Offline-first local storage on top of Hive (all values are JSON strings / primitives).
class LocalStore {
  LocalStore._(this.meta, this.profileBox, this.content, this.ghosts);
  final Box meta;
  final Box profileBox;
  final Box content;
  final Box ghosts;

  static const currentSchema = 1;

  static Future<LocalStore> init() async {
    await Hive.initFlutter();
    final meta = await Hive.openBox('meta');
    final profile = await Hive.openBox('profile');
    final content = await Hive.openBox('content');
    final ghosts = await Hive.openBox('ghosts');
    final s = LocalStore._(meta, profile, content, ghosts);
    await s._migrate();
    return s;
  }

  /// In-memory-like store for tests (uses a temporary directory).
  @visibleForTesting
  static Future<LocalStore> forTest(String path) async {
    Hive.init(path);
    final meta = await Hive.openBox('meta');
    final profile = await Hive.openBox('profile');
    final content = await Hive.openBox('content');
    final ghosts = await Hive.openBox('ghosts');
    return LocalStore._(meta, profile, content, ghosts);
  }

  Future<void> _migrate() async {
    var v = (meta.get('schema') as int?) ?? 0;
    while (v < currentSchema) {
      switch (v) {
        case 0:
          // v0 -> v1: first schema, nothing to convert. Profile defaults are filled on load.
          break;
      }
      v++;
      await meta.put('schema', v);
    }
  }

  String get deviceId {
    var id = meta.get('deviceId') as String?;
    if (id == null) {
      id = newId(12);
      meta.put('deviceId', id);
    }
    return id;
  }

  String? get authMode => meta.get('authMode') as String?;
  set authMode(String? v) => v == null ? meta.delete('authMode') : meta.put('authMode', v);

  /// Loads the profile, falling back to the previous good copy if the main one is corrupt.
  PlayerProfile loadProfile() {
    for (final key in ['main', 'main_prev']) {
      final raw = profileBox.get(key) as String?;
      if (raw == null) continue;
      try {
        return _upgrade(PlayerProfile.fromJson(raw));
      } catch (e) {
        debugPrint('profile load failed ($key): $e');
      }
    }
    return PlayerProfile.fresh(deviceId);
  }

  bool get hasProfile => profileBox.get('main') != null;

  /// Migration/forward compatibility: fill in any missing keys with defaults.
  PlayerProfile _upgrade(PlayerProfile p) {
    final fresh = PlayerProfile.fresh(deviceId).d;
    fresh.forEach((k, v) => p.d.putIfAbsent(k, () => v));
    p.d['deviceId'] = deviceId;
    p.d['v'] = AppConfig.profileSchema;
    return p;
  }

  Future<void> saveProfile(PlayerProfile p) async {
    final prev = profileBox.get('main');
    if (prev != null) await profileBox.put('main_prev', prev);
    await profileBox.put('main', p.toJson());
  }

  Future<void> archiveAndWipeProfile() async {
    final raw = profileBox.get('main') as String?;
    if (raw != null) {
      final list = ((meta.get('archive') as List?) ?? []).cast<String>().toList()..add(raw);
      while (list.length > 3) {
        list.removeAt(0);
      }
      await meta.put('archive', list);
    }
    await profileBox.delete('main');
    await profileBox.delete('main_prev');
    await ghosts.clear();
  }

  List<PlayerProfile> archivedProfiles() {
    final out = <PlayerProfile>[];
    for (final raw in ((meta.get('archive') as List?) ?? []).cast<String>()) {
      try {
        out.add(PlayerProfile.fromJson(raw));
      } catch (_) {}
    }
    return out;
  }

  Future<void> wipeEverything() async {
    await profileBox.clear();
    await ghosts.clear();
    await content.clear();
    await meta.delete('archive');
    await meta.delete('authMode');
  }

  // ---- ghosts -----
  Map<String, dynamic>? ghost(String textId) {
    final raw = ghosts.get(textId) as String?;
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<bool> saveGhostIfBetter(String textId, double wpm, List<List<num>> samples) async {
    final cur = ghost(textId);
    if (cur != null && (cur['wpm'] as num) >= wpm) return false;
    await ghosts.put(textId, jsonEncode({'wpm': wpm, 'samples': samples, 'at': DateTime.now().millisecondsSinceEpoch}));
    return true;
  }

  List<MapEntry<String, Map<String, dynamic>>> allGhosts() {
    final out = <MapEntry<String, Map<String, dynamic>>>[];
    for (final k in ghosts.keys) {
      final g = ghost(k as String);
      if (g != null) out.add(MapEntry(k, g));
    }
    out.sort((a, b) => ((b.value['at'] as num?) ?? 0).compareTo((a.value['at'] as num?) ?? 0));
    return out;
  }
}
