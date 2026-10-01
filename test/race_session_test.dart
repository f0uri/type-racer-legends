import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/data/models/content_models.dart';
import 'package:type_racer_legends/features/ai/ai_driver.dart';
import 'package:type_racer_legends/features/race/engine/race_models.dart';
import 'package:type_racer_legends/features/race/engine/race_session.dart';
import 'package:type_racer_legends/features/race/engine/typing_engine.dart';

const longText = 'the quick brown fox jumps over the lazy dog and keeps running across the wide open field until the sun goes down behind the hills';

TextItem textItem(String t) => TextItem({'id': 't', 't': t, 'cat': 'x', 'topic': 'x', 'lang': 'en', 'diff': 1, 'len': t.length});

AiSpec ai(String id, double wpm) => AiSpec(id: id, name: id, cc: 'US', persona: 'balanced', baseWpm: wpm, vehicleId: 'c_sprout', paintId: 'p_red');

RaceSession make({List<AiSpec> opp = const [], RaceRules rules = RaceRules.full, String text = longText, int seed = 1, List<GhostSpec> ghosts = const []}) {
  final cfg = RaceConfig(modeId: 'quick', title: 'x', text: textItem(text), opponents: opp, rules: rules, ghosts: ghosts);
  final s = RaceSession(cfg, TypingEngine(text), rnd: Random(seed));
  s.start();
  return s;
}

/// Plays the race typing at [wpm]; answers challenges correctly if [answer].
void play(RaceSession s, double wpm, {double errorRate = 0, bool answer = true, Random? rnd}) {
  final r = rnd ?? Random(5);
  final cps = wpm * 5 / 60;
  var acc = 0.0;
  var guard = 0;
  while (!s.over && guard++ < 200000) {
    const dt = 1 / 60;
    s.update(dt);
    acc += cps * dt;
    while (acc >= 1 && !s.over) {
      acc -= 1;
      final c = s.challenge;
      if (c != null) {
        if (answer) {
          s.onChar(c.word[c.typed]);
        } else {
          s.onChar('#');
        }
        continue;
      }
      if (errorRate > 0 && r.nextDouble() < errorRate) {
        s.onChar('#');
        s.onBackspace();
      }
      final n = s.engine.nextChar;
      if (n != null) s.onChar(n);
    }
  }
}

void main() {
  test('player alone finishes first and result is sane', () {
    final s = make();
    play(s, 60);
    final r = s.buildResult();
    expect(r.won, isTrue);
    expect(r.accuracy, 100);
    expect(r.wpm, inInclusiveRange(55, 75)); // bonuses may finish a little early
    expect(r.chars, greaterThan(105));
  });

  test('fast player beats slow AI, slow player loses to fast AI', () {
    final a = make(opp: [ai('a', 35), ai('b', 40)]);
    play(a, 80);
    expect(a.buildResult().playerRank, 1);
    final b = make(opp: [ai('a', 95), ai('b', 90)], seed: 3);
    play(b, 25);
    final rb = b.buildResult();
    expect(rb.playerRank, greaterThan(1));
    expect(rb.standings.first.isPlayer, isFalse);
  });

  test('nitro fills from clean typing and errors halve the meter', () {
    final s = make(rules: const RaceRules(powerups: false, pit: false));
    for (var i = 0; i < 20; i++) {
      s.update(0.05);
      s.onChar(s.engine.nextChar!);
    }
    final before = s.nitroMeter;
    expect(before, greaterThan(10));
    s.onChar('#');
    expect(s.nitroMeter, closeTo(before / 2, 1e-9));
  });

  test('nitro activates when the meter is full and counts uses', () {
    final s = make(text: List.filled(25, 'abcd efgh').join(' '), rules: const RaceRules(powerups: false, pit: false));
    var t = 0;
    while (!s.nitroActive && s.engine.nextChar != null && t < 400) {
      s.update(0.05);
      s.onChar(s.engine.nextChar!);
      t++;
    }
    expect(s.nitroActive, isTrue);
    expect(s.nitroUses, 1);
    expect(s.drainEvents().any((e) => e.type == RaceEventType.nitroStart), isTrue);
  });

  test('errors brake the player (unless shielded) but not in pure mode', () {
    final s = make();
    s.update(0.1);
    s.onChar('#');
    expect(s.brake, greaterThan(0));
    final p = make(rules: RaceRules.purePlay);
    p.update(0.1);
    p.onChar('#');
    expect(p.brake, 0);
    final sh = make();
    sh.player.shielded = true;
    sh.onChar('#');
    expect(sh.brake, 0);
    expect(sh.player.shielded, isFalse);
  });

  test('pit stop and power-up challenges appear and resolve', () {
    final s = make();
    final seen = <RaceEventType>{};
    play(s, 70);
    // replay with event inspection
    final s2 = make(seed: 2);
    var guard = 0;
    while (!s2.over && guard++ < 100000) {
      s2.update(1 / 60);
      for (final e in s2.drainEvents()) {
        seen.add(e.type);
      }
      final c = s2.challenge;
      if (c != null) {
        s2.onChar(c.word[c.typed]);
      } else if (s2.engine.nextChar != null && guard % 6 == 0) {
        s2.onChar(s2.engine.nextChar!);
      }
    }
    expect(seen, contains(RaceEventType.pitPrompt));
    expect(seen, contains(RaceEventType.pitSuccess));
    expect(seen, contains(RaceEventType.powerSuccess));
    final r = s2.buildResult();
    expect(r.pitPerfect, isTrue);
    expect(r.powerupsUsed, greaterThan(0));
  });

  test('failing the pit stop loses ground', () {
    final s = make();
    var guard = 0;
    while (s.challenge == null || !s.challenge!.isPit) {
      s.update(1 / 60);
      if (guard++ % 5 == 0 && s.challenge == null && s.engine.nextChar != null) s.onChar(s.engine.nextChar!);
      if (guard > 60000) fail('no pit');
    }
    final before = s.player.eff;
    s.onChar('#');
    expect(s.challenge, isNull);
    expect(s.player.eff, lessThan(before));
    expect(s.pitPerfect, isFalse);
  });

  test('EMP stuns an opponent', () {
    final s = make(opp: [ai('a', 40)]);
    s.challenge = Challenge(ChallengeKind.emp, 'EMP', 5);
    for (final c in 'emp'.split('')) {
      s.onChar(c); // case-insensitive
    }
    expect(s.drivers['a']!.stunLeft, greaterThan(2));
    expect(s.powerupsUsed, 1);
  });

  test('challenge timeout fails it and resumes the race', () {
    final s = make();
    s.challenge = Challenge(ChallengeKind.turbo, 'TURBO', 1);
    for (var i = 0; i < 70; i++) {
      s.update(1 / 60);
    }
    expect(s.challenge, isNull);
    expect(s.powerupsUsed, 0);
  });

  test('ghosts take part and are ranked', () {
    final s = make(ghosts: const [GhostSpec(name: 'Ghost', wpm: 30, personal: true)]);
    play(s, 70);
    final r = s.buildResult();
    expect(r.standings.length, 2);
    expect(r.standings.any((e) => e.isGhost), isTrue);
    expect(r.playerRank, 1);
  });

  test('timed test ends at the limit', () {
    final text = List.filled(400, 'word').join(' ');
    final cfg = RaceConfig(modeId: 'official', title: 't', text: textItem(text), rules: RaceRules.purePlay, timeLimitMs: 10000);
    final s = RaceSession(cfg, TypingEngine(text), rnd: Random(1))..start();
    play(s, 60);
    final r = s.buildResult();
    expect(r.timeUp, isTrue);
    expect(r.wpm, closeTo(60, 6));
  });

  test('pure mode finishes exactly when typing is done (no bonuses)', () {
    final s = make(rules: RaceRules.purePlay);
    play(s, 60);
    final r = s.buildResult();
    expect(r.chars, longText.length);
    expect(r.wpm, closeTo(60, 4));
  });

  test('a typo really blocks the perfect-word bonus (regression: it used to always fire)', () {
    final s = make(text: 'alpha beta gamma delta epsilon', rules: const RaceRules(powerups: false, pit: false));
    // warm up slowly so a fast, clean word counts as a genuine burst
    for (final ch in 'alpha ') {
      s.update(0.35);
      s.onChar(ch);
    }
    for (final ch in 'beta ') {
      s.update(0.05);
      s.onChar(ch); // fast + clean -> perfect word
    }
    expect(s.perfectWords, 1, reason: 'a fast clean word earns the bonus');
    // the same fast word, now with a typo that is fixed immediately
    for (final ch in 'ga') {
      s.update(0.05);
      s.onChar(ch);
    }
    s.update(0.05);
    s.onChar('x');
    s.onBackspace();
    for (final ch in 'mma ') {
      s.update(0.05);
      s.onChar(ch);
    }
    expect(s.perfectWords, 1, reason: 'the typo must cancel the bonus (it used to fire anyway)');
  });

  test('the pack keeps racing after the player crosses the line (photo finish window)', () {
    final s = make(opp: [ai('rival', 60)]);
    var acc = 0.0, guard = 0;
    while (!s.player.finished && guard++ < 200000) {
      const dt = 1 / 60;
      s.update(dt);
      acc += 60 * 5 / 60 * dt;
      while (acc >= 1) {
        acc -= 1;
        final n = s.engine.nextChar;
        if (n != null) s.onChar(n);
      }
    }
    expect(s.player.finished, isTrue);
    expect(s.over, isFalse, reason: 'the race is not ranked the instant the player finishes');
    expect(s.postFinishT, 0);
    for (var i = 0; i < 60; i++) {
      s.update(1 / 60); // ~1 s: the window is still open
    }
    expect(s.over, isFalse);
    for (var i = 0; i < 60; i++) {
      s.update(1 / 60);
    }
    expect(s.over, isTrue, reason: 'the post-finish window closes after ~1.6 s');
    expect(s.postFinishT, greaterThanOrEqualTo(RaceSession.postFinishWindow));
  });

  test('results carry the active typing span used by anti-cheat', () {
    final s = make();
    play(s, 60);
    final r = s.buildResult();
    expect(r.typingMs, greaterThan(0));
    expect(r.typingMs, lessThanOrEqualTo((r.time * 1000).round() + 1));
  });
}
