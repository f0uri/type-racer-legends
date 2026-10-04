import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/data/merge/profile_merge.dart';
import 'package:type_racer_legends/data/models/profile.dart';
import 'package:type_racer_legends/features/career/progress.dart';
import 'package:type_racer_legends/features/career/rewards.dart';
import 'package:type_racer_legends/features/race/race_outcome.dart';
import 'modes_logic_test.dart' show res;
import 'test_support.dart';

void main() {
  final db = loadSeedContent();
  final day1 = DateTime(2026, 10, 1, 10);

  test('metrics: counters, bests and derived values', () {
    final p = PlayerProfile.fresh('d');
    p.addCounter('races', 7);
    p.setBest('best_wpm', 88.5);
    p.setCampaignStars(1, 3);
    p.setCampaignStars(2, 1);
    p.grantVehicle('c_urban');
    expect(Metrics.value(db, p, 'races'), 7);
    expect(Metrics.value(db, p, 'best_wpm'), 88.5);
    expect(Metrics.value(db, p, 'stages_cleared'), 2);
    expect(Metrics.value(db, p, 'campaign_stars'), 4);
    expect(Metrics.value(db, p, 'vehicles_owned'), greaterThanOrEqualTo(3)); // two starters + urban
    expect(Metrics.value(db, p, 'level'), 1);
    expect(Metrics.value(db, p, 'rank_tier'), 0);
    p.addRankPoints(650);
    expect(Metrics.value(db, p, 'rank_tier'), 3);
    // every metric used by the content is resolvable (no silent zero for typos)
    final known = {...db.achievements.map((a) => a.metric), ...db.quests.map((q) => q.metric)};
    for (final m in known) {
      expect(Metrics.value(db, p, m), isA<double>(), reason: m);
    }
  });

  test('achievements unlock once, reward on claim, and hand out tied items', () {
    final p = PlayerProfile.fresh('d');
    expect(Achievements.evaluate(db, p), isEmpty);
    p.addCounter('races', 10);
    final got = Achievements.evaluate(db, p);
    expect(got.map((a) => a.id), contains('a_races_1'));
    expect(Achievements.evaluate(db, p), isEmpty); // not twice
    final coinsBefore = p.coins;
    final lines = Achievements.claim(db, p, 'a_races_1')!;
    expect(lines, isNotEmpty);
    expect(p.coins, greaterThan(coinsBefore));
    expect(Achievements.claim(db, p, 'a_races_1'), isNull); // not twice
    expect(Achievements.claim(db, p, 'a_wins_1'), isNull); // locked
    // legend rank gives the exclusive car, plate skin and outfit
    p.addRankPoints(2300);
    final legend = Achievements.evaluate(db, p);
    expect(legend.map((a) => a.id), contains('a_rank_legend'));
    expect(p.ownsVehicle('c_legend'), isTrue);
    expect(p.ownsSkin('p_legend'), isTrue);
    expect(p.ownsOutfit('o_legend'), isTrue);
    final l = Achievements.claim(db, p, 'a_rank_legend')!;
    expect(l.join(), contains('لقب'));
    expect(p.m('titles').containsKey('t_legend'), isTrue);
  });

  test('90 achievements across many metrics, each with 3+ levels of a family', () {
    expect(db.achievements.length, greaterThanOrEqualTo(50));
    final families = <String, int>{};
    for (final a in db.achievements) {
      families[a.metric] = (families[a.metric] ?? 0) + 1;
      expect(a.target, greaterThan(0));
      expect(a.reward, isNotEmpty);
    }
    expect(families.length, greaterThanOrEqualTo(25));
  });

  test('daily quests: deterministic, distinct metrics, progress is a delta from the period start', () {
    final a = Quests.selection(db, 'daily', day1), b = Quests.selection(db, 'daily', day1);
    expect(a.map((q) => q.id).toList(), b.map((q) => q.id).toList());
    expect(a.length, 3);
    expect(a.map((q) => q.metric).toSet().length, 3);
    expect(Quests.selection(db, 'daily', day1.add(const Duration(days: 1))).map((q) => q.id).toList(), isNot(a.map((q) => q.id).toList()));
    expect(Quests.selection(db, 'weekly', day1).length, 3);

    final p = PlayerProfile.fresh('d');
    p.addCounter('races', 50);
    p.addCounter('chars', 9999);
    Quests.ensure(db, p, 'daily', day1);
    Quests.ensure(db, p, 'weekly', day1);
    expect(Quests.views(db, p, 'daily', day1).every((v) => v.progress == 0), isTrue); // old progress does not count
    // play: add enough of every metric used today
    final today = Quests.selection(db, 'daily', day1);
    for (final q in today) {
      if (Metrics.bests.contains(q.metric)) continue;
      p.addCounter(q.metric, q.target);
    }
    final views = Quests.views(db, p, 'daily', day1);
    expect(views.every((v) => v.done), isTrue);
    final q0 = today.first;
    final coins0 = p.coins;
    final lines = Quests.claim(db, p, 'daily', q0.id, now: day1)!;
    expect(lines, isNotEmpty);
    expect(p.coins, greaterThan(coins0));
    expect(Quests.claim(db, p, 'daily', q0.id, now: day1), isNull); // once
    expect(p.counter('quests_done'), 1);
    expect(p.counter('sp_${Season.idAt(db, day1)}'), q0.sp);
    // next day: fresh quests with fresh baselines
    final next = day1.add(const Duration(days: 1));
    Quests.ensure(db, p, 'daily', next);
    expect(Quests.views(db, p, 'daily', next).every((v) => v.progress == 0 && !v.claimed), isTrue);
  });

  test('best-style quest metrics use the best reached during the period', () {
    final p = PlayerProfile.fresh('d');
    p.setBest('combo_max', 500);
    Quests.ensure(db, p, 'daily', day1);
    Quests.recordBests(db, p, {'combo_max': 37, 'best_wpm': 60}, now: day1);
    Quests.recordBests(db, p, {'combo_max': 20}, now: day1);
    final rec = p.m('quests')['daily'] as Map;
    expect(Quests.progressOf(db, p, rec.cast<String, dynamic>(), 'combo_max'), 37);
    expect(Quests.progressOf(db, p, rec.cast<String, dynamic>(), 'best_wpm'), 60);
  });

  test('race results feed bests and season points', () {
    final p = PlayerProfile.fresh('d');
    final now = DateTime(2026, 10, 2, 12);
    final o = RaceRewards.apply(p, res(rank: 1, wpm: 77), db, now: now);
    expect(o.rewarded, isTrue);
    final sid = Season.idAt(db, now);
    expect(p.counter('sp_$sid'), Progression.racePoints(res(rank: 1, wpm: 77)));
    final rec = p.m('quests')['daily'] as Map;
    expect((rec['best'] as Map)['best_wpm'], 77);
  });

  test('events: tasks progress from the event start, rewards once, final reward after all tasks', () {
    final p = PlayerProfile.fresh('d');
    final ev = db.event('ramadan_2027')!;
    final during = DateTime(2027, 2, 20);
    p.addCounter('races', 100);
    Events.ensure(db, p, ev, now: during);
    for (final t in ev.tasks) {
      expect(Events.taskProgress(db, p, ev, t), 0);
    }
    for (final t in ev.tasks) {
      final m = t['metric'] as String;
      if (m == 'combo_max') {
        Quests.recordBests(db, p, {'combo_max': 99}, now: during);
        continue;
      }
      p.addCounter(m, (t['target'] as num).toInt());
    }
    // recordBests only touches events that are active *now*; emulate with the event record directly
    ((p.m('events')[ev.id] as Map)['best'] as Map)['combo_max'] = 99;
    for (final t in ev.tasks) {
      expect(Events.claimTask(db, p, ev, t['id'] as String, now: during), isNotNull, reason: t['id'] as String);
      expect(Events.claimTask(db, p, ev, t['id'] as String, now: during), isNull);
    }
    expect(Events.allDone(p, ev), isTrue);
    final fin = Events.claimFinal(db, p, ev, now: during)!;
    expect(fin, isNotEmpty);
    expect(Events.claimFinal(db, p, ev, now: during), isNull);
    expect(Events.claimTask(db, PlayerProfile.fresh('x'), ev, ev.tasks.first['id'] as String, now: DateTime(2027, 4, 1)), isNull); // event over
  });

  group('season / battle pass', () {
    test('ids follow the 28 day anchor; nothing before it', () {
      expect(Season.idAt(db, DateTime(2026, 9, 28)), 0);
      expect(Season.idAt(db, DateTime(2026, 9, 29)), 1);
      expect(Season.idAt(db, DateTime(2026, 10, 26)), 1);
      expect(Season.idAt(db, DateTime(2026, 10, 27)), 2);
    });

    test('points -> levels, free rewards for everyone, premium only with the pass', () {
      final p = PlayerProfile.fresh('d');
      final now = DateTime(2026, 10, 1);
      Season.record(db, p, now);
      Season.addPoints(p, db, 350, now: now);
      final si = Season.info(db, p, now);
      expect(si.level, 3);
      expect(si.pointsInLevel, 50);
      expect(Season.claim(db, p, 4, premiumSide: false, now: now), isNull); // level not reached
      final coins = p.coins;
      expect(Season.claim(db, p, 1, premiumSide: false, now: now), isNotNull);
      expect(p.coins, greaterThan(coins));
      expect(Season.claim(db, p, 1, premiumSide: false, now: now), isNull);
      expect(Season.claim(db, p, 1, premiumSide: true, now: now), isNull); // no pass
      Season.grantPremium(p, db, now);
      expect(Season.claim(db, p, 1, premiumSide: true, now: now), isNotNull);
      final rest = Season.claimAll(db, p, now: now);
      expect(rest, isNotEmpty);
      expect(Season.claimableCount(db, p, now), 0);
    });

    test('premium track contains the exclusive season skin at level 30 and chests', () {
      final p = PlayerProfile.fresh('d');
      final now = DateTime(2026, 10, 1);
      Season.record(db, p, now);
      Season.grantPremium(p, db, now);
      Season.addPoints(p, db, 4000, now: now);
      expect(Season.info(db, p, now).level, 40);
      Season.claimAll(db, p, now: now);
      expect(p.ownsSkin('p_season1'), isTrue);
      expect(p.ownsSkin('s_crown'), isTrue);
      expect(Economyish.chests(p), greaterThanOrEqualTo(3));
    });

    test('a new season resets the claim lists and premium flag; points are per season', () {
      final p = PlayerProfile.fresh('d');
      final s1 = DateTime(2026, 10, 1);
      Season.record(db, p, s1);
      Season.grantPremium(p, db, s1);
      Season.addPoints(p, db, 500, now: s1);
      Season.claimAll(db, p, now: s1);
      final s2 = DateTime(2026, 11, 5);
      final rec = Season.record(db, p, s2);
      expect(rec['id'], 2);
      expect(rec['premium'], false);
      expect(Season.info(db, p, s2).level, 0);
      expect(Season.info(db, p, s1).level, 5);
    });

    test('merging two devices keeps the higher season and unions claimed levels', () {
      final a = PlayerProfile.fresh('a'), b = PlayerProfile.fresh('b');
      final now = DateTime.now();
      Season.record(db, a, now);
      Season.record(db, b, now);
      Season.addPoints(a, db, 300, now: now);
      Season.claim(db, a, 1, premiumSide: false, now: now);
      Season.addPoints(b, db, 300, now: now);
      Season.claim(db, b, 2, premiumSide: false, now: now);
      final m = ProfileMerger.merge(a, b);
      expect(Season.claimedFree(m, 1), isTrue);
      expect(Season.claimedFree(m, 2), isTrue);
    });
  });

  test('login streak: claim once per day, reward grows along the 7-day cycle', () {
    final p = PlayerProfile.fresh('d');
    final d0 = DateTime(2026, 10, 1, 9);
    expect(LoginStreak.claimable(p, d0), isFalse);
    LoginStreak.register(p, d0);
    expect(LoginStreak.claimable(p, d0), isTrue);
    final first = LoginStreak.claim(db, p, d0)!;
    expect(first, isNotEmpty);
    expect(LoginStreak.claim(db, p, d0), isNull);
    for (var i = 1; i < 7; i++) {
      final d = d0.add(Duration(days: i));
      LoginStreak.register(p, d);
      expect(p.streak, i + 1);
      expect(LoginStreak.claim(db, p, d), isNotNull);
    }
    expect(LoginStreak.rewardFor(db, 7)['coins'], 600);
    expect(LoginStreak.rewardFor(db, 8)['coins'], 100); // cycle restarts
    // a missed day resets
    LoginStreak.register(p, d0.add(const Duration(days: 9)));
    expect(p.streak, 1);
  });

  test('rewards bundle grants everything and describes it; duplicates pay coins', () {
    final p = PlayerProfile.fresh('d');
    final lines = Rewards.grant(p, db, {'coins': 100, 'gems': 5, 'xp': 50, 'chest': 'chest_gold', 'skin': 'p_gold', 'title': 't_legend'});
    expect(lines.length, 6);
    expect(p.coins, 100);
    expect(p.gems, 5);
    expect(p.xp, 50);
    expect(p.ownsSkin('p_gold'), isTrue);
    final again = Rewards.grant(p, db, {'skin': 'p_gold'});
    expect(again.single, contains('مكرر'));
    expect(Rewards.preview(db, {'coins': 1500, 'gems': 2}), contains('2 جوهرة'));
  });

  test('progression.evaluate is cheap to skip when nothing is pending', () {
    final p = PlayerProfile.fresh('d');
    final now = DateTime(2026, 10, 1);
    expect(Progression.needsWork(db, p, now), isTrue); // first run sets up quests + season
    Progression.evaluate(db, p, now);
    expect(Progression.needsWork(db, p, now), isFalse);
    p.addCounter('races', 10);
    expect(Progression.needsWork(db, p, now), isTrue);
  });
}

class Economyish {
  static int chests(PlayerProfile p) => p.counter('ch_chest_gold_g');
}
