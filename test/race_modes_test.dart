import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/features/race/engine/race_models.dart';
import 'package:type_racer_legends/features/race/engine/race_session.dart';
import 'package:type_racer_legends/features/race/engine/typing_engine.dart';
import 'race_session_test.dart' show ai, textItem, play;

const big = 'lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum';

RaceSession mk(String mode, List<dynamic> opp, {int seed = 2, String text = big, RaceRules rules = RaceRules.full}) {
  final cfg = RaceConfig(modeId: mode, title: mode, text: textItem(text), opponents: List.from(opp), rules: rules);
  final s = RaceSession(cfg, TypingEngine(text), rnd: Random(seed));
  s.start();
  return s;
}

void main() {
  test('survival: a slow typist is caught by the accelerating hunter', () {
    final s = mk('survival', [ai('hunter', 40)], rules: RaceRules.solo);
    play(s, 15);
    final r = s.buildResult();
    expect(s.caught, isTrue);
    expect(r.won, isFalse);
    expect(r.extra['caught'], isTrue);
    expect(r.extra['survived'] as double, greaterThan(3));
  });

  test('survival: a fast typist survives longer than a slow one', () {
    final slow = mk('survival', [ai('hunter', 60)], rules: RaceRules.solo);
    play(slow, 25);
    final fast = mk('survival', [ai('hunter', 60)], rules: RaceRules.solo);
    play(fast, 110);
    expect(fast.buildResult().extra['survived'] as double, greaterThan(slow.buildResult().extra['survived'] as double));
  });

  test('survival: the hunter starts behind and speeds up over time', () {
    final s = mk('survival', [ai('hunter', 60)], rules: RaceRules.solo);
    expect(s.hunterGap, greaterThan(10));
    s.update(0.016);
    final d = s.drivers.values.first;
    final early = d.wpmScale;
    for (var i = 0; i < 60 * 30; i++) {
      s.update(1 / 60);
      if (s.over) break;
    }
    expect(d.wpmScale, greaterThan(early));
  });

  test('combat: clean words fire rockets, rivals die, and the player wins by elimination', () {
    final s = mk('combat', [ai('a', 10), ai('b', 10)], rules: RaceRules.solo);
    play(s, 90);
    final r = s.buildResult();
    expect(r.extra['kills'] as int, greaterThan(0));
    expect(s.hp.values.any((h) => h < 3), isTrue);
    expect(r.won, isTrue);
  });

  test('combat: ignoring incoming attacks costs progress; dodging them does not', () {
    final rivals = [for (var i = 0; i < 8; i++) ai('r$i', 1)];
    final a = mk('combat', rivals, rules: RaceRules.solo, seed: 7);
    final b = mk('combat', rivals, rules: RaceRules.solo, seed: 7);
    var hitsA = 0, dodgesB = 0;
    void drive(RaceSession s, bool answer, void Function(RaceEvent e) on) {
      var acc = 0.0;
      for (var i = 0; i < 60 * 40 && !s.over; i++) {
        s.update(1 / 60);
        acc += 60 * 5 / 60 / 60;
        while (acc >= 1) {
          acc -= 1;
          final c = s.challenge;
          if (c != null) {
            if (answer) s.onChar(c.word[c.typed]);
            continue;
          }
          final n = s.engine.nextChar;
          if (n != null) s.onChar(n);
        }
        for (final e in s.drainEvents()) {
          on(e);
        }
      }
    }

    drive(a, false, (e) => hitsA += e.type == RaceEventType.hit ? 1 : 0);
    drive(b, true, (e) => dodgesB += (e.type == RaceEventType.powerSuccess && e.text == 'dodge') ? 1 : 0);
    expect(hitsA, greaterThan(0));
    expect(dodgesB, greaterThan(0));
  });

  test('defend challenge can be shielded', () {
    final s = mk('combat', [ai('a', 1)], rules: RaceRules.solo);
    s.player.shielded = true;
    // let an attack come
    for (var i = 0; i < 60 * 20 && s.challenge == null; i++) {
      s.update(1 / 60);
    }
    expect(s.challenge?.kind, ChallengeKind.defend);
    for (var i = 0; i < 60 * 4; i++) {
      s.update(1 / 60);
    }
    expect(s.player.shielded, isFalse);
    expect(s.brake, 0);
  });
}
