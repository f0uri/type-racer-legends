import '../../../data/models/content_models.dart';
import '../../ai/ai_driver.dart';
import '../../garage/look.dart';

class RaceRules {
  final bool powerups, pit, nitro, slipstream, vehicleStats, penalties;
  final bool pure; // pure typing: no bonuses, no penalties (leaderboards, official test)
  const RaceRules({this.powerups = true, this.pit = true, this.nitro = true, this.slipstream = true, this.vehicleStats = true, this.penalties = true, this.pure = false});
  static const full = RaceRules();
  static const purePlay = RaceRules(powerups: false, pit: false, nitro: false, slipstream: false, vehicleStats: false, penalties: false, pure: true);
  static const solo = RaceRules(powerups: false, pit: false, slipstream: false);
}

class GhostSpec {
  final String name;
  final double wpm;
  final List<List<num>>? samples;
  final bool personal;
  const GhostSpec({required this.name, required this.wpm, this.samples, this.personal = false});
}

class RaceConfig {
  final String modeId;
  final String title;
  final TextItem text;
  final String biomeId;
  final String mod; // none|fog|ice|blackout|storm
  final List<AiSpec> opponents;
  final List<GhostSpec> ghosts;
  final RaceRules rules;
  final double riskMul; // reward multiplier from choosing a harder text
  final bool ranked;
  final bool rewards; // false for lessons/tests without economy
  final Map<String, dynamic> meta; // stage, city, tournament info...
  final Map<int, String>? vocabHints; // word index -> Arabic meaning (Arabic->English mode)
  final int? timeLimitMs; // timed tests
  final Look? playerLookOverride;
  final String? bossId;

  const RaceConfig({
    required this.modeId,
    required this.title,
    required this.text,
    this.biomeId = 'city',
    this.mod = 'none',
    this.opponents = const [],
    this.ghosts = const [],
    this.rules = RaceRules.full,
    this.riskMul = 1.0,
    this.ranked = false,
    this.rewards = true,
    this.meta = const {},
    this.vocabHints,
    this.timeLimitMs,
    this.playerLookOverride,
    this.bossId,
  });

  RaceConfig copyWith({TextItem? text, String? biomeId, String? mod, List<AiSpec>? opponents, double? riskMul}) => RaceConfig(
        modeId: modeId,
        title: title,
        text: text ?? this.text,
        biomeId: biomeId ?? this.biomeId,
        mod: mod ?? this.mod,
        opponents: opponents ?? this.opponents,
        ghosts: ghosts,
        rules: rules,
        riskMul: riskMul ?? this.riskMul,
        ranked: ranked,
        rewards: rewards,
        meta: meta,
        vocabHints: vocabHints,
        timeLimitMs: timeLimitMs,
        playerLookOverride: playerLookOverride,
        bossId: bossId,
      );
}

class RacerResult {
  final String id, name, cc;
  final bool isPlayer, isAi, isGhost, isBoss;
  final int rank;
  final double time, wpm, accuracy;
  const RacerResult({required this.id, required this.name, required this.cc, required this.isPlayer, required this.isAi, this.isGhost = false, this.isBoss = false, required this.rank, required this.time, required this.wpm, required this.accuracy});
}

class RaceResult {
  final RaceConfig config;
  final List<RacerResult> standings;
  final int playerRank;
  final double wpm, accuracy, time, rawWpm;
  final int maxCombo, errors, chars, nitroUses, perfectWords, powerupsUsed;
  final bool pitPerfect, photoFinish, timeUp, suspicious;
  final List<int> intervals;
  final List<List<num>> samples; // [tSec, pos] for ghost saving
  final Map<String, List<int>> charStats;
  final Map<String, dynamic> wordStats; // word -> [errors]
  const RaceResult({
    required this.config,
    required this.standings,
    required this.playerRank,
    required this.wpm,
    required this.rawWpm,
    required this.accuracy,
    required this.time,
    required this.maxCombo,
    required this.errors,
    required this.chars,
    required this.nitroUses,
    required this.perfectWords,
    required this.powerupsUsed,
    required this.pitPerfect,
    required this.photoFinish,
    required this.timeUp,
    required this.suspicious,
    required this.intervals,
    required this.samples,
    required this.charStats,
    this.wordStats = const {},
  });
  bool get won => playerRank == 1;
  int get opponents => standings.length - 1;
}
