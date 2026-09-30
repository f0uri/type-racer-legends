import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../core/providers.dart';
import '../../core/util/dates.dart';
import '../../data/models/profile.dart';
import '../../data/remote/cloud_sync.dart';
import '../../data/remote/firebase_boot.dart';
import 'notification_service.dart';

/// Background isolate entry point (required by firebase_messaging). The system tray shows notification messages itself.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

/// Firebase Cloud Messaging: topic subscriptions (announcements / events) and the device token.
class PushService {
  PushService(this.cloud, this.local);
  final CloudSync cloud;
  final NotificationService local;
  bool _started = false;

  Future<void> init(GameSettings s, PlayerProfile p) async {
    if (!FirebaseBoot.available || _started || kIsWeb) return;
    _started = true;
    try {
      final m = FirebaseMessaging.instance;
      await m.requestPermission();
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n != null) local.showNow(n.title ?? 'Type Racer Legends', n.body ?? '');
      });
      await m.subscribeToTopic('all');
      await applySettings(s);
      m.onTokenRefresh.listen((t) => saveToken(s, p, token: t));
      await saveToken(s, p);
    } catch (e) {
      debugPrint('push init failed: $e');
    }
  }

  Future<void> applySettings(GameSettings s) async {
    if (!FirebaseBoot.available) return;
    try {
      final m = FirebaseMessaging.instance;
      if (s.eventNotifs) {
        await m.subscribeToTopic('events');
      } else {
        await m.unsubscribeFromTopic('events');
      }
    } catch (_) {}
  }

  /// Stores the token for signed-in (Google) players. Fields match firestore.rules (fcmTokens).
  Future<void> saveToken(GameSettings s, PlayerProfile p, {String? token}) async {
    final uid = cloud.uid;
    if (!FirebaseBoot.available || uid == null) return;
    try {
      final t = token ?? await FirebaseMessaging.instance.getToken();
      if (t == null) return;
      final now = DateTime.now();
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
      await FirebaseFirestore.instance.doc('fcmTokens/$uid').set({
        'token': t,
        'updatedAt': FieldValue.serverTimestamp(),
        'streakEnds': (p.streakLast == dayKey(now) ? endOfDay.add(const Duration(days: 1)) : endOfDay).millisecondsSinceEpoch,
        'notifStreak': s.streakReminder,
        'notifEvents': s.eventNotifs,
        'tz': now.timeZoneName,
      });
    } catch (_) {}
  }
}
