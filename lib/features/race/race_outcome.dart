import 'dart:math';
import '../../core/util/dates.dart';
import '../../data/models/profile.dart';
import '../career/rank.dart';
import '../content/content_db.dart';
import 'engine/race_models.dart';

class RaceOutcome {
  int coins = 0, gems = 0, xp = 0, rpDelta = 0;
  int oldLevel = 1, newLevel = 1;
  int rpBefore = 0, rpAfter = 0;
  bool capped = false, rewarded = true, newGhost = false, tierUp = false, tierDown = false;
  String? tierBefore, tierAfter;
  final List<String> records = []; // best_wpm, best_acc, combo_max
  String? note;
  bool get levelUp => newLevel > oldLevel;
}

/// Rewards and progress bookkeeping for a finished race. Pure: operates on a profile copy handed in by the controller.
class RaceRewards {
  /// Minimum typed characters for a race to count towards records and history.
  static const minCharsForStats = 30;

  static double rankMultiplier(ContentDb db, int rank) {
    final list = ((db.econ('race')['rankMul']) as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [1.0, 0.7, 0.5, 0.35, 0.25, 0.2, 0.15, 0.12];
    return list[(rank - 1).clamp(0, list.length - 1)];
  }

  static RaceOutcome apply(PlayerProfile p, RaceResult r, ContentDb db, {DateTime? now, double earningsMul = 1.0, bool saveGhost = false}) {
    final o = RaceOutcome();
    final econ = db.econ('race');
    final lv = db.econ('levels');
    int levelOf() => p.level(base: (lv['xpBase'] as num?)?.toInt() ?? 120, step: (lv['xpStep'] as num?)?.toInt() ?? 45, maxLevel: (lv['maxLevel'] as num?)?.toInt() ?? 100).level;
    o.oldLevel = levelOf();
    o.rpBefore = p.rankPoints;
    final meaningful = r.chars >= minCharsForStats && !r.suspicious;

    p.addCounter('races', 1);
    if (r.won && r.opponents > 0) p.addCounter('wins', 1);
    p.addCounter('chars', r.chars);
    if (r.nitroUses > 0) p.addCounter('nitro_count', r.nitroUses);
    if (r.powerupsUsed > 0) p.addCounter('powerups_used', r.powerupsUsed);
    if (r.pitPerfect) p.addCounter('pit_perfect', 1);
    if (meaningful && r.accuracy >= 100 && r.chars >= 40) p.addCounter('perfect_races', 1);
    if (r.photoFinish && r.won) p.addCounter('photo_finish_wins', 1);
    final kills = (r.extra['kills'] as num?)?.toInt() ?? 0;
    if (kills > 0) p.addCounter('combat_kills', kills);
    final survived = (r.extra['survived'] as num?)?.toDouble();
    if (survived != null && !r.suspicious && survived > 0) p.setBest('survival_best', survived);
    p.registerActivity(now);

    if (meaningful) {
      if (p.setBest('best_wpm', double.parse(r.wpm.toStringAsFixed(1)))) o.records.add('best_wpm');
      if (r.chars >= 60 && p.setBest('best_acc', double.parse(r.accuracy.toStringAsFixed(1)))) o.records.add('best_acc');
      if (p.setBest('combo_max', r.maxCombo)) o.records.add('combo_max');
      p.pushHistory(r.wpm);
      final lang = r.config.text.lang;
      final cs = p.m('charStats');
      r.charStats.forEach((ch, st) {
        final key = '$lang:$ch';
        final cur = (cs[key] as List?) ?? [0, 0, 0];
        cs[key] = [((cur[0] as num) + st[0]).toInt(), ((cur[1] as num) + st[1]).toInt(), ((cur[2] as num) + st[2]).toInt()];
      });
    }

    if (!r.config.rewards || r.suspicious || r.chars < 10) {
      o.rewarded = false;
      o.note = r.suspicious ? 'suspicious' : null;
      o.newLevel = levelOf();
      o.rpAfter = p.rankPoints;
      return o;
    }

    // ---- coins
    final dk = dayKey(now ?? DateTime.now()).replaceAll('-', '');
    final earnedToday = p.counter('dc_$dk');
    final cap = (econ['dailyCoinCap'] as num?)?.toInt() ?? 2500;
    final guaranteed = (econ['minGuaranteed'] as num?)?.toInt() ?? 12;
    final base = (econ['baseCoins'] as num?)?.toDouble() ?? 18;
    final perWpm = (econ['perWpm'] as num?)?.toDouble() ?? 0.55;
    final accFrom = (econ['accBonusFrom'] as num?)?.toDouble() ?? 95;
    final accBonus = (econ['accBonus'] as num?)?.toDouble() ?? 0.15;
    var coins = (base + r.wpm * perWpm) * (r.opponents > 0 ? rankMultiplier(db, r.playerRank) : 0.8) * r.config.riskMul * earningsMul;
    if (survived != null) coins *= 1 + min(2.0, survived / 60);
    if (kills > 0) coins *= 1 + min(1.0, kills * 0.15);
    if (r.accuracy >= accFrom) coins *= 1 + accBonus;
    if (r.accuracy < 80) coins *= 0.5;
    var c = max(guaranteed, coins.round());
    if (earnedToday >= cap) {
      c = guaranteed; // guaranteed minimum for free players after the daily cap
      o.capped = true;
    } else if (earnedToday + c > cap) {
      c = max(guaranteed, cap - earnedToday);
      o.capped = true;
    }
    o.coins = c;
    p.addCoins(c);
    p.addCounter('dc_$dk', c);

    // ---- xp
    final xpBase = (econ['xpBase'] as num?)?.toDouble() ?? 25;
    final xpPerWpm = (econ['xpPerWpm'] as num?)?.toDouble() ?? 0.45;
    var xp = (xpBase + r.wpm * xpPerWpm) * (r.won ? 1.25 : 1.0) * (0.6 + 0.4 * (r.accuracy / 100));
    xp *= r.config.riskMul > 1 ? 1.4 : 1.0;
    xp *= db.xpMultiplier;
    o.xp = max(5, xp.round());
    p.addXp(o.xp);

    // ---- ranked
    if (r.config.ranked && r.opponents > 0 && meaningful) {
      final win = (econ['rankedWin'] as num?)?.toInt() ?? 22;
      final loss = (econ['rankedLoss'] as num?)?.toInt() ?? 12;
      final maxGain = (econ['rankedMax'] as num?)?.toInt() ?? 40;
      var d = 0;
      if (r.playerRank == 1) {
        d = win;
      } else if (r.playerRank <= (r.standings.length / 2).ceil()) {
        d = (win * 0.35).round();
      } else {
        d = -loss;
      }
      if (d > 0 && r.accuracy >= 97) d += 3;
      if (d < 0 && r.accuracy >= 98) d += 4;
      d = d.clamp(-loss, maxGain);
      final before = p.rankPoints;
      p.addRankPoints(d);
      o.rpDelta = p.rankPoints - before;
    }
    o.rpAfter = p.rankPoints;
    final tb = Ranks.tierIndex(db, o.rpBefore), ta = Ranks.tierIndex(db, o.rpAfter);
    o.tierBefore = Ranks.tiers(db)[tb].id;
    o.tierAfter = Ranks.tiers(db)[ta].id;
    o.tierUp = ta > tb;
    o.tierDown = ta < tb;

    o.newLevel = levelOf();
    if (o.levelUp) {
      // level-up gems every 5 levels
      if (o.newLevel % 5 == 0) {
        o.gems += 5;
        p.addGems(5);
      }
    }
    return o;
  }
}
