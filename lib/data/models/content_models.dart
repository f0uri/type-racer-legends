import '../../core/util/dates.dart';

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _list(dynamic v) => v is List ? v : <dynamic>[];
T _req<T>(Map m, String k) {
  final v = m[k];
  if (v is! T) throw FormatException('missing/invalid field "$k"');
  return v;
}

class Price {
  final int coins;
  final int gems;
  const Price(this.coins, this.gems);
  factory Price.from(dynamic v) {
    final m = _map(v);
    return Price((m['coins'] as num?)?.toInt() ?? 0, (m['gems'] as num?)?.toInt() ?? 0);
  }
  bool get free => coins == 0 && gems == 0;
}

/// Base class for all data-driven catalog items (vehicles, skins, outfits).
abstract class CatalogItem {
  final String id;
  final Map<String, dynamic> name;
  final String rarity;
  final Price price;
  final Map<String, dynamic> unlock;
  final bool enabled;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final List<String> tags;
  final String? imageUrl;
  CatalogItem(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        name = _map(_req<Map>(m, 'name')),
        rarity = (m['rarity'] as String?) ?? 'common',
        price = Price.from(m['price']),
        unlock = _map(m['unlock']),
        enabled = m['enabled'] != false,
        startsAt = parseIso(m['startsAt'] as String?),
        endsAt = parseIso(m['endsAt'] as String?),
        tags = _list(m['tags']).map((e) => e.toString()).toList(),
        imageUrl = m['imageUrl'] as String?;

  String? get eventId => unlock['event'] as String?;
  String? get achievementId => unlock['achievement'] as String?;
  int get unlockLevel => (unlock['level'] as num?)?.toInt() ?? 1;
  bool get isExclusive => eventId != null || achievementId != null || unlock['season'] != null;

  bool inWindow([DateTime? now]) {
    final n = now ?? DateTime.now();
    if (startsAt != null && n.isBefore(startsAt!)) return false;
    if (endsAt != null && n.isAfter(endsAt!)) return false;
    return true;
  }
}

class Vehicle extends CatalogItem {
  final String kind; // car | bike
  final String style;
  final Map<String, dynamic> stats;
  final Map<String, dynamic> colors;
  final Map<String, dynamic> shape;
  Vehicle(super.m)
      : kind = _req<String>(m, 'kind'),
        style = _req<String>(m, 'style'),
        stats = _map(m['stats']),
        colors = _map(m['colors']),
        shape = _map(m['shape']) {
    if (kind != 'car' && kind != 'bike') throw const FormatException('bad kind');
  }
  bool get isBike => kind == 'bike';
  int stat(String k) => (stats[k] as num?)?.toInt() ?? 5;
}

class Skin extends CatalogItem {
  final String slot;
  final Map<String, dynamic> params;
  final List<String> kinds;
  final String? vehicleId;
  Skin(super.m)
      : slot = _req<String>(m, 'slot'),
        params = _map(m['params']),
        kinds = _list(m['kinds']).map((e) => e.toString()).toList(),
        vehicleId = m['vehicleId'] as String?;
  bool fits(Vehicle v) => (vehicleId == null || vehicleId == v.id) && (kinds.isEmpty || kinds.contains(v.kind));
}

class Outfit extends CatalogItem {
  final Map<String, dynamic> params;
  Outfit(super.m) : params = _map(m['params']);
}

class GameEvent {
  final String id;
  final Map<String, dynamic> name, desc;
  final bool enabled;
  final DateTime? startsAt, endsAt;
  final String color;
  final double xpMultiplier;
  final List<String> featured;
  final List<Map<String, dynamic>> tasks;
  final Map<String, dynamic> finalReward;
  GameEvent(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        name = _map(_req<Map>(m, 'name')),
        desc = _map(m['desc']),
        enabled = m['enabled'] != false,
        startsAt = parseIso(m['startsAt'] as String?),
        endsAt = parseIso(m['endsAt'] as String?),
        color = (m['color'] as String?) ?? '#00E5FF',
        xpMultiplier = (m['xpMultiplier'] as num?)?.toDouble() ?? 1,
        featured = _list(m['featured']).map((e) => e.toString()).toList(),
        tasks = _list(m['tasks']).map((e) => _map(e)).toList(),
        finalReward = _map(m['finalReward']);
  bool isActive([DateTime? now]) {
    final n = now ?? DateTime.now();
    return enabled && (startsAt == null || !n.isBefore(startsAt!)) && (endsAt == null || !n.isAfter(endsAt!));
  }

  bool isUpcoming([DateTime? now]) => enabled && startsAt != null && (now ?? DateTime.now()).isBefore(startsAt!);
}

class TextItem {
  final String id;
  final String text;
  final String cat;
  final String topic;
  final String lang;
  final int diff;
  final String? src;
  TextItem(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        text = _req<String>(m, 't'),
        cat = (m['cat'] as String?) ?? 'sentence',
        topic = (m['topic'] as String?) ?? 'general',
        lang = (m['lang'] as String?) ?? 'en',
        diff = (m['diff'] as num?)?.toInt() ?? 2,
        src = m['src'] as String? {
    if (text.trim().isEmpty) throw const FormatException('empty text');
  }
  int get len => text.length;
}

class Biome {
  final String id;
  final Map<String, dynamic> name;
  final List<String> sky;
  final String ground, weather, mod, accent;
  Biome(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        name = _map(m['name']),
        sky = _list(m['sky']).map((e) => e.toString()).toList(),
        ground = (m['ground'] as String?) ?? '#2b2f3a',
        weather = (m['weather'] as String?) ?? 'none',
        mod = (m['mod'] as String?) ?? 'none',
        accent = (m['accent'] as String?) ?? '#00E5FF';
}

class Boss {
  final String id;
  final Map<String, dynamic> name, win, lose;
  final String cc, persona, vehicle, paint;
  final double wpmMul;
  final Map<String, dynamic> taunts;
  Boss(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        name = _map(m['name']),
        win = _map(m['win']),
        lose = _map(m['lose']),
        cc = (m['cc'] as String?) ?? 'US',
        persona = (m['persona'] as String?) ?? 'balanced',
        vehicle = (m['vehicle'] as String?) ?? 'c_sprout',
        paint = (m['paint'] as String?) ?? 'p_red',
        wpmMul = (m['wpmMul'] as num?)?.toDouble() ?? 1.1,
        taunts = _map(m['taunts']);
}

class Stage {
  final int n;
  final String biome;
  final String? boss;
  final Map<String, dynamic> title;
  final int lenMin, lenMax;
  final List<String> cats;
  final String mod;
  final int oppCount;
  final double oppWpm;
  final int accStar;
  final Map<String, dynamic> reward;
  Stage(Map<String, dynamic> m)
      : n = _req<num>(m, 'n').toInt(),
        biome = _req<String>(m, 'biome'),
        boss = m['boss'] as String?,
        title = _map(m['title']),
        lenMin = (m['lenMin'] as num?)?.toInt() ?? 40,
        lenMax = (m['lenMax'] as num?)?.toInt() ?? 120,
        cats = _list(m['cats']).map((e) => e.toString()).toList(),
        mod = (m['mod'] as String?) ?? 'none',
        oppCount = ((m['opp'] as Map?)?['count'] as num?)?.toInt() ?? 3,
        oppWpm = ((m['opp'] as Map?)?['wpm'] as num?)?.toDouble() ?? 30,
        accStar = (m['accStar'] as num?)?.toInt() ?? 92,
        reward = _map(m['reward']);
  bool get isBoss => boss != null;
}

class Achievement {
  final String id, metric, icon;
  final int target, tier, of;
  final Map<String, dynamic> name, desc, reward;
  final String? title;
  final bool enabled;
  Achievement(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        metric = _req<String>(m, 'metric'),
        icon = (m['icon'] as String?) ?? 'star',
        target = _req<num>(m, 'target').toInt(),
        tier = (m['tier'] as num?)?.toInt() ?? 1,
        of = (m['of'] as num?)?.toInt() ?? 1,
        name = _map(m['name']),
        desc = _map(m['desc']),
        reward = _map(m['reward']),
        title = m['title'] as String?,
        enabled = m['enabled'] != false;
}

class Quest {
  final String id, period, metric;
  final int target, sp;
  final Map<String, dynamic> name, reward;
  final bool enabled;
  Quest(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        period = _req<String>(m, 'period'),
        metric = _req<String>(m, 'metric'),
        target = _req<num>(m, 'target').toInt(),
        sp = (m['sp'] as num?)?.toInt() ?? 20,
        name = _map(m['name']),
        reward = _map(m['reward']),
        enabled = m['enabled'] != false;
}

class City {
  final String id, cc, landmark;
  final int idx, km, minWpm, opp;
  final Map<String, dynamic> name, reward;
  final List<String> textIds;
  final List<String> colors;
  City(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        cc = (m['cc'] as String?) ?? '',
        landmark = (m['landmark'] as String?) ?? 'lighthouse',
        idx = (m['idx'] as num?)?.toInt() ?? 0,
        km = (m['km'] as num?)?.toInt() ?? 0,
        minWpm = (m['minWpm'] as num?)?.toInt() ?? 20,
        opp = (m['opp'] as num?)?.toInt() ?? 2,
        name = _map(m['name']),
        reward = _map(m['reward']),
        textIds = _list(m['textIds']).map((e) => e.toString()).toList(),
        colors = _list(m['colors']).map((e) => e.toString()).toList();
}

class TournamentDef {
  final String id, period;
  final int size, rounds;
  final Map<String, dynamic> name, rewards;
  final List<String> cats;
  TournamentDef(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        period = (m['period'] as String?) ?? 'daily',
        size = (m['size'] as num?)?.toInt() ?? 8,
        rounds = (m['rounds'] as num?)?.toInt() ?? 3,
        name = _map(m['name']),
        rewards = _map(m['rewards']),
        cats = _list(m['cats']).map((e) => e.toString()).toList();
}

class VocabWord {
  final String id, en, ar;
  final int level;
  VocabWord(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        en = _req<String>(m, 'en'),
        ar = _req<String>(m, 'ar'),
        level = (m['level'] as num?)?.toInt() ?? 1;
}


/// One touch-typing lesson (content/lessons.json).
class Lesson {
  final String id, kind, focus, allowed, hint, text;
  final int n, targetWpm, minAcc;
  final Map<String, dynamic> title, reward;
  Lesson(Map<String, dynamic> m)
      : id = _req<String>(m, 'id'),
        kind = (m['kind'] as String?) ?? 'keys',
        focus = (m['focus'] as String?) ?? '',
        allowed = (m['allowed'] as String?) ?? '',
        hint = (m['hint'] as String?) ?? '',
        text = _req<String>(m, 'text'),
        n = _req<num>(m, 'n').toInt(),
        targetWpm = (m['targetWpm'] as num?)?.toInt() ?? 20,
        minAcc = (m['minAcc'] as num?)?.toInt() ?? 92,
        title = _map(m['title']),
        reward = _map(m['reward']) {
    if (text.trim().length < 20) throw const FormatException('lesson text too short');
  }
}
