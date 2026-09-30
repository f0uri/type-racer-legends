import 'dart:math';
import '../../core/util/misc.dart';
import '../../data/models/content_models.dart';

/// Parsed, validated game content. All game definitions live in JSON (content/*.json).
/// Invalid items are skipped, never crash the game, and no loaded data is ever executed.
class ContentDb {
  final int catalogVersion;
  final Map<String, dynamic> catalog;
  final List<Vehicle> vehicles;
  final List<Skin> skins;
  final List<Outfit> outfits;
  final List<GameEvent> events;
  final List<TextItem> texts;
  final List<Biome> biomes;
  final List<Boss> bosses;
  final List<Stage> stages;
  final List<Achievement> achievements;
  final List<Quest> quests;
  final List<City> cities;
  final List<TournamentDef> tournaments;
  final List<VocabWord> vocab;
  final Map<String, dynamic> economy, shop, season, ai, titles;
  final Set<String> killedItems;
  final Set<String> killedFeatures;
  final Map<String, TextItem> _textById;
  final Map<String, dynamic> _byId;

  ContentDb._(this.catalogVersion, this.catalog, this.vehicles, this.skins, this.outfits, this.events, this.texts, this.biomes, this.bosses, this.stages,
      this.achievements, this.quests, this.cities, this.tournaments, this.vocab, this.economy, this.shop, this.season, this.ai, this.titles, this.killedItems,
      this.killedFeatures, this._textById, this._byId);

  factory ContentDb.empty() => ContentDb.parse({'catalog': <String, dynamic>{}});

  static List<T> _parseList<T>(dynamic items, T Function(Map<String, dynamic>) f, {void Function(Object e)? onError}) {
    final out = <T>[];
    if (items is! List) return out;
    for (final it in items) {
      try {
        if (it is Map) out.add(f(Map<String, dynamic>.from(it)));
      } catch (e) {
        onError?.call(e);
      }
    }
    return out;
  }

  static Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// [files] maps file key (e.g. "vehicles", "texts/en_words") to decoded JSON; "catalog" holds catalog.json.
  factory ContentDb.parse(Map<String, dynamic> files) {
    final catalog = _m(files['catalog']);
    final kill = _m(catalog['killSwitch']);
    final texts = <TextItem>[];
    for (final e in files.entries) {
      if (e.key.startsWith('texts/')) texts.addAll(_parseList(_m(e.value)['items'], TextItem.new));
    }
    final byText = <String, TextItem>{for (final t in texts) t.id: t};
    final vehicles = _parseList(_m(files['vehicles'])['items'], Vehicle.new);
    final skins = _parseList(_m(files['skins'])['items'], Skin.new);
    final outfits = _parseList(_m(files['outfits'])['items'], Outfit.new);
    final byId = <String, dynamic>{};
    for (final i in [...vehicles, ...skins, ...outfits]) {
      byId[i.id] = i;
    }
    final camp = _m(files['campaign']);
    return ContentDb._(
      (catalog['version'] as num?)?.toInt() ?? 0,
      catalog,
      vehicles,
      skins,
      outfits,
      _parseList(_m(files['events'])['items'], GameEvent.new),
      texts,
      _parseList(camp['biomes'], Biome.new),
      _parseList(camp['bosses'], Boss.new),
      _parseList(camp['items'], Stage.new)..sort((a, b) => a.n.compareTo(b.n)),
      _parseList(_m(files['achievements'])['items'], Achievement.new),
      _parseList(_m(files['quests'])['items'], Quest.new),
      _parseList(_m(files['world'])['items'], City.new)..sort((a, b) => a.idx.compareTo(b.idx)),
      _parseList(_m(files['tournaments'])['items'], TournamentDef.new),
      _parseList(_m(files['vocab'])['items'], VocabWord.new),
      _m(files['economy']),
      _m(files['shop']),
      _m(files['season']),
      _m(files['ai']),
      _m(_m(files['achievements'])['titles']),
      ((kill['items'] as List?) ?? []).map((e) => e.toString()).toSet(),
      ((kill['features'] as List?) ?? []).map((e) => e.toString()).toSet(),
      byText,
      byId,
    );
  }

  /// Copy with extra remote kill-switch entries and economy patches (Firebase Remote Config); nothing is executed.
  ContentDb withOverrides({Set<String> killFeatures = const {}, Set<String> killItems = const {}, Map<String, Map<String, dynamic>>? economyPatch}) {
    final eco = Map<String, dynamic>.from(economy);
    economyPatch?.forEach((group, patch) {
      eco[group] = {..._m(eco[group]), ...patch};
    });
    return ContentDb._(catalogVersion, catalog, vehicles, skins, outfits, events, texts, biomes, bosses, stages, achievements, quests, cities, tournaments, vocab, eco, shop, season, ai,
        titles, {...killedItems, ...killItems}, {...killedFeatures, ...killFeatures}, _textById, _byId);
  }

  // ---- lookups -----
  Vehicle? vehicle(String id) => _byId[id] is Vehicle ? _byId[id] as Vehicle : null;
  Skin? skin(String id) => _byId[id] is Skin ? _byId[id] as Skin : null;
  Outfit? outfit(String id) => _byId[id] is Outfit ? _byId[id] as Outfit : null;
  CatalogItem? item(String id) => _byId[id] as CatalogItem?;
  TextItem? textById(String id) => _textById[id];
  GameEvent? event(String id) => firstWhereOrNull(events, (e) => e.id == id);
  Boss? boss(String id) => firstWhereOrNull(bosses, (b) => b.id == id);
  Biome biomeOf(String id) => firstWhereOrNull(biomes, (b) => b.id == id) ?? (biomes.isNotEmpty ? biomes.first : Biome({'id': 'city', 'name': {'ar': 'المدينة'}}));
  Stage? stage(int n) => firstWhereOrNull(stages, (s) => s.n == n);
  Achievement? achievement(String id) => firstWhereOrNull(achievements, (a) => a.id == id);

  bool featureOn(String f) => !killedFeatures.contains(f);
  bool itemAvailable(CatalogItem i, [DateTime? now]) => i.enabled && !killedItems.contains(i.id) && i.inWindow(now);
  Vehicle get starterCar => vehicle('c_sprout') ?? vehicles.firstWhere((v) => !v.isBike, orElse: () => vehicles.first);

  GameEvent? get activeEvent => firstWhereOrNull(events, (e) => e.isActive());
  List<GameEvent> get activeEvents => events.where((e) => e.isActive()).toList();
  double get xpMultiplier => activeEvents.fold<double>(1, (a, e) => max(a, e.xpMultiplier));

  // ---- economy accessors (defaults keep the game working if economy.json is missing) -----
  Map<String, dynamic> econ(String k) => _m(economy[k]);
  num econNum(String group, String key, num def) => (econ(group)[key] as num?) ?? def;

  List<String> get dailyPool => ((catalog['dailyPool'] as List?) ?? []).map((e) => e.toString()).toList();

  // ---- texts -----
  List<TextItem> textsFor({String lang = 'en', List<String>? cats, int? minLen, int? maxLen, int? minDiff, int? maxDiff, String? topic, Set<String>? exclude}) {
    return texts.where((t) {
      if (t.lang != lang) return false;
      if (cats != null && cats.isNotEmpty && !cats.contains(t.cat)) return false;
      if (minLen != null && t.len < minLen) return false;
      if (maxLen != null && t.len > maxLen) return false;
      if (minDiff != null && t.diff < minDiff) return false;
      if (maxDiff != null && t.diff > maxDiff) return false;
      if (topic != null && t.topic != topic) return false;
      if (exclude != null && exclude.contains(t.id)) return false;
      return t.cat != 'official' && t.cat != 'world';
    }).toList();
  }

  TextItem pickText(Random rnd, {String lang = 'en', List<String>? cats, int? minLen, int? maxLen, int? minDiff, int? maxDiff, String? topic, Set<String>? exclude}) {
    var pool = textsFor(lang: lang, cats: cats, minLen: minLen, maxLen: maxLen, minDiff: minDiff, maxDiff: maxDiff, topic: topic, exclude: exclude);
    if (pool.isEmpty) pool = textsFor(lang: lang, cats: cats, exclude: exclude);
    if (pool.isEmpty) pool = textsFor(lang: lang);
    if (pool.isEmpty) pool = textsFor(lang: 'en');
    if (pool.isEmpty) {
      return TextItem({'id': 'fallback', 't': 'The quick brown fox jumps over the lazy dog.', 'cat': 'sentence'});
    }
    return pool[rnd.nextInt(pool.length)];
  }

  List<TextItem> officialTexts() => texts.where((t) => t.cat == 'official').toList();

  /// Everyone gets the same text for a given day (deterministic).
  TextItem dailyText(String key) {
    final pool = dailyPool.map(textById).whereType<TextItem>().toList();
    if (pool.isEmpty) {
      final all = textsFor(lang: 'en', cats: ['sentence', 'quote'], minLen: 60, maxLen: 180)..sort((a, b) => a.id.compareTo(b.id));
      return all.isEmpty ? pickText(Random(1)) : all[stableHash('daily$key') % all.length];
    }
    return pool[stableHash('daily$key') % pool.length];
  }
}
