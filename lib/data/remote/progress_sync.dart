import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../features/auth/auth_controller.dart';
import '../merge/profile_merge.dart';
import '../models/profile.dart';
import 'drive_sync.dart';

/// Google Drive sync: the game's save file lives in the player's own hidden Drive app folder.
/// No server, no database, no billing — the only thing needed is a Google sign-in with the
/// `drive.appdata` scope, which is granted per player and can be revoked by them at any time.
class ProgressSyncState {
  /// A Web client id was compiled in, so Drive sync can work at all.
  final bool configured;

  /// We hold a Drive access token for the signed-in player.
  final bool connected;
  final bool busy;
  final DateTime? last;
  final String? error;
  const ProgressSyncState({required this.configured, this.connected = false, this.busy = false, this.last, this.error});

  ProgressSyncState copyWith({bool? connected, bool? busy, DateTime? last, Object? error = _sentinel}) => ProgressSyncState(
        configured: configured,
        connected: connected ?? this.connected,
        busy: busy ?? this.busy,
        last: last ?? this.last,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );
}

const Object _sentinel = Object();

/// The Web OAuth client id, from `--dart-define=GOOGLE_WEB_CLIENT_ID=...` when the build sets it
/// (CI does) or from the bundled `assets/google_client_id.txt` otherwise. It is not a secret: it
/// ships inside every copy of the app. Empty means no Google sign-in and no Drive sync, and the
/// game then works exactly as before: guest, local, offline.
String _googleWebClientId = const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
String get googleWebClientId => _googleWebClientId;

/// Called once from `main()`: reads the bundled id when the build did not define one. The player
/// can therefore enable cloud saves by editing a single line in the repository, with no CI secret
/// and no console configuration beyond creating the OAuth clients themselves.
Future<void> loadBundledGoogleClientId() async {
  if (_googleWebClientId.isNotEmpty) return;
  try {
    final raw = await rootBundle.loadString('assets/google_client_id.txt');
    for (final line in raw.split('\n')) {
      final value = line.trim();
      if (value.isEmpty || value.startsWith('#')) continue;
      if (value.endsWith('.apps.googleusercontent.com')) {
        _googleWebClientId = value;
        debugPrint('google client id loaded from assets');
        return;
      }
      debugPrint('assets/google_client_id.txt: ignoring a line that is not a client id');
      return;
    }
  } catch (e) {
    debugPrint('no bundled google client id: $e');
  }
}

class ProgressSyncController extends Notifier<ProgressSyncState> {
  Timer? _debounce;
  bool _dirty = false;

  @override
  ProgressSyncState build() {
    ref.onDispose(() => _debounce?.cancel());
    // The token lives in the auth state: follow it so the UI always tells the truth.
    ref.listen<AuthState>(authProvider, (prev, next) {
      final was = prev?.driveToken != null;
      final now = next.driveToken != null;
      if (was != now) state = state.copyWith(connected: now, error: null);
    });
    final configured = googleWebClientId.isNotEmpty;
    // Already signed in from a previous session: fetch a Drive token silently so saving resumes
    // without asking the player to sign in again (no UI is ever shown for this call).
    if (configured && ref.read(authProvider).isGoogle) {
      Future.microtask(() {
        try {
          ref.read(authProvider.notifier).refreshDriveToken();
        } catch (_) {}
      });
    }
    return ProgressSyncState(configured: configured, connected: ref.read(authProvider).driveToken != null);
  }

  String? get _token => ref.read(authProvider).driveToken;

  DriveSync get _drive => ref.read(driveSyncProvider);

  /// The save file: everything the player has, plus a small readable summary at the top
  /// (useful when debugging, and it makes the file self-describing if it is ever inspected).
  static Map<String, dynamic> payload(PlayerProfile p) => {
        'app': 'type-racer-legends',
        'schema': AppConfig.profileSchema,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'rev': p.rev,
        'uid': p.uid,
        'summary': ProfileMerger.summary(p),
        'profile': p.toJson(),
      };

  /// Called after every profile change: writes to Drive shortly after the player stops acting,
  /// so a burst of changes costs exactly one upload.
  void schedule([Duration delay = const Duration(milliseconds: 1200)]) {
    if (_token == null) return;
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      pushNow();
    });
  }

  /// Uploads the current profile. Returns false when nothing was sent (not connected / offline).
  Future<bool> pushNow() async {
    final token = _token;
    if (token == null) return false;
    if (state.busy) {
      _dirty = true;
      return false;
    }
    state = state.copyWith(busy: true, error: null);
    try {
      await _pushWithRetry(token);
      _dirty = false;
      state = state.copyWith(busy: false, last: DateTime.now(), error: null);
      ref.read(syncStateProvider.notifier).set(SyncState(SyncPhase.ok, last: DateTime.now()));
      return true;
    } catch (e) {
      debugPrint('drive sync failed: $e');
      state = state.copyWith(busy: false, error: '$e');
      ref.read(syncStateProvider.notifier).set(SyncState(SyncPhase.error, last: state.last, error: '$e'));
      return false;
    } finally {
      if (_dirty && _token != null) schedule(const Duration(seconds: 20));
    }
  }

  Future<void> _pushWithRetry(String token) async {
    try {
      await _push(token);
    } on DriveAuthException {
      // Access tokens last an hour: silently re-authorize once, then give up quietly.
      final fresh = await ref.read(authProvider.notifier).refreshDriveToken();
      if (fresh == null) rethrow;
      await _push(fresh);
    }
  }

  /// One upload. If the cloud file belongs to a device that moved further, merges first: an old
  /// local save can add to the cloud one but must never replace it.
  Future<void> _push(String token) async {
    final result = await _drive.push(token, payload(ref.read(profileProvider)));
    if (result.remoteAhead) await _pullMergePush(token);
  }

  /// Sign-in on a device that may be new: downloads the cloud save, merges it with whatever is
  /// local (counters and unlocks are unioned by [ProfileMerger]), then uploads the union.
  /// Returns true when a cloud save was found and merged.
  Future<bool> pullAndMerge({bool interactiveAuthorization = false}) async {
    var token = _token;
    if (token == null && interactiveAuthorization) {
      token = await ref.read(authProvider.notifier).refreshDriveToken(interactive: true);
    }
    if (token == null) return false;
    state = state.copyWith(busy: true, error: null);
    try {
      final restored = await _pullMergePush(token);
      state = state.copyWith(busy: false, last: DateTime.now(), error: null);
      ref.read(syncStateProvider.notifier).set(SyncState(SyncPhase.ok, last: DateTime.now()));
      return restored;
    } catch (e) {
      debugPrint('drive restore failed: $e');
      state = state.copyWith(busy: false, error: '$e');
      ref.read(syncStateProvider.notifier).set(SyncState(SyncPhase.error, last: state.last, error: '$e'));
      return false;
    }
  }

  /// Pull, merge into the local profile, push the union. The one place where cloud and local
  /// progress meet, shared by sign-in, the player pressing «مزامنة الآن», and a stale-device
  /// conflict detected during a normal save.
  Future<bool> _pullMergePush(String token) async {
    final remote = await _drive.pull(token);
    var restored = false;
    final blob = remote?['profile'];
    if (blob is String && blob.isNotEmpty) {
      final server = PlayerProfile.fromJson(blob);
      final local = ref.read(profileProvider);
      final merged = ProfileMerger.merge(local, server);
      // the save belongs to this account, but the device stays this device
      merged.d['deviceId'] = local.deviceId;
      ref.read(profileProvider.notifier).replace(merged);
      restored = true;
    }
    // The union is uploaded without checking the result: merging sets the revision one above
    // everything it saw, so this write can never come back as a conflict.
    await _drive.push(token, payload(ref.read(profileProvider)));
    return restored;
  }

  /// Removes the cloud save (account deletion). Best effort: local data is wiped regardless.
  Future<void> eraseRemote() async {
    final token = _token;
    if (token == null) return;
    try {
      await _drive.erase(token);
    } catch (e) {
      debugPrint('drive erase failed: $e');
    }
  }

  /// Sign-out: the save stays in the player's Drive, the token is dropped with the session.
  void forget() {
    _debounce?.cancel();
    _dirty = false;
    state = state.copyWith(connected: false, busy: false, error: null);
  }
}

final driveSyncProvider = Provider<DriveSync>((ref) => DriveSync());

final progressSyncProvider = NotifierProvider<ProgressSyncController, ProgressSyncState>(ProgressSyncController.new);
