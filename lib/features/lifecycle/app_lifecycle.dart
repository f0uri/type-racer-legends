import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../career/challenge_link.dart';
import '../content/content_updater.dart';
import '../../data/remote/progress_sync.dart';
import '../leaderboard/leaderboard_service.dart';
import '../notifications/engagement.dart';

/// Hooks lifecycle + connectivity: sync on background/foreground and when the network returns.
/// Other features register callbacks through [lifecycleHooksProvider].
class LifecycleHooks {
  final List<Future<void> Function()> onResume = [];
  final List<Future<void> Function()> onPause = [];
  final List<Future<void> Function()> onOnline = [];
}

final lifecycleHooksProvider = Provider<LifecycleHooks>((ref) => LifecycleHooks());

class AppLifecycleHost extends ConsumerStatefulWidget {
  final Widget child;
  const AppLifecycleHost({super.key, required this.child});
  @override
  ConsumerState<AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends ConsumerState<AppLifecycleHost> with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = false;
  ChallengeLinkListener? _links;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _links = ChallengeLinkListener(ProviderScope.containerOf(context, listen: false))..start();
      ref.read(contentUpdaterProvider.notifier).refresh(force: true);
    });
    try {
      _sub = Connectivity().onConnectivityChanged.listen((r) {
        final offline = r.isEmpty || (r.length == 1 && r.first == ConnectivityResult.none);
        if (_wasOffline && !offline) {
          ref.read(profileProvider.notifier).syncNow();
          ref.read(progressSyncProvider.notifier).flush();
          ref.read(contentUpdaterProvider.notifier).refresh(force: true);
          ref.read(leaderboardProvider).flush();
          for (final f in ref.read(lifecycleHooksProvider).onOnline) {
            f();
          }
        }
        _wasOffline = offline;
      });
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hooks = ref.read(lifecycleHooksProvider);
    if (state == AppLifecycleState.paused) {
      ref.read(profileProvider.notifier).syncNow();
      // The cloud save goes out immediately, not on the 1.2s debounce: the OS may stop the
      // process at any moment after a pause, and the player's last race must not be the one lost.
      ref.read(progressSyncProvider.notifier).flush();
      ref.read(engagementProvider).refresh();
      for (final f in hooks.onPause) {
        f();
      }
    } else if (state == AppLifecycleState.resumed) {
      ref.read(profileProvider.notifier).syncNow();
      ref.read(contentUpdaterProvider.notifier).refresh();
      ref.read(leaderboardProvider).flush();
      for (final f in hooks.onResume) {
        f();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _links?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
