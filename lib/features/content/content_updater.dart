import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_info.dart';
import '../../core/providers.dart';
import '../../core/remote_settings.dart';
import 'content_repository.dart';
import 'content_sync.dart';
import 'new_items.dart';

class ContentUpdateState {
  final bool running;
  final DateTime? lastCheck;
  final String? lastError;
  final int version;
  final int changedFiles;
  const ContentUpdateState({this.running = false, this.lastCheck, this.lastError, this.version = 0, this.changedFiles = 0});
}

final appInfoProvider = FutureProvider<AppInfo>((ref) => AppInfo.load());

/// Orchestrates live-content refreshes and Remote Config: on start, on resume (throttled) and when the network returns.
class ContentUpdater extends Notifier<ContentUpdateState> {
  static const minGap = Duration(minutes: 20);

  @override
  ContentUpdateState build() => const ContentUpdateState();

  /// Returns true when new content was applied.
  Future<bool> refresh({bool force = false}) async {
    if (state.running) return false;
    final last = state.lastCheck;
    if (!force && last != null && DateTime.now().difference(last) < minGap) return false;
    state = ContentUpdateState(running: true, lastCheck: last, version: state.version);
    var applied = false;
    String? error;
    var changed = 0;
    try {
      final info = await ref.read(appInfoProvider.future);
      final store = ref.read(storeProvider);
      final sync = ContentSync(store, appVersionCode: info.versionCode);
      final r = await sync.refresh();
      sync.close();
      error = r.error;
      if (r.updated) {
        final db = await ContentRepository(store).loadLocal();
        ref.read(contentProvider.notifier).set(db);
        applied = true;
        changed = r.changedFiles.length;
      }
      final remote = await RemoteSettingsService().fetch();
      ref.read(contentProvider.notifier).applyRemote(remote);
    } catch (e) {
      error = e.toString();
      debugPrint('content refresh failed: $e');
    }
    state = ContentUpdateState(lastCheck: DateTime.now(), lastError: error, version: ref.read(contentProvider).catalogVersion, changedFiles: changed);
    return applied;
  }
}

final contentUpdaterProvider = NotifierProvider<ContentUpdater, ContentUpdateState>(ContentUpdater.new);

/// Ids of vehicles / skins / outfits the player has not looked at yet.
final unseenItemsProvider = Provider<Set<String>>((ref) {
  final db = ref.watch(contentProvider);
  final p = ref.watch(profileProvider);
  return NewItems.unseen(db, p);
});
