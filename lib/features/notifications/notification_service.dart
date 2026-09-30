import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../core/providers.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';
import 'reminder_planner.dart';

/// Local notifications: streak reminder (two hours before the streak day ends) and seasonal events.
/// Everything is wrapped so that a missing plugin / denied permission can never crash the game.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'trl_main',
    'تنبيهات اللعبة',
    channelDescription: 'تذكير السلسلة اليومية والأحداث',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _details = NotificationDetails(android: _channel);

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (_ready || !supported) return;
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }
      await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _ready = true;
    } catch (e) {
      debugPrint('notifications init failed: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    try {
      return await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Replaces every scheduled notification with the current plan.
  Future<int> reschedule(ContentDb db, PlayerProfile p, GameSettings s, {DateTime? now}) async {
    if (!supported) return 0;
    await init();
    if (!_ready) return 0;
    try {
      await _plugin.cancelAllPendingNotifications();
      final plan = ReminderPlanner.plan(db: db, p: p, s: s, now: now ?? DateTime.now());
      for (final r in plan) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      return plan.length;
    } catch (e) {
      debugPrint('notification scheduling failed: $e');
      return 0;
    }
  }

  /// Shows a message immediately (used for push messages received while the app is open).
  Future<void> showNow(String title, String body) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(id: DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000 + 1000, title: title, body: body, notificationDetails: _details);
    } catch (_) {}
  }
}
