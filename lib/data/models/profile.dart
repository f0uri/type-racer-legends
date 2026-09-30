import 'dart:convert';
import '../../core/config/app_config.dart';
import '../../core/util/dates.dart';
import '../../core/util/misc.dart';

class LevelInfo {
  final int level;
  final int xpInLevel;
  final int xpForNext;
  const LevelInfo(this.level, this.xpInLevel, this.xpForNext);
  double get progress => xpForNext == 0 ? 1 : xpInLevel / xpForNext;
}

/// XP curve: level n -> n+1 costs base + step*(n-1).
LevelInfo levelInfoFor(int xp, {int base = 120, int step = 45, int maxLevel = 100}) {
  var level = 1;
  var rest = xp < 0 ? 0 : xp;
  while (level < maxLevel) {
    final need = base + step * (level - 1);
    if (rest < need) return LevelInfo(level, rest, need);
    rest -= need;
    level++;
  }
  return LevelInfo(maxLevel, 0, 0);
}

/// Player profile stored as a JSON map so that migration and merging stay generic.
/// Additive numbers (coins, gems, xp, stats) are per-device grow-only counters so that
/// merging two devices/accounts never loses or double counts progress.
class PlayerProfile {
  final Map<String, dynamic> d;
  PlayerProfile(this.d);

  factory PlayerProfile.fresh(String deviceId) => PlayerProfile({
        'v': AppConfig.profileSchema,
        'rev': 0,
        'updatedAt': nowMs(),
        'deviceId': deviceId,
        'uid': null,
        'name': 'لاعب',
        'country': '',
        'avatar': 0,
        'title': 't_rookie',
        'profileAt': 0,
        'refCode': newId(6).toUpperCase(),
        'referredBy': null,
        'c': <String, dynamic>{},
        'b': <String, dynamic>{},
        'vehicles': <String, dynamic>{},
        'skins': <String, dynamic>{},
        'outfits': <String, dynamic>{},
        'titles': <String, dynamic>{'t_rookie': 0},
        'sel': {'vehicle': 'c_sprout', 'outfit': 'o_default', 'at': 0},
        'ach': <String, dynamic>{},
        'achClaimed': <String, dynamic>{},
        'quests': {'daily': <String, dynamic>{}, 'weekly': <String, dynamic>{}},
        'streak': {'count': 0, 'best': 0, 'last': ''},
        'season': {'id': 0, 'premium': false, 'free': <dynamic>[], 'prem': <dynamic>[]},
        'campaign': <String, dynamic>{},
        'world': <String, dynamic>{},
        'bossWon': <String, dynamic>{},
        'settings': <String, dynamic>{},
        'settingsAt': 0,
        'flags': <String, dynamic>{},
        'hist': <dynamic>[],
        'histAt': 0,
        'charStats': <String, dynamic>{},
        'daily': <String, dynamic>{},
        'events': <String, dynamic>{},
        'tourn': <String, dynamic>{},
        'pendingPurchases': <dynamic>[],
        'lessons': <String, dynamic>{},
        'seenItems': <String, dynamic>{},
        'chests': <String, dynamic>{},
      });

  factory PlayerProfile.fromJson(String s) => PlayerProfile(Map<String, dynamic>.from(jsonDecode(s) as Map));

  PlayerProfile clone() => PlayerProfile(Map<String, dynamic>.from(jsonDecode(jsonEncode(d)) as Map));
  String toJson() => jsonEncode(d);

  // ---- helpers -----
  Map<String, dynamic> m(String k) => (d[k] ??= <String, dynamic>{}) as Map<String, dynamic>;
  Map<String, dynamic> sub(Map<String, dynamic> parent, String k) => (parent[k] ??= <String, dynamic>{}) as Map<String, dynamic>;
  String get deviceId => d['deviceId'] as String;
  String? get uid => d['uid'] as String?;
  set uid(String? v) => d['uid'] = v;
  String get name => (d['name'] as String?) ?? 'لاعب';
  String get country => (d['country'] as String?) ?? '';
  int get avatar => (d['avatar'] as num?)?.toInt() ?? 0;
  String get title => (d['title'] as String?) ?? 't_rookie';
  String get refCode => (d['refCode'] as String?) ?? '';
  int get rev => (d['rev'] as num?)?.toInt() ?? 0;
  int get updatedAt => (d['updatedAt'] as num?)?.toInt() ?? 0;

  void setIdentity({String? name, String? country, int? avatar, String? title}) {
    if (name != null) d['name'] = name;
    if (country != null) d['country'] = country;
    if (avatar != null) d['avatar'] = avatar;
    if (title != null) d['title'] = title;
    d['profileAt'] = nowMs();
  }

  void touch() {
    d['rev'] = rev + 1;
    d['updatedAt'] = nowMs();
  }

  // ---- counters (G-Counter per device) -----
  int counter(String key) {
    final c = (d['c'] as Map?)?[key];
    if (c is! Map) return 0;
    var s = 0;
    for (final v in c.values) {
      s += (v as num).toInt();
    }
    return s;
  }

  void addCounter(String key, int n) {
    if (n <= 0) return;
    final c = sub(m('c'), key);
    c[deviceId] = ((c[deviceId] as num?)?.toInt() ?? 0) + n;
  }

  // ---- bests (max) -----
  double best(String key) => ((d['b'] as Map?)?[key] as num?)?.toDouble() ?? 0;
  bool setBest(String key, num v) {
    if (v > best(key)) {
      m('b')[key] = v;
      return true;
    }
    return false;
  }

  // ---- wallet -----
  int get coins => counter('coinsEarned') - counter('coinsSpent');
  int get gems => counter('gemsEarned') - counter('gemsSpent');
  void addCoins(int n) => n >= 0 ? addCounter('coinsEarned', n) : addCounter('coinsSpent', -n);
  void addGems(int n) => n >= 0 ? addCounter('gemsEarned', n) : addCounter('gemsSpent', -n);
  bool spend({int coins = 0, int gems = 0}) {
    if (this.coins < coins || this.gems < gems) return false;
    if (coins > 0) addCounter('coinsSpent', coins);
    if (gems > 0) addCounter('gemsSpent', gems);
    return true;
  }

  // ---- xp / level / rank -----
  int get xp => counter('xp');
  void addXp(int n) => addCounter('xp', n);
  LevelInfo level({int base = 120, int step = 45, int maxLevel = 100}) => levelInfoFor(xp, base: base, step: step, maxLevel: maxLevel);
  int get rankPoints {
    final v = counter('rpGain') - counter('rpLoss');
    return v < 0 ? 0 : v;
  }

  void addRankPoints(int delta) => delta >= 0 ? addCounter('rpGain', delta) : addCounter('rpLoss', -delta);

  // ---- collections -----
  Map<String, dynamic> get vehicles => m('vehicles');
  Map<String, dynamic> get skins => m('skins');
  Map<String, dynamic> get outfits => m('outfits');
  bool ownsVehicle(String id) => vehicles.containsKey(id);
  bool ownsSkin(String id) => skins.containsKey(id);
  bool ownsOutfit(String id) => outfits.containsKey(id);
  String get selVehicle => ((d['sel'] as Map?)?['vehicle'] as String?) ?? 'c_sprout';
  String get selOutfit => ((d['sel'] as Map?)?['outfit'] as String?) ?? 'o_default';
  void select({String? vehicle, String? outfit}) {
    final s = m('sel');
    if (vehicle != null) s['vehicle'] = vehicle;
    if (outfit != null) s['outfit'] = outfit;
    s['at'] = nowMs();
  }

  void grantVehicle(String id) {
    vehicles.putIfAbsent(id, () => {'at': nowMs(), 'upg': {'accel': 0, 'stab': 0, 'nitro': 0, 'earn': 0}, 'lo': <String, dynamic>{}, 'loAt': 0});
  }

  void grantSkin(String id) => skins.putIfAbsent(id, () => nowMs());
  void grantOutfit(String id) => outfits.putIfAbsent(id, () => nowMs());
  void grantTitle(String id) => m('titles').putIfAbsent(id, () => nowMs());

  Map<String, dynamic> vehicleState(String id) => (vehicles[id] as Map).cast<String, dynamic>();
  int upgradeLevel(String vid, String stat) {
    final v = vehicles[vid];
    if (v is! Map) return 0;
    return (((v['upg'] as Map?)?[stat]) as num?)?.toInt() ?? 0;
  }

  Map<String, dynamic> loadout(String vid) {
    final v = vehicles[vid];
    if (v is! Map) return {};
    return ((v['lo'] ??= <String, dynamic>{}) as Map).cast<String, dynamic>();
  }

  void setLoadout(String vid, Map<String, dynamic> lo) {
    final v = vehicles[vid] as Map;
    v['lo'] = lo;
    v['loAt'] = nowMs();
  }

  // ---- settings -----
  Map<String, dynamic> get settings => m('settings');
  void setSetting(String k, dynamic v) {
    settings[k] = v;
    d['settingsAt'] = nowMs();
  }

  // ---- flags -----
  bool flag(String k) => (d['flags'] as Map?)?[k] == true;
  void setFlag(String k, [bool v = true]) => m('flags')[k] = v;

  // ---- history (for matchmaking) -----
  List<double> get history => ((d['hist'] as List?) ?? []).map((e) => (e as num).toDouble()).toList();
  void pushHistory(double wpm) {
    final h = history..add(wpm);
    while (h.length > 10) {
      h.removeAt(0);
    }
    d['hist'] = h;
    d['histAt'] = nowMs();
  }

  double get avgWpm {
    final h = history;
    if (h.isEmpty) return 0;
    return h.reduce((a, b) => a + b) / h.length;
  }

  // ---- campaign -----
  int campaignStars(int stage) => ((d['campaign'] as Map?)?['$stage'] as num?)?.toInt() ?? 0;
  void setCampaignStars(int stage, int stars) {
    final c = m('campaign');
    if (stars > ((c['$stage'] as num?)?.toInt() ?? 0)) c['$stage'] = stars;
  }

  int get stagesCleared => ((d['campaign'] as Map?) ?? {}).values.where((v) => (v as num) > 0).length;
  int get totalStars => ((d['campaign'] as Map?) ?? {}).values.fold<int>(0, (a, v) => a + (v as num).toInt());
  int get worldStops => ((d['world'] as Map?) ?? {}).values.where((v) => (v as num) > 0).length;
  int get bossesDefeated => ((d['bossWon'] as Map?) ?? {}).length;
  int get upgradesDone => counter('upgrades');

  // ---- streak -----
  int get streak => (d['streak'] as Map?)?['count'] as int? ?? 0;
  String get streakLast => (d['streak'] as Map?)?['last'] as String? ?? '';

  /// Returns the new streak value after registering activity today.
  int registerActivity([DateTime? now]) {
    final today = dayKey(now);
    final s = m('streak');
    final last = (s['last'] as String?) ?? '';
    var count = (s['count'] as num?)?.toInt() ?? 0;
    if (last == today) return count;
    if (last.isNotEmpty && daysBetween(last, today) == 1) {
      count += 1;
    } else {
      count = 1;
    }
    s['count'] = count;
    s['last'] = today;
    if (count > ((s['best'] as num?)?.toInt() ?? 0)) s['best'] = count;
    return count;
  }

  /// Streak as displayed now (resets to 0 when a day was missed).
  int activeStreak([DateTime? now]) {
    final last = streakLast;
    if (last.isEmpty) return 0;
    final diff = daysBetween(last, dayKey(now));
    return diff <= 1 ? streak : 0;
  }
}
