import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/providers.dart';
import 'package:type_racer_legends/core/services/analytics_service.dart';
import 'package:type_racer_legends/core/theme/app_theme.dart';
import 'package:type_racer_legends/data/models/profile.dart';
import 'package:type_racer_legends/features/ads/ad_policy.dart';
import 'package:type_racer_legends/features/content/content_db.dart';
import 'package:type_racer_legends/features/notifications/break_tracker.dart';
import 'package:type_racer_legends/features/notifications/reminder_planner.dart';
import 'package:type_racer_legends/features/settings/licenses_screen.dart';
import 'package:type_racer_legends/features/tutorial/tutorial_screen.dart';
import 'package:type_racer_legends/features/widget/widget_service.dart';
import 'test_support.dart';

PlayerProfile withStreak(int count, String last) {
  final p = PlayerProfile.fresh('d');
  p.m('streak')
    ..['count'] = count
    ..['last'] = last;
  return p;
}

void main() {
  final db = loadSeedContent();

  group('ads policy (optional ads only)', () {
    test('rewarded ads grant the configured coins up to the daily limit, then stop', () {
      final p = PlayerProfile.fresh('d');
      final now = DateTime(2026, 9, 30, 12);
      final limit = AdPolicy.rewardedDailyLimit(db);
      expect(limit, greaterThan(0));
      for (var i = 0; i < limit; i++) {
        expect(AdPolicy.grantRewarded(db, p, now: now), AdPolicy.rewardedCoins(db));
      }
      expect(AdPolicy.rewardedLeft(db, p, now), 0);
      final before = p.coins;
      expect(AdPolicy.grantRewarded(db, p, now: now), 0);
      expect(p.coins, before);
      // a new day resets the allowance
      expect(AdPolicy.rewardedLeft(db, p, DateTime(2026, 10, 1)), limit);
    });

    test('players who removed ads never see any ad', () {
      final p = PlayerProfile.fresh('d')..setFlag('adsRemoved');
      expect(AdPolicy.enabled(db, p), isFalse);
      expect(AdPolicy.rewardedLeft(db, p), 0);
      expect(AdPolicy.grantRewarded(db, p), 0);
      expect(AdPolicy.interstitialDue(db, p, racesSinceAd: 99, msSinceLastAd: null, tutorialOrLesson: false), isFalse);
    });

    test('interstitial respects the remote frequency, the minimum gap and lessons', () {
      final p = PlayerProfile.fresh('d');
      final n = AdPolicy.interstitialEvery(db);
      expect(AdPolicy.interstitialDue(db, p, racesSinceAd: n - 1, msSinceLastAd: null, tutorialOrLesson: false), isFalse);
      expect(AdPolicy.interstitialDue(db, p, racesSinceAd: n, msSinceLastAd: null, tutorialOrLesson: false), isTrue);
      expect(AdPolicy.interstitialDue(db, p, racesSinceAd: n, msSinceLastAd: 10 * 1000, tutorialOrLesson: false), isFalse);
      expect(AdPolicy.interstitialDue(db, p, racesSinceAd: n, msSinceLastAd: AdPolicy.interstitialMinSeconds(db) * 1000 + 1, tutorialOrLesson: false), isTrue);
      expect(AdPolicy.interstitialDue(db, p, racesSinceAd: n, msSinceLastAd: null, tutorialOrLesson: true), isFalse);
    });

    test('the remote kill switch and remote interval are honoured', () {
      final p = PlayerProfile.fresh('d');
      ContentDb withAds(Map<String, dynamic> ads) => loadSeedContent((f) {
            final e = f['economy'] as Map<String, dynamic>;
            e['ads'] = {...(e['ads'] as Map<String, dynamic>), ...ads};
          });
      final patched = withAds({'interstitialEveryNRaces': 10});
      expect(AdPolicy.interstitialDue(patched, p, racesSinceAd: 5, msSinceLastAd: null, tutorialOrLesson: false), isFalse);
      expect(AdPolicy.interstitialDue(patched, p, racesSinceAd: 10, msSinceLastAd: null, tutorialOrLesson: false), isTrue);
      final off = withAds({'interstitialEnabled': false});
      expect(AdPolicy.interstitialDue(off, p, racesSinceAd: 50, msSinceLastAd: null, tutorialOrLesson: false), isFalse);
      final killed = db.withOverrides(killFeatures: {'ads'});
      expect(AdPolicy.enabled(killed, p), isFalse);
      expect(AdPolicy.rewardedLeft(killed, p), 0);
    });
  });

  group('reminders', () {
    final s = GameSettingsStub.make();
    test('streak reminder is two hours before the streak day ends', () {
      final now = DateTime(2026, 9, 30, 10);
      // played today -> reminder tomorrow 22:00 for the next day's streak
      final r1 = ReminderPlanner.plan(db: db, p: withStreak(4, '2026-09-30'), s: s, now: now).where((r) => r.id == ReminderPlanner.streakId).single;
      expect(r1.at, DateTime(2026, 10, 1, 22));
      expect(r1.body, contains('5'));
      // not yet played today and before 22:00 -> tonight
      final r2 = ReminderPlanner.plan(db: db, p: withStreak(4, '2026-09-29'), s: s, now: now).where((r) => r.id == ReminderPlanner.streakId).single;
      expect(r2.at, DateTime(2026, 9, 30, 22));
      // no streak -> nothing to protect
      expect(ReminderPlanner.plan(db: db, p: withStreak(0, ''), s: s, now: now).where((r) => r.id == ReminderPlanner.streakId), isEmpty);
    });

    test('reminders respect the player settings', () {
      final off = GameSettingsStub.make({'streakReminder': false, 'eventNotifs': false});
      expect(ReminderPlanner.plan(db: db, p: withStreak(9, '2026-09-30'), s: off, now: DateTime(2026, 9, 30, 10)), isEmpty);
    });

    test('events: start and "ends tomorrow" reminders only inside the horizon, always in the future', () {
      final ev = db.event('ramadan_2027')!;
      final start = ev.startsAt!;
      final now = start.subtract(const Duration(days: 3));
      final plan = ReminderPlanner.plan(db: db, p: withStreak(0, ''), s: s, now: now);
      final startR = plan.where((r) => r.title.contains('بدأ')).toList();
      expect(startR, isNotEmpty);
      expect(startR.first.at.isAfter(now), isTrue);
      expect(plan.every((r) => r.at.isAfter(now)), isTrue);
      // far from any event: none
      expect(ReminderPlanner.plan(db: db, p: withStreak(0, ''), s: s, now: DateTime(2026, 9, 30)).where((r) => r.id >= 200), isEmpty);
    });
  });

  group('break reminder', () {
    test('fires once after a continuous session and resets after a long gap', () {
      final t = BreakTracker();
      const min = 60 * 1000;
      var now = 0;
      var fired = false;
      for (var i = 0; i < 20; i++) {
        now += 2 * min; // a two-minute race every two minutes
        fired = t.recordRace(raceMs: 2 * min, nowMs: now, breakMinutes: 10) || fired;
        if (fired) break;
      }
      expect(fired, isTrue);
      expect(now, lessThanOrEqualTo(10 * min + 2 * min));
      // after the prompt a new session starts
      expect(t.recordRace(raceMs: min, nowMs: now + 2 * min, breakMinutes: 10), isFalse);
      // a 30 minute pause starts a fresh session
      expect(t.recordRace(raceMs: min, nowMs: now + 40 * min, breakMinutes: 10), isFalse);
      expect(t.sessionMinutes(now + 40 * min), lessThanOrEqualTo(1));
    });
  });

  test('widget data carries streak and best WPM', () {
    final p = withStreak(6, '2026-09-30')..d['b'] = {'best_wpm': 83.4};
    final d = WidgetService.data(p);
    expect(d['streak'], 6);
    expect(d['best_wpm'], 83);
  });

  test('analytics never throws without Firebase and keeps a short history', () async {
    final a = AnalyticsService();
    for (var i = 0; i < 60; i++) {
      await a.log('e$i', {'x': i});
    }
    await a.setUserProps(country: 'MA', level: 3, rank: 'gold');
    expect(a.recent.length, 50);
    expect(a.recent.last, 'e59');
  });

  test('the OFL licence files shipped for every bundled font exist', () {
    for (final f in LicensesScreen.fonts.values) {
      expect(File(f).existsSync(), isTrue, reason: f);
    }
    expect(File('assets/fonts/OpenDyslexic-Regular.otf').existsSync(), isTrue);
  });

  Future<void> show(WidgetTester t, ProviderContainer c, Widget w) async {
    t.view.physicalSize = const Size(1080, 2200);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(), home: Directionality(textDirection: TextDirection.rtl, child: w)),
    ));
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('interactive tutorial: wrong keys are rejected, words advance, finishing rewards once', (t) async {
    final c = await testContainer(t);
    await show(t, c, const TutorialScreen());
    expect(find.text('أهلاً بك في الحلبة!'), findsOneWidget);
    await t.tap(find.text('التالي'));
    await t.pump(const Duration(milliseconds: 300));
    // step 2: type "race" — a wrong letter is rejected
    final tf = find.byType(TextField);
    await t.enterText(tf, 'x');
    await t.pump(const Duration(milliseconds: 50));
    expect((t.widget(tf) as TextField).controller!.text, '');
    await t.enterText(tf, 'rac');
    await t.pump(const Duration(milliseconds: 50));
    expect((t.widget(tf) as TextField).controller!.text, 'rac');
    await t.enterText(tf, 'race');
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('الدقة = السرعة'), findsOneWidget);
    final coinsBefore = c.read(profileProvider).coins;
    // skip to the end
    await t.tap(find.text('تخطّي'));
    await t.pump(const Duration(milliseconds: 600));
    final p = c.read(profileProvider);
    expect(p.flag('tutorialDone'), isTrue);
    expect(p.coins, coinsBefore + 200);
  });

  testWidgets('every tutorial drill can be completed (including the timed power-up word)', (t) async {
    final c = await testContainer(t);
    await show(t, c, const TutorialScreen());
    for (var i = 0; i < tutorialSteps.length; i++) {
      final s = tutorialSteps[i];
      if (s.target == null) {
        await t.tap(find.text(i == tutorialSteps.length - 1 ? 'ابدأ اللعب' : 'التالي'));
        await t.pump(const Duration(milliseconds: 400));
      } else {
        await t.enterText(find.byType(TextField), s.target!);
        await t.pump(const Duration(milliseconds: 800));
      }
      if (s.seconds != null) await t.pump(const Duration(milliseconds: 100));
    }
    expect(c.read(profileProvider).flag('tutorialDone'), isTrue);
  });

  testWidgets('licences screen lists the font licences', (t) async {
    final c = await testContainer(t);
    await show(t, c, const LicensesScreen());
    expect(find.text('OpenDyslexic'), findsOneWidget);
    await t.tap(find.text('OpenDyslexic'));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
  });
}
