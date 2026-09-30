import 'dart:math';
import '../../core/providers.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../ai/ai_driver.dart';
import '../content/content_db.dart';
import '../garage/look.dart';
import 'engine/race_models.dart';
import 'engine/race_session.dart';

/// The player's resolved vehicle: look + gameplay modifiers.
class PlayerRig {
  final Look look;
  final VehicleMods mods;
  final Vehicle vehicle;
  const PlayerRig(this.look, this.mods, this.vehicle);

  static PlayerRig from(ContentDb db, PlayerProfile p) {
    var v = db.vehicle(p.selVehicle);
    if (v == null || !p.ownsVehicle(v.id)) v = db.starterCar;
    final lo = p.loadout(v.id);
    final look = Look.resolve(db, v, lo, outfitId: p.selOutfit, plateName: p.name);
    final up = db.econ('upgrade');
    final per = (up['bonusPerLevel'] as num?)?.toDouble() ?? 0.03;
    int st(String k) => (v!.stats[k] as num?)?.toInt() ?? 3;
    final mods = VehicleMods.from(
      accel: st('accel'),
      stab: st('stab'),
      nitro: st('nitro'),
      earn: st('earn'),
      upAccel: p.upgradeLevel(v.id, 'accel'),
      upStab: p.upgradeLevel(v.id, 'stab'),
      upNitro: p.upgradeLevel(v.id, 'nitro'),
      upEarn: p.upgradeLevel(v.id, 'earn'),
      perLevel: per,
    );
    return PlayerRig(look, mods, v);
  }
}

enum LengthPref { short, medium, long }

class RaceBuilder {
  RaceBuilder(this.db, this.profile, this.settings, [Random? rnd]) : rnd = rnd ?? Random();
  final ContentDb db;
  final PlayerProfile profile;
  final GameSettings settings;
  final Random rnd;

  String get lang => settings.textLang;

  /// Average speed used to calibrate opponents, scaled by the user's difficulty setting (0 = auto).
  double targetWpm() {
    final base = Matchmaker.targetWpm(profile.history, fallback: max(20.0, profile.best('best_wpm') * 0.85));
    final mul = const [1.0, 0.85, 1.0, 1.15][settings.difficulty.clamp(0, 3)];
    return max(10.0, base * mul);
  }

  ({int min, int max}) diffRange(double wpm) {
    if (settings.difficulty == 1) return (min: 1, max: 2);
    if (settings.difficulty == 3) return (min: 3, max: 5);
    if (wpm < 25) return (min: 1, max: 2);
    if (wpm < 45) return (min: 1, max: 3);
    if (wpm < 70) return (min: 2, max: 4);
    return (min: 3, max: 5);
  }

  TextItem pickText({LengthPref len = LengthPref.medium, List<String>? cats, Set<String>? exclude}) {
    final dr = diffRange(targetWpm());
    final (minL, maxL) = switch (len) { LengthPref.short => (40, 95), LengthPref.medium => (90, 200), LengthPref.long => (190, 320) };
    final c = cats ?? (lang == 'en' ? const ['sentence', 'quote', 'words_short', 'words_long', 'story'] : const ['sentence', 'quote', 'words_short']);
    return db.pickText(rnd, lang: lang, cats: c, minLen: minL, maxLen: maxL, minDiff: dr.min, maxDiff: dr.max, exclude: exclude);
  }

  List<AiSpec> opponents(int count, {double? wpm, double difficulty = 1.0}) {
    final w = Matchmaker.opponentWpms(wpm ?? targetWpm(), count, rnd, difficulty: difficulty);
    return Matchmaker.roster(db, rnd, w, playerName: profile.name);
  }

  Biome randomBiome() => db.biomes.isEmpty ? db.biomeOf('city') : db.biomes[rnd.nextInt(db.biomes.length)];

  RaceConfig quick({int opponentsCount = 4, LengthPref len = LengthPref.medium, bool ranked = true, Biome? biome, String? mod}) {
    final b = biome ?? randomBiome();
    final m = mod ?? (rnd.nextDouble() < 0.3 ? b.mod : 'none');
    return RaceConfig(
      modeId: 'quick',
      title: 'سباق سريع',
      text: pickText(len: len),
      biomeId: b.id,
      mod: m,
      opponents: opponents(opponentsCount.clamp(3, 7)),
      ranked: ranked,
      rules: RaceRules.full,
    );
  }
}
