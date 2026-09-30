import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/features/ai/ai_driver.dart';

AiSpec spec(double wpm, [String persona = 'balanced']) => AiSpec(id: 'a', name: 'A', cc: 'US', persona: persona, baseWpm: wpm, vehicleId: 'c_sprout', paintId: 'p_red');

double finishTime(AiDriver d, {double playerWpm = 50, int total = 300}) {
  var t = 0.0;
  while (!d.finished && t < 600) {
    t += 1 / 30;
    d.update(1 / 30, playerFrac: min(1, t * playerWpm * 5 / 60 / total), playerWpm: playerWpm);
  }
  return t;
}

void main() {
  test('AI average speed is close to its base WPM with natural variance', () {
    final times = <double>[];
    for (var seed = 0; seed < 40; seed++) {
      final d = AiDriver(spec(60), 300, Random(seed));
      times.add(finishTime(d, playerWpm: 60));
    }
    final mean = times.reduce((a, b) => a + b) / times.length;
    final expected = 300 / 5 / 60 * 60; // 60s at 60 wpm
    expect(mean, inInclusiveRange(expected * 0.85, expected * 1.25));
    final sd = sqrt(times.map((t) => pow(t - mean, 2)).reduce((a, b) => a + b) / times.length);
    expect(sd, greaterThan(0.5)); // not robotic
  });

  test('a clearly faster player usually beats the AI, a clearly slower one usually loses', () {
    int wins(double playerWpm) {
      var w = 0;
      for (var seed = 0; seed < 60; seed++) {
        final d = AiDriver(spec(50), 300, Random(seed));
        final pt = 300 / 5 / playerWpm * 60;
        if (pt < finishTime(d, playerWpm: playerWpm)) w++;
      }
      return w;
    }
    expect(wins(65), greaterThan(40));
    expect(wins(35), lessThan(20));
  });

  test('rubber band does not help an idle player', () {
    final d = AiDriver(spec(50), 300, Random(1));
    final t = finishTime(d, playerWpm: 0);
    expect(t, lessThan(300 / 5 / 50 * 60 * 1.3));
  });

  test('stun freezes the AI', () {
    final d = AiDriver(spec(80), 300, Random(2))..stun(2);
    final before = d.pos;
    for (var i = 0; i < 30; i++) {
      d.update(1 / 30, playerFrac: 0, playerWpm: 50);
    }
    expect(d.pos, before);
    for (var i = 0; i < 90; i++) {
      d.update(1 / 30, playerFrac: 0, playerWpm: 50);
    }
    expect(d.pos, greaterThan(before));
  });

  test('fatigue persona slows down near the end', () {
    double late(String persona) {
      final d = AiDriver(spec(60, persona), 400, Random(7));
      var t = 0.0;
      while (d.fraction < 0.8 && t < 200) {
        t += 1 / 30;
        d.update(1 / 30, playerFrac: 0.5, playerWpm: 0, rubberEnabled: false);
      }
      return d.fraction;
    }
    expect(late('fatigue'), greaterThan(0.79));
  });

  group('Matchmaker', () {
    test('opponents bracket the player speed', () {
      final w = Matchmaker.opponentWpms(50, 5, Random(3));
      expect(w.length, 5);
      expect(w.reduce(min), lessThan(45));
      expect(w.reduce(max), greaterThan(52));
    });
    test('target uses the last 10 races and has a fallback', () {
      expect(Matchmaker.targetWpm([]), 24);
      expect(Matchmaker.targetWpm(List.filled(15, 40.0)..[0] = 400), 40);
    });
    test('persona distribution includes every personality', () {
      final r = Random(1);
      final seen = {for (var i = 0; i < 200; i++) Matchmaker.randomPersona(r)};
      expect(seen, containsAll(Persona.all));
    });
  });

  test('ghost replays samples and constant ghosts', () {
    final g = GhostDriver.fromSamples('me', [[0, 0], [1, 10], [2, 30]], 100);
    g.update(1.5);
    expect(g.pos, closeTo(20, 1e-9));
    g.update(5);
    expect(g.pos, greaterThan(30));
    final c = GhostDriver.constant('c', 60, 100)..update(10);
    expect(c.pos, closeTo(50, 1e-9));
  });
}
