import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/providers.dart';
import 'package:type_racer_legends/core/theme/app_theme.dart';
import 'package:type_racer_legends/features/career/campaign_screen.dart';
import 'package:type_racer_legends/features/career/challenge_link.dart';
import 'package:type_racer_legends/features/career/custom_text_screen.dart';
import 'package:type_racer_legends/features/career/daily_screen.dart';
import 'package:type_racer_legends/features/career/ghost_screen.dart';
import 'package:type_racer_legends/features/career/tournament_screen.dart';
import 'package:type_racer_legends/features/career/world_tour_screen.dart';
import 'package:type_racer_legends/features/home/home_screen.dart';
import 'package:type_racer_legends/features/race/quick_race_sheet.dart';
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
  testWidgets('home lists the game modes and opens the quick race sheet', (t) async {
    final c = await testContainer(t);
    await show(t, c, const HomeScreen());
    // the lobby shows four hero pods plus one giant start button
    for (final s in ['الحملة', 'البطولات', 'التحديات', 'التعلّم', 'سباق سريع']) {
      expect(find.text(s, skipOffstage: false), findsWidgets, reason: s);
    }
    // the secondary modes are one tap away behind «المزيد»
    await t.tap(find.text('المزيد من الأوضاع'));
    await t.pump(const Duration(milliseconds: 500));
    for (final s in ['الأشباح', 'البقاء', 'قتال الطريق', 'جولة العالم', 'نص مخصص', 'التدريب الذكي']) {
      expect(find.text(s, skipOffstage: false), findsWidgets, reason: s);
    }
    await t.tapAt(const Offset(10, 10)); // dismiss the sheet
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('سباق سريع').first);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(QuickRaceSheet), findsOneWidget);
  });

  testWidgets('campaign map renders every biome and opens a stage sheet', (t) async {
    final c = await testContainer(t);
    await show(t, c, const CampaignScreen());
    expect(find.text('1'), findsWidgets);
    await t.tap(find.text('1').first);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(StageSheet), findsOneWidget);
    expect(find.text('ابدأ المرحلة'), findsOneWidget);
    // dismiss the sheet and swipe through every biome page
    await t.tapAt(const Offset(10, 10));
    await t.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < c.read(contentProvider).biomes.length; i++) {
      await t.drag(find.byType(PageView), const Offset(-320, 0));
      await t.pump(const Duration(milliseconds: 500));
    }
    for (var i = 0; i < c.read(contentProvider).biomes.length; i++) {
      await t.drag(find.byType(PageView), const Offset(320, 0));
      await t.pump(const Duration(milliseconds: 500));
    }
  });

  testWidgets('tournament list + bracket, world tour, ghosts, daily, custom text and challenge hub build', (t) async {
    final c = await testContainer(t);
    final db = c.read(contentProvider);
    await show(t, c, const TournamentListScreen());
    expect(find.text('بطولة اليوم'), findsOneWidget);
    await show(t, c, TournamentScreen(def: db.tournaments.first));
    expect(find.text('ادخل البطولة'), findsOneWidget);
    await show(t, c, TournamentScreen(def: db.tournaments.last));
    await show(t, c, const WorldTourScreen());
    expect(find.textContaining('طنجة'), findsWidgets);
    await show(t, c, const GhostScreen());
    await show(t, c, const DailyScreen());
    expect(find.text('تحدي اليوم'), findsWidgets);
    await show(t, c, const CustomTextScreen());
    await show(t, c, const ChallengeHubScreen());
  });
}
