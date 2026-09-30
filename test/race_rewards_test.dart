import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/data/models/profile.dart';
import 'package:type_racer_legends/features/race/engine/race_models.dart';
import 'package:type_racer_legends/features/race/race_outcome.dart';
import 'package:type_racer_legends/data/models/content_models.dart';
import 'test_support.dart';

RaceResult _res({double wpm = 60, double acc = 97, int rank = 1, int n = 5, bool rewards = true, bool ranked = true, int chars = 120, bool suspicious = false, double risk = 1}) {
  final cfg = RaceConfig(
    modeId: 'quick',
    title: 't',
    text: TextItem({'id': 'x', 't': 'a' * chars, 'cat': 'sentence', 'lang': 'en', 'diff': 2, 'len': chars}),
    biomeId: 'city',
    mod: 'none',
    opponents: const [],
    ranked: ranked,
    rewards: rewards,
    riskMul: risk,
  );
  return RaceResult(
    config: cfg,
    standings: List.generate(n, (i) => RacerResult(id: 'r$i', rank: i + 1, name: i + 1 == rank ? 'me' : 'ai$i', cc: 'MA', wpm: 50, time: 20, isPlayer: i + 1 == rank, isAi: i + 1 != rank, accuracy: 95)),
    playerRank: rank,
    wpm: wpm,
    rawWpm: wpm,
    accuracy: acc,
    time: 20,
    maxCombo: 25,
    errors: 2,
    chars: chars,
    nitroUses: 1,
    perfectWords: 2,
    powerupsUsed: 1,
    pitPerfect: true,
    photoFinish: false,
    timeUp: false,
    suspicious: suspicious,
    intervals: const [],
    samples: const [],
    charStats: const {},
    wordStats: const {},
  );
}

void main() {
  final db = loadSeedContent();

  test('winning pays more than last place and updates counters / bests', () {
    final a = PlayerProfile.fresh('d1'), b = PlayerProfile.fresh('d2');
    b.addRankPoints(50);
    final w = RaceRewards.apply(a, _res(rank: 1), db);
    final l = RaceRewards.apply(b, _res(rank: 5), db);
    expect(w.coins, greaterThan(l.coins));
    expect(w.rpDelta, greaterThan(0));
    expect(l.rpDelta, lessThan(0));
    expect(a.counter('wins'), 1);
    expect(b.counter('wins'), 0);
    expect(a.counter('races'), 1);
    expect(a.best('best_wpm'), 60);
    expect(a.counter('nitro_count'), 1);
    expect(w.records, contains('best_wpm'));
    expect(a.coins, w.coins);
    expect(a.xp, w.xp);
  });

  test('risk multiplier doubles the coin reward', () {
    final a = PlayerProfile.fresh('d1'), b = PlayerProfile.fresh('d2');
    final n = RaceRewards.apply(a, _res(), db);
    final r = RaceRewards.apply(b, _res(risk: 2), db);
    expect(r.coins, closeTo(n.coins * 2, 2));
  });

  test('daily cap falls back to the guaranteed minimum', () {
    final p = PlayerProfile.fresh('d1');
    final now = DateTime(2026, 9, 30, 12);
    final cap = (db.econ('race')['dailyCoinCap'] as num).toInt();
    final min = (db.econ('race')['minGuaranteed'] as num).toInt();
    p.addCounter('dc_20260930', cap);
    final o = RaceRewards.apply(p, _res(), db, now: now);
    expect(o.capped, isTrue);
    expect(o.coins, min);
    // the next day the cap resets
    final o2 = RaceRewards.apply(p, _res(), db, now: DateTime(2026, 10, 1, 9));
    expect(o2.capped, isFalse);
    expect(o2.coins, greaterThan(min));
  });

  test('suspicious or unrewarded races never pay and never set records', () {
    final p = PlayerProfile.fresh('d1');
    final o = RaceRewards.apply(p, _res(suspicious: true, wpm: 300), db);
    expect(o.rewarded, isFalse);
    expect(p.coins, 0);
    expect(p.best('best_wpm'), 0);
    final o2 = RaceRewards.apply(p, _res(rewards: false), db);
    expect(o2.coins, 0);
  });

  test('ranked points never change for practice races and tier-ups are detected', () {
    final p = PlayerProfile.fresh('d1');
    RaceRewards.apply(p, _res(ranked: false), db);
    expect(p.rankPoints, 0);
    p.addRankPoints(90);
    final o = RaceRewards.apply(p, _res(rank: 1), db);
    expect(o.tierUp, isTrue);
    expect(o.tierAfter, 'silver');
  });

  test('level-ups are reported', () {
    final p = PlayerProfile.fresh('d1');
    p.addXp(119);
    final o = RaceRewards.apply(p, _res(), db);
    expect(o.levelUp, isTrue);
  });
}
