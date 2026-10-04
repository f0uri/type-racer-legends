import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/local_store.dart';
import '../data/merge/profile_merge.dart';
import '../data/models/profile.dart';
import '../data/remote/cloud_sync.dart';
import '../data/remote/firebase_boot.dart';
import '../features/ai/ai_driver.dart';
import 'remote_settings.dart';
import '../features/content/content_db.dart';
import '../data/remote/progress_sync.dart';
import 'services/audio_service.dart';
import 'services/haptics_service.dart';
import 'util/dates.dart';

final storeProvider = Provider<LocalStore>((ref) => throw UnimplementedError('storeProvider must be overridden'));
final initialContentProvider = Provider<ContentDb>((ref) => ContentDb.empty());
final cloudSyncProvider = Provider<CloudSync>((ref) => CloudSync());

class ContentController extends Notifier<ContentDb> {
  ContentDb? _base;
  RemoteSettings _remote = RemoteSettings.empty;

  @override
  ContentDb build() {
    _base = ref.read(initialContentProvider);
    return _compose();
  }

  ContentDb _compose() {
    final db = _base!.withOverrides(killFeatures: _remote.killFeatures, killItems: _remote.killItems, economyPatch: _remote.economyPatch);
    // pushes data-driven AI personality parameters into the AI engine
    final pp = db.ai['personalities'];
    if (pp is Map) Persona.applyContent(pp.cast<String, dynamic>());
    return db;
  }

  void set(ContentDb db) {
    _base = db;
    state = _compose();
  }

  void applyRemote(RemoteSettings r) {
    _remote = r;
    state = _compose();
  }

  RemoteSettings get remote => _remote;
}

final contentProvider = NotifierProvider<ContentController, ContentDb>(ContentController.new);

enum SyncPhase { idle, syncing, ok, error, offline }

class SyncState {
  final SyncPhase phase;
  final DateTime? last;
  final String? error;
  const SyncState(this.phase, {this.last, this.error});
}

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState(SyncPhase.idle);
  void set(SyncState s) => state = s;
}

final syncStateProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Holds the player profile: local-first, every mutation is persisted immediately and synced to the cloud when possible.
class ProfileController extends Notifier<PlayerProfile> {
  Timer? _debounce;
  bool _syncing = false;
  bool _dirty = false;

  @override
  PlayerProfile build() {
    ref.onDispose(() => _debounce?.cancel());
    return ref.read(storeProvider).loadProfile();
  }

  LocalStore get _store => ref.read(storeProvider);

  /// Mutate a copy of the profile, persist, and schedule a cloud sync.
  PlayerProfile update(void Function(PlayerProfile p) fn, {bool syncSoon = true}) {
    final p = state.clone();
    fn(p);
    p.touch();
    state = p;
    _store.saveProfile(p);
    if (syncSoon) scheduleSync();
    return p;
  }

  void replace(PlayerProfile p) {
    state = p;
    _store.saveProfile(p);
  }

  bool get canSync => FirebaseBoot.available && ref.read(cloudSyncProvider).uid != null;

  void scheduleSync([Duration delay = const Duration(seconds: 8)]) {
    _dirty = true;
    // Google Drive sync (no server needed) has its own short debounce: between two races the
    // player's save is already uploaded, so opening the game on another phone loses nothing.
    ref.read(progressSyncProvider.notifier).schedule();
    if (!canSync) return;
    _debounce?.cancel();
    _debounce = Timer(delay, () => syncNow());
  }

  /// Merges with the cloud copy (transaction). Safe to call any time; failures keep local data intact.
  Future<bool> syncNow() async {
    if (!canSync) {
      return false;
    }
    if (_syncing) {
      _dirty = true;
      return false;
    }
    _syncing = true;
    _debounce?.cancel();
    ref.read(syncStateProvider.notifier).set(SyncState(SyncPhase.syncing, last: ref.read(syncStateProvider).last));
    try {
      final snapshot = state.clone();
      final merged = await ref.read(cloudSyncProvider).sync(snapshot);
      // Re-merge with any edits made while the transaction was running.
      final now = ProfileMerger.merge(state, merged);
      now.d['rev'] = state.rev; // do not inflate revision purely from merging
      replace(now);
      _dirty = false;
      ref.read(syncStateProvider.notifier).set(SyncState(SyncPhase.ok, last: DateTime.now()));
      return true;
    } catch (e) {
      debugPrint('sync failed: $e');
      ref.read(syncStateProvider.notifier).set(SyncState(SyncPhase.error, last: ref.read(syncStateProvider).last, error: e.toString()));
      return false;
    } finally {
      _syncing = false;
      if (_dirty && canSync) scheduleSync(const Duration(seconds: 30));
    }
  }

  /// Called after login: attaches the uid and merges the cloud copy with local (guest) progress.
  Future<void> linkAccount(String uid, {String? displayName}) async {
    update((p) {
      p.uid = uid;
      if ((p.name == 'لاعب' || p.name.isEmpty) && displayName != null && displayName.isNotEmpty) {
        p.setIdentity(name: displayName.split(' ').first);
      }
    }, syncSoon: false);
    await syncNow();
  }

  Future<void> resetToFresh() async {
    await _store.archiveAndWipeProfile();
    state = PlayerProfile.fresh(_store.deviceId);
    await _store.saveProfile(state);
  }
}

final profileProvider = NotifierProvider<ProfileController, PlayerProfile>(ProfileController.new);

/// Typed read-only view of settings with defaults.
class GameSettings {
  final Map<String, dynamic> m;
  GameSettings(this.m);
  bool _b(String k, bool d) => m[k] is bool ? m[k] as bool : d;
  double _d(String k, double d) => (m[k] as num?)?.toDouble() ?? d;
  bool get sound => _b('sound', true);
  bool get music => _b('music', true);
  double get sfxVolume => _d('sfxVol', 0.8);
  double get musicVolume => _d('musicVol', 0.5);
  bool get haptics => _b('haptics', true);
  double get fontScale => _d('fontScale', 1.0);
  bool get dyslexia => _b('dyslexia', false);
  String get colorBlind => (m['colorBlind'] as String?) ?? 'none';
  int get difficulty => (m['difficulty'] as num?)?.toInt() ?? 0; // 0 = auto
  bool get nextCharHint => _b('nextCharHint', true);
  bool get backspace => _b('backspace', true);
  bool get fps30 => _b('fps30', false);
  bool get breakReminder => _b('breakReminder', true);
  String get textLang => (m['textLang'] as String?) ?? 'en';
  bool get foldAccents => _b('foldAccents', true);
  bool get streakReminder => _b('streakReminder', true);
  bool get eventNotifs => _b('eventNotifs', true);
  bool get showGhost => _b('showGhost', true);
  bool get autoUpdateCheck => _b('autoUpdateCheck', true);
}

final settingsProvider = Provider<GameSettings>((ref) => GameSettings(ref.watch(profileProvider.select((p) => p.settings))));

final levelInfoProvider = Provider<LevelInfo>((ref) {
  final c = ref.watch(contentProvider);
  final p = ref.watch(profileProvider);
  final lv = c.econ('levels');
  return p.level(base: (lv['xpBase'] as num?)?.toInt() ?? 120, step: (lv['xpStep'] as num?)?.toInt() ?? 45, maxLevel: (lv['maxLevel'] as num?)?.toInt() ?? 100);
});

/// Races finished in a row this session. In-memory on purpose: it is ceremony (the result
/// screen shows «سلسلة الجولات»), not progress, so it must reset with the app.
final raceChainProvider = StateProvider<int>((ref) => 0);

/// Daily key provider that refreshes at midnight (used to rebuild daily UI).
final todayProvider = Provider<String>((ref) => dayKey());

final audioProvider = Provider<AudioService>((ref) {
  final a = AudioService();
  ref.onDispose(a.dispose);
  final s = ref.read(settingsProvider);
  a.configure(sfx: s.sound, music: s.music, sfxVolume: s.sfxVolume, musicVolume: s.musicVolume);
  ref.listen(settingsProvider, (_, n) => a.configure(sfx: n.sound, music: n.music, sfxVolume: n.sfxVolume, musicVolume: n.musicVolume));
  return a;
});

final hapticsProvider = Provider<Haptics>((ref) {
  final h = Haptics();
  final s = ref.read(settingsProvider);
  h.enabled = s.haptics;
  ref.listen(settingsProvider, (_, n) => h.enabled = n.haptics);
  return h;
});
