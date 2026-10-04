import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/theme/app_theme.dart';
import 'package:type_racer_legends/data/models/content_models.dart';
import 'package:type_racer_legends/features/race/engine/race_models.dart';
import 'package:type_racer_legends/features/race/engine/typing_engine.dart';
import 'package:type_racer_legends/features/race/race_outcome.dart';
import 'package:type_racer_legends/features/race/ui/result_screen.dart';
import 'test_support.dart';

/// The result screen is the one page every single race ends on, and the one that just learned to
/// animate: a win card dropping in, a staggered stats block and a coin burst. So it gets its own
/// guard — a win at the largest text the app allows on a small phone, the same with the OS asking
/// for reduced motion, and a plain race with nothing to celebrate.
const text = 'the quick brown fox jumps over the lazy dog and keeps running to the end';

RaceResult _result({bool won = true, bool withLog = true}) {
  final e = TypingEngine(text);
  var t = 600;
  for (var i = 0; i < text.length; i++) {
    e.type(text[i], t);
    t += 170;
  }
  return RaceResult(
    config: RaceConfig(
      modeId: 'daily',
      title: 'تحدي اليوم',
      rules: RaceRules.purePlay,
      ranked: true,
      text: TextItem({'id': 'eq1', 't': text, 'cat': 'sentence', 'lang': 'en', 'diff': 2, 'len': text.length}),
    ),
    standings: [
      RacerResult(id: 'p', name: 'أنت', cc: 'MA', isPlayer: true, isAi: false, rank: won ? 1 : 3, wpm: 88, accuracy: 100, time: 12.9),
      RacerResult(id: 'a', name: 'ظل', cc: 'MA', isPlayer: false, isAi: true, rank: won ? 2 : 1, wpm: 84, accuracy: 98, time: 12.4),
      RacerResult(id: 'b', name: 'نيون', cc: 'MA', isPlayer: false, isAi: true, rank: won ? 3 : 2, wpm: 80, accuracy: 97, time: 13),
    ],
    playerRank: won ? 1 : 3,
    wpm: 88,
    rawWpm: 92,
    accuracy: 100,
    time: 12.9,
    maxCombo: 60,
    errors: 0,
    chars: text.length,
    nitroUses: 2,
    perfectWords: 9,
    powerupsUsed: 1,
    pitPerfect: true,
    photoFinish: false,
    timeUp: false,
    suspicious: false,
    intervals: List.filled(80, 170),
    samples: const [],
    charStats: const {'e': [12, 0, 2000]},
    typingMs: t - 170 - 600 + 1200,
    keys: withLog ? e.keyLog() : const [],
    wordStats: const {'quick': [0]},
    extra: const {},
  );
}

RaceOutcome _outcome({bool levelUp = true}) {
  final o = RaceOutcome();
  o.coins = 320;
  o.xp = 240;
  o.gems = 2;
  o.rpDelta = 18;
  o.oldLevel = 7;
  o.newLevel = levelUp ? 8 : 7;
  o.records.addAll(const ['best_wpm', 'combo_max']);
  o.tierUp = true;
  o.tierBefore = 'فضي';
  o.tierAfter = 'ذهبي';
  return o;
}

Future<void> _pump(WidgetTester t, Widget child, {Size size = const Size(360, 800), double textScale = 1.3, bool reduced = false}) async {
  final c = await testContainer(t);
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  if (reduced) {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildTheme(),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(textDirection: TextDirection.rtl, child: inner ?? const SizedBox()),
      ),
      home: child,
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('a win lays out on a small phone at 1.3x with the celebration running', (t) async {
    await _pump(t, ResultScreen(result: _result(), outcome: _outcome()));
    expect(find.byType(ResultBanner), findsOneWidget);
    expect(find.text('فوز!'), findsOneWidget);
    expect(find.textContaining('سلسلة الجولات'), findsNothing); // chain 0 is not claimed
    expect(find.byType(ListView), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'a 360x800 phone at 1.3x must not overflow');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the same win with the OS asking for reduced motion', (t) async {
    await _pump(t, ResultScreen(result: _result(), outcome: _outcome()), reduced: true);
    expect(find.text('فوز!'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a loss still lays out and shows no win ceremony', (t) async {
    await _pump(t, ResultScreen(result: _result(won: false), outcome: _outcome(levelUp: false)));
    expect(find.text('فوز!'), findsNothing);
    expect(find.textContaining('المركز 3 من 3'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a large phone with normal text stays intact too', (t) async {
    await _pump(t, ResultScreen(result: _result(), outcome: _outcome()), size: const Size(412, 915), textScale: 1.0);
    expect(find.text('فوز!'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the whole page keeps rendering through the entrance and beyond', (t) async {
    await _pump(t, ResultScreen(result: _result(), outcome: _outcome()));
    // past every animation: the banner, the staggered blocks, the coin burst, the confetti
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    expect(find.text('فوز!'), findsOneWidget);
    // and the reward row is still findable, i.e. nothing was covered or dropped on the way
    expect(find.byIcon(Icons.monetization_on), findsWidgets);
    await t.pumpWidget(const SizedBox());
  });
}
