import 'dart:math';
import '../../core/providers.dart';
import '../../core/util/dates.dart';
import '../../core/util/misc.dart';
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
    final customPlate = (p.settings['plateText'] as String?) ?? '';
    final look = Look.resolve(db, v, lo, outfitId: p.selOutfit, plateName: customPlate.isNotEmpty ? customPlate : p.name);
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

  // ---------------------------------------------------------------- other modes
  TextItem _synthetic(String id, String text, {String? lang, String cat = 'sentence', int diff = 2}) =>
      TextItem({'id': id, 't': text, 'cat': cat, 'topic': 'mix', 'lang': lang ?? this.lang, 'diff': diff, 'len': text.length});

  /// Endless-style text for survival: many sentences in a row.
  TextItem survivalText() {
    final used = <String>{};
    final buf = StringBuffer();
    for (var i = 0; i < 9; i++) {
      final t = db.pickText(rnd, lang: lang, cats: const ['sentence', 'quote'], minLen: 50, maxLen: 130, exclude: used);
      used.add(t.id);
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(t.text);
    }
    return _synthetic('survival_${rnd.nextInt(1 << 30)}', buf.toString(), diff: diffRange(targetWpm()).max);
  }

  RaceConfig survival() {
    final wpm = targetWpm();
    final legendary = db.vehicles.where((v) => v.rarity == 'legendary' && v.eventId == null && v.achievementId == null && !v.isBike).toList();
    final v = legendary.isEmpty ? db.starterCar : legendary[rnd.nextInt(legendary.length)];
    final hunter = AiSpec(id: 'hunter', name: 'المطارد', cc: '', persona: Persona.aggressive, baseWpm: max(25.0, wpm * 1.05), vehicleId: v.id, paintId: 'p_black', rubberScale: 0);
    final b = randomBiome();
    return RaceConfig(modeId: 'survival', title: 'البقاء', text: survivalText(), biomeId: b.id, mod: 'none', opponents: [hunter], rules: RaceRules.solo, ranked: false);
  }

  RaceConfig combat({int rivals = 3}) {
    final b = randomBiome();
    final wpm = targetWpm();
    final specs = opponents(rivals, wpm: wpm, difficulty: 0.85);
    return RaceConfig(
      modeId: 'combat',
      title: 'قتال الطريق',
      text: pickText(len: LengthPref.long, cats: lang == 'en' ? const ['sentence', 'quote', 'story'] : null),
      biomeId: b.id,
      mod: 'none',
      opponents: [for (final o in specs) AiSpec(id: o.id, name: o.name, cc: o.cc, persona: Persona.aggressive, baseWpm: o.baseWpm, vehicleId: o.vehicleId, paintId: o.paintId)],
      rules: const RaceRules(pit: false, slipstream: false),
    );
  }

  static List<GhostSpec> fixedGhosts(double wpm) => [
        GhostSpec(name: 'AI • مبتدئ', wpm: max(10, wpm * 0.6)),
        GhostSpec(name: 'AI • ثابت', wpm: max(12, wpm * 0.95)),
        GhostSpec(name: 'AI • سريع', wpm: max(15, wpm * 1.25)),
      ];

  RaceConfig dailyChallenge({DateTime? now}) {
    final t = db.dailyText(dayKey(now));
    return RaceConfig(
      modeId: 'daily',
      title: 'تحدي اليوم',
      text: t,
      biomeId: 'city',
      ghosts: fixedGhosts(max(25, targetWpm())),
      rules: RaceRules.purePlay,
      meta: {'period': dayKey(now)},
    );
  }

  TextItem weeklyText({DateTime? now}) {
    final all = db.textsFor(lang: 'en', cats: const ['story'])..sort((a, b) => a.id.compareTo(b.id));
    if (all.isEmpty) return db.dailyText('w${weekKey(now)}');
    return all[stableHash('weekly${weekKey(now)}') % all.length];
  }

  RaceConfig weeklyChallenge({DateTime? now}) {
    final b = db.biomes.isEmpty ? db.biomeOf('city') : db.biomes[stableHash('wb${weekKey(now)}') % db.biomes.length];
    return RaceConfig(
      modeId: 'weekly',
      title: 'تحدي الأسبوع',
      text: weeklyText(now: now),
      biomeId: b.id,
      ghosts: fixedGhosts(max(25, targetWpm())),
      rules: RaceRules.purePlay,
      meta: {'period': weekKey(now)},
    );
  }

  RaceConfig custom(String text, {String? lang}) => RaceConfig(
        modeId: 'custom',
        title: 'نص مخصص',
        text: _synthetic('custom', text, lang: lang, diff: 3),
        biomeId: randomBiome().id,
        rules: RaceRules.purePlay,
        rewards: false,
      );

  RaceConfig worldStop(City c) {
    final ids = c.textIds.isEmpty ? <String>[] : c.textIds;
    final t = ids.isEmpty ? pickText() : (db.textById(ids[rnd.nextInt(ids.length)]) ?? pickText());
    final wpms = Matchmaker.opponentWpms(c.minWpm.toDouble(), c.opp, rnd);
    final sky = c.colors.length >= 2 ? c.colors.map((e) => e).toList() : null;
    return RaceConfig(
      modeId: 'world',
      title: loc(c.name),
      text: t,
      biomeId: 'city',
      mod: 'none',
      opponents: Matchmaker.roster(db, rnd, wpms, playerName: profile.name),
      meta: {'cityId': c.id, 'sky': ?sky},
    );
  }

  RaceConfig ghostRace({required TextItem text, GhostSpec? personal, double? aiWpm}) {
    final w = aiWpm ?? max(25, targetWpm());
    return RaceConfig(
      modeId: 'ghost',
      title: 'سباق الأشباح',
      text: text,
      biomeId: randomBiome().id,
      ghosts: [?personal, ...fixedGhosts(w).where((g) => personal == null || (g.wpm - personal.wpm).abs() > 4)],
      rules: RaceRules.solo,
    );
  }

  /// Personal ghost saved locally for a text (best run), or null.
  GhostSpec? personalGhost(Map<String, dynamic>? saved) {
    if (saved == null) return null;
    final samples = (saved['samples'] as List?)?.map((e) => (e as List).map((x) => x as num).toList()).toList();
    return GhostSpec(name: '👻 رقمك', wpm: (saved['wpm'] as num).toDouble(), samples: samples, personal: true);
  }

  RaceConfig tournamentMatch({required String title, required AiSpec opponent, required TournamentDef def}) => RaceConfig(
        modeId: 'tournament',
        title: title,
        text: db.pickText(rnd, lang: lang, cats: def.cats.isEmpty ? null : def.cats, minLen: 70, maxLen: 190, minDiff: diffRange(targetWpm()).min, maxDiff: diffRange(targetWpm()).max),
        biomeId: randomBiome().id,
        opponents: [opponent],
        ranked: false,
        meta: {'tournament': def.id},
      );
}
