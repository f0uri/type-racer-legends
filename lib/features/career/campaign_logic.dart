import 'dart:math';
import '../../core/providers.dart';
import '../../core/util/misc.dart';
import '../../core/util/dates.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../ai/ai_driver.dart';
import '../content/content_db.dart';
import '../race/engine/race_models.dart';
import 'progress.dart';

class StageOutcome {
  int stars = 0, bestBefore = 0;
  bool firstClear = false, bossBeaten = false, unlockedNext = false;
  int coins = 0, xp = 0, gems = 0;
}

/// Campaign rules: 50 stages, unlock in order, 1-3 stars, first-clear rewards and boss fights.
class CampaignLogic {
  static bool unlocked(PlayerProfile p, int n) => n <= 1 || p.campaignStars(n - 1) > 0;

  /// ★ finish top 2 · ★★ win · ★★★ win with accuracy >= stage goal.
  static int starsFor(RaceResult r, Stage s) {
    if (r.suspicious || r.timeUp) return 0;
    if (r.playerRank > 2) return 0;
    if (!r.won) return 1;
    return r.accuracy >= s.accStar ? 3 : 2;
  }

  static RaceConfig buildConfig(ContentDb db, PlayerProfile p, GameSettings settings, Stage stage, [Random? rnd]) {
    final r = rnd ?? Random();
    final text = db.pickText(r, lang: settings.textLang, cats: stage.cats, minLen: stage.lenMin, maxLen: stage.lenMax);
    final wpms = Matchmaker.opponentWpms(stage.oppWpm, stage.oppCount, r);
    final roster = Matchmaker.roster(db, r, wpms, playerName: p.name);
    final bossDef = stage.boss == null ? null : db.boss(stage.boss!);
    if (bossDef != null && roster.isNotEmpty) {
      // the boss is the fastest opponent of the stage
      roster.sort((a, b) => b.baseWpm.compareTo(a.baseWpm));
      roster[0] = Matchmaker.bossSpec(bossDef, stage.oppWpm * bossDef.wpmMul);
    }
    return RaceConfig(
      modeId: 'campaign',
      title: loc(stage.title),
      text: text,
      biomeId: stage.biome,
      mod: stage.mod,
      opponents: roster,
      ranked: false,
      bossId: bossDef?.id,
      meta: {'stage': stage.n},
    );
  }

  /// Applies stars and first-clear rewards. Mutates [p]. Returns what happened for the result screen.
  static StageOutcome apply(PlayerProfile p, Stage s, RaceResult r, ContentDb db) {
    final o = StageOutcome();
    o.bestBefore = p.campaignStars(s.n);
    o.stars = starsFor(r, s);
    if (o.stars > o.bestBefore) p.setCampaignStars(s.n, o.stars);
    final coins = (s.reward['coins'] as num?)?.toInt() ?? 0;
    final xp = (s.reward['xp'] as num?)?.toInt() ?? 0;
    final gems = (s.reward['gems'] as num?)?.toInt() ?? 0;
    if (o.bestBefore == 0 && o.stars > 0) {
      o.firstClear = true;
      o.coins = coins;
      o.xp = xp;
      o.gems = gems;
      o.unlockedNext = s.n < db.stages.length;
    } else if (o.stars > o.bestBefore) {
      // improving your stars pays a quarter of the coins per extra star
      o.coins = (coins * 0.25 * (o.stars - o.bestBefore)).round();
    }
    if (o.firstClear) Season.addPoints(p, db, s.isBoss ? 60 : 20);
    if (o.coins > 0) p.addCoins(o.coins);
    if (o.xp > 0) p.addXp(o.xp);
    if (o.gems > 0) p.addGems(o.gems);
    if (s.isBoss && r.won && !r.suspicious) {
      final bw = p.m('bossWon');
      if (!bw.containsKey(s.boss)) o.bossBeaten = true;
      bw[s.boss!] = nowMs();
    }
    return o;
  }

  static int nextStage(ContentDb db, int n) => n < db.stages.length ? n + 1 : n;
}
