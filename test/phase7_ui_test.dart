import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/providers.dart';
import 'package:type_racer_legends/core/theme/app_theme.dart';
import 'package:type_racer_legends/features/learn/keyboard_guide.dart';
import 'package:type_racer_legends/features/learn/learn_logic.dart';
import 'package:type_racer_legends/features/learn/learn_screens.dart';
import 'package:type_racer_legends/features/profile/profile_screen.dart';
import 'package:type_racer_legends/features/race/ui/race_screen.dart';
import 'package:type_racer_legends/features/race/ui/result_screen.dart';
import 'package:type_racer_legends/features/stats/stats_screen.dart';
import 'test_support.dart';

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

void main() {
  testWidgets('learn hub, lessons, vocabulary, training and certificates render', (t) async {
    final c = await testContainer(t);
    await show(t, c, const LearnHubScreen());
    expect(find.byType(LearnHubScreen), findsOneWidget);
    for (final w in <Widget>[const LessonsScreen(), const VocabScreen(), const TrainingScreen(), const CertificatesScreen(), const OfficialTestScreen()]) {
      await show(t, c, w);
      expect(tester(t), isNull);
    }
  });

  testWidgets('stats screen renders with an empty profile', (t) async {
    final c = await testContainer(t);
    await show(t, c, const StatsScreen());
    expect(find.text('إحصائياتي'), findsOneWidget);
    expect(find.text('هدفي الأسبوعي'), findsOneWidget);
    expect(find.text('تحديد الهدف'), findsOneWidget);
  });

  testWidgets('stats screen charts draw once there is history and the weekly goal can be set', (t) async {
    final c = await testContainer(t);
    c.read(profileProvider.notifier).update((p) {
      p.d['hist'] = [30.0, 32.0, 35.0, 33.0, 38.0, 41.0, 40.0, 44.0];
      p.m('sdays')[DateTime.now().toIso8601String().substring(0, 10)] = [3, 400, 90000, 440, 1200];
    });
    await show(t, c, const StatsScreen());
    expect(find.byType(CustomPaint), findsWidgets);
    await t.ensureVisible(find.text('تحديد الهدف'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('تحديد الهدف'));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('حفظ'));
    await t.pump(const Duration(milliseconds: 400));
    expect(c.read(profileProvider).m('goal')['target'], isNotNull);
  });

  testWidgets('profile screen shows identity, invite code and opens certificates', (t) async {
    final c = await testContainer(t);
    await show(t, c, const ProfileScreen());
    expect(find.text('ملفي'), findsOneWidget);
    expect(find.text('شارك بطاقة اللاعب'), findsOneWidget);
    await t.scrollUntilVisible(find.text('ادعُ أصدقاءك'), 400, scrollable: find.byType(Scrollable).first);
    expect(find.text(c.read(profileProvider).refCode, findRichText: true), findsWidgets);
  });

  testWidgets('a lesson runs in guide mode (keyboard + finger hint) and ends on the results screen', (t) async {
    final c = await testContainer(t);
    final db = c.read(contentProvider);
    final cfg = LessonsLogic.config(db.lessons.first);
    await show(t, c, RaceScreen(config: cfg));
    await t.tap(find.text('ابدأ السباق'));
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(KeyboardGuide), findsOneWidget);
    final sess = RaceScreen.debugSession!;
    expect(sess.started, isTrue);
    for (var frame = 0; frame < 6000 && find.byType(ResultScreen).evaluate().isEmpty; frame++) {
      await t.pump(const Duration(milliseconds: 40));
      if (frame % 3 != 0 || sess.player.finished) continue;
      final tf = find.byType(TextField);
      if (tf.evaluate().isEmpty) continue;
      final ch = sess.engine.pos < sess.engine.length ? sess.engine.text[sess.engine.pos] : ' ';
      await t.enterText(tf, '\u200B\u200B$ch');
    }
    expect(sess.player.finished, isTrue);
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(ResultScreen), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

Object? tester(WidgetTester t) => t.takeException();
