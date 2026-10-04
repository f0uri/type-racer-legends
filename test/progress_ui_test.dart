import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/providers.dart';
import 'package:type_racer_legends/features/career/progress.dart';
import 'package:type_racer_legends/features/career/progress_screen.dart';
import 'package:type_racer_legends/features/home/home_shell.dart';
import 'screens_smoke_test.dart' show show;
import 'test_support.dart';

void main() {
  testWidgets('progress screen: quests, season, achievements and events tabs render and claims work', (t) async {
    final c = await testContainer(t);
    final db = c.read(contentProvider);
    c.read(profileProvider.notifier).update((p) {
      Progression.evaluate(db, p);
      p.addCounter('races', 12);
      for (final q in Quests.selection(db, 'daily')) {
        if (!Metrics.bests.contains(q.metric)) p.addCounter(q.metric, q.target);
      }
      Season.addPoints(p, db, 650);
      Progression.evaluate(db, p);
    });
    await show(t, c, const ProgressScreen(embedded: false));
    expect(find.text('مهام اليوم'), findsOneWidget);
    expect(find.text('استلام'), findsWidgets);
    final coins = c.read(profileProvider).coins;
    await t.tap(find.text('استلام').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(c.read(profileProvider).coins, greaterThan(coins));
    await t.tap(find.text('الموسم'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(find.textContaining('الموسم 1'), findsOneWidget);
    expect(find.textContaining('استلم كل المكافآت'), findsOneWidget);
    // the track opens on the player's own level and says so
    expect(find.text('أنت هنا'), findsOneWidget);
    await t.tap(find.textContaining('استلم كل المكافآت'));
    await t.pump(const Duration(milliseconds: 300));
    expect(Season.claimableCount(db, c.read(profileProvider)), 0);
    await t.tap(find.text('الإنجازات'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(find.textContaining('إنجاز'), findsWidgets);
    expect(find.text('استلم'), findsWidgets);
    await t.tap(find.text('استلم').first);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('الأحداث'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('home shell shows the progress tab with a badge and offers the daily login reward', (t) async {
    final c = await testContainer(t);
    c.read(profileProvider.notifier).update((p) => p.setFlag('tutorialDone'));
    await show(t, c, const HomeShell());
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    // the daily login dialog appears on first open
    expect(find.text('مرحباً بعودتك!'), findsOneWidget);
    await t.tap(find.text('استلم مكافأة اليوم'));
    await t.pump(const Duration(milliseconds: 300));
    expect(c.read(profileProvider).coins, greaterThan(0));
    await t.tap(find.text('إغلاق'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('التقدم').last);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('مهام اليوم'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
