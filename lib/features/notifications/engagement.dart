import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/remote/firebase_boot.dart';
import '../widget/widget_service.dart';
import 'break_tracker.dart';
import 'notification_service.dart';
import 'push_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());
final widgetServiceProvider = Provider<WidgetService>((ref) => WidgetService());
final breakTrackerProvider = Provider<BreakTracker>((ref) => BreakTracker());
final pushServiceProvider = Provider<PushService>((ref) => PushService(ref.watch(cloudSyncProvider), ref.watch(notificationServiceProvider)));

/// Keeps reminders, the home-screen widget and the push token in step with the player's progress.
class Engagement {
  Engagement(this.ref);
  final Ref ref;
  bool _askedPermission = false;

  Future<void> startup() async {
    final notifs = ref.read(notificationServiceProvider);
    await notifs.init();
    final p = ref.read(profileProvider);
    if (!_askedPermission && !p.flag('notifAsked')) {
      _askedPermission = true;
      await notifs.requestPermission();
      ref.read(profileProvider.notifier).update((pp) => pp.setFlag('notifAsked'), syncSoon: false);
    }
    if (FirebaseBoot.available) unawaited(ref.read(pushServiceProvider).init(ref.read(settingsProvider), ref.read(profileProvider)));
    await refresh();
  }

  Future<void> refresh() async {
    final db = ref.read(contentProvider);
    final p = ref.read(profileProvider);
    final s = ref.read(settingsProvider);
    await ref.read(notificationServiceProvider).reschedule(db, p, s);
    await ref.read(widgetServiceProvider).update(p);
    if (FirebaseBoot.available) {
      final push = ref.read(pushServiceProvider);
      await push.applySettings(s);
      await push.saveToken(s, p);
    }
  }
}

final engagementProvider = Provider<Engagement>((ref) => Engagement(ref));
