import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/providers.dart';
import 'package:type_racer_legends/core/services/audio_service.dart';
import 'package:type_racer_legends/core/theme/app_theme.dart';
import 'package:type_racer_legends/data/local/local_store.dart';
import 'package:type_racer_legends/features/race/race_builder.dart';
import 'package:type_racer_legends/features/race/ui/race_screen.dart';
import 'package:type_racer_legends/features/race/ui/result_screen.dart';
import 'test_support.dart';

void main() {
  testWidgets('a full race runs from lobby to results without errors', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('trl_race');
      return LocalStore.forTest(dir.path);
    });
    final db = loadSeedContent();
    final audio = AudioService()..available = false;
    final container = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store!),
      initialContentProvider.overrideWithValue(db),
      audioProvider.overrideWithValue(audio),
    ]);
    addTearDown(container.dispose);
    final builder = RaceBuilder(db, container.read(profileProvider), container.read(settingsProvider), Random(3));
    final cfg = builder.quick(opponentsCount: 4, len: LengthPref.short, mod: 'none');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(), home: RaceScreen(config: cfg, rebuild: () => builder.quick())),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ابدأ السباق'), findsOneWidget);
    expect(find.text('AI'), findsWidgets);
    await tester.tap(find.text('ابدأ السباق'));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final sess = RaceScreen.debugSession!;
    var mistakes = 0;
    for (var frame = 0; frame < 6000 && find.byType(ResultScreen).evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (frame % 3 != 0 || sess.player.finished) continue;
      final ch = sess.challenge != null ? sess.challenge!.word[sess.challenge!.typed] : (sess.engine.pos < sess.engine.length ? sess.engine.text[sess.engine.pos] : ' ');
      final tf = find.byType(TextField);
      if (tf.evaluate().isEmpty) continue;
      if (sess.challenge == null && frame % 97 == 0 && mistakes < 3) {
        mistakes++;
        await tester.enterText(tf, '\u200B\u200B#');
        await tester.pump(const Duration(milliseconds: 16));
        await tester.enterText(tf, '\u200B');
      } else {
        await tester.enterText(tf, '\u200B\u200B$ch');
      }
    }
    // ignore: avoid_print
    print('finished=${sess.player.finished} mistakes=$mistakes');
    await tester.pump(const Duration(seconds: 12)); // photo-finish replay / celebration
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(find.text('الترتيب'), findsOneWidget);
    // the page must not claim real players
    expect(find.textContaining('ذكاء اصطناعي'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
