import 'dart:math';
import '../../core/util/misc.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';

enum BuyResult { ok, notEnoughCoins, notEnoughGems, locked, unavailable, owned }

enum LockReason { none, level, event, achievement, season, unavailable }

class Availability {
  final bool owned;
  final bool canBuy;
  final LockReason reason;
  final String label; // Arabic explanation when locked
  const Availability(this.owned, this.canBuy, this.reason, this.label);
}

class UpgradeQuote {
  final int level; // current
  final int cost; // coins for the next level (0 when maxed)
  final bool maxed;
  const UpgradeQuote(this.level, this.cost, this.maxed);
}

/// Pure shop / upgrade rules. Every method mutates only the passed profile so it can be used inside `ProfileController.update`.
class Economy {
  static const stats = ['accel', 'stab', 'nitro', 'earn'];
  static const statNames = {'accel': 'التسارع', 'stab': 'الثبات', 'nitro': 'النيترو', 'earn': 'الأرباح'};

  static int levelOf(ContentDb db, PlayerProfile p) {
    final lv = db.econ('levels');
    return p.level(base: (lv['xpBase'] as num?)?.toInt() ?? 120, step: (lv['xpStep'] as num?)?.toInt() ?? 45, maxLevel: (lv['maxLevel'] as num?)?.toInt() ?? 100).level;
  }

  static bool _isStarter(CatalogItem i) => i.price.free && i.unlock.isEmpty;

  static bool ownsVehicle(PlayerProfile p, Vehicle v) => p.ownsVehicle(v.id) || _isStarter(v) && (v.id == 'c_sprout' || v.id == 'b_pocket');
  static bool ownsSkin(PlayerProfile p, Skin s) => p.ownsSkin(s.id) || _isStarter(s);
  static bool ownsOutfit(PlayerProfile p, Outfit o) => p.ownsOutfit(o.id) || _isStarter(o);

  static Availability availability(ContentDb db, PlayerProfile p, CatalogItem item, {DateTime? now}) {
    final owned = item is Vehicle ? ownsVehicle(p, item) : item is Skin ? ownsSkin(p, item) : ownsOutfit(p, item as Outfit);
    if (owned) return const Availability(true, false, LockReason.none, '');
    if (!db.itemAvailable(item, now)) return const Availability(false, false, LockReason.unavailable, 'غير متاح حالياً');
    if (item.achievementId != null) {
      final a = db.achievement(item.achievementId!);
      return Availability(false, false, LockReason.achievement, 'يُفتح بإنجاز: ${a == null ? item.achievementId! : (a.name['ar'] ?? a.id)}');
    }
    if (item.unlock['season'] != null) return const Availability(false, false, LockReason.season, 'يُفتح من مسار الموسم');
    if (item.eventId != null) {
      final e = db.event(item.eventId!);
      final active = e != null && e.isActive(now);
      return Availability(false, false, LockReason.event, active ? 'متاح عبر حدث ${e.name['ar'] ?? ''}' : 'خاص بحدث موسمي');
    }
    final lv = levelOf(db, p);
    if (item.unlockLevel > lv) return Availability(false, false, LockReason.level, 'يُفتح في المستوى ${item.unlockLevel}');
    if (item.price.free) return const Availability(false, false, LockReason.unavailable, 'غير متاح للشراء');
    return const Availability(false, true, LockReason.none, '');
  }

  static BuyResult _charge(PlayerProfile p, Price price) {
    if (p.coins < price.coins) return BuyResult.notEnoughCoins;
    if (p.gems < price.gems) return BuyResult.notEnoughGems;
    p.spend(coins: price.coins, gems: price.gems);
    return BuyResult.ok;
  }

  static BuyResult buy(ContentDb db, PlayerProfile p, CatalogItem item, {DateTime? now, double discount = 0}) {
    final a = availability(db, p, item, now: now);
    if (a.owned) return BuyResult.owned;
    if (!a.canBuy) return a.reason == LockReason.unavailable ? BuyResult.unavailable : BuyResult.locked;
    final price = discount <= 0 ? item.price : Price((item.price.coins * (1 - discount)).round(), (item.price.gems * (1 - discount)).round());
    final r = _charge(p, price);
    if (r != BuyResult.ok) return r;
    if (item is Vehicle) {
      p.grantVehicle(item.id);
    } else if (item is Skin) {
      p.grantSkin(item.id);
    } else if (item is Outfit) {
      p.grantOutfit(item.id);
    }
    return BuyResult.ok;
  }

  // ------------------------------------------------------------------ upgrades
  static double _rarityMul(String r) => r == 'legendary' ? 2.5 : (r == 'rare' ? 1.5 : 1.0);

  static UpgradeQuote upgradeQuote(ContentDb db, PlayerProfile p, Vehicle v, String stat) {
    final up = db.econ('upgrade');
    final max = (up['maxLevel'] as num?)?.toInt() ?? 5;
    final base = (up['costBase'] as num?)?.toDouble() ?? 400;
    final growth = (up['costGrowth'] as num?)?.toDouble() ?? 1.85;
    final lvl = p.upgradeLevel(v.id, stat);
    if (lvl >= max) return UpgradeQuote(lvl, 0, true);
    return UpgradeQuote(lvl, (base * pow(growth, lvl) * _rarityMul(v.rarity)).round(), false);
  }

  static BuyResult upgrade(ContentDb db, PlayerProfile p, Vehicle v, String stat) {
    if (!ownsVehicle(p, v)) return BuyResult.locked;
    final q = upgradeQuote(db, p, v, stat);
    if (q.maxed) return BuyResult.owned;
    if (p.coins < q.cost) return BuyResult.notEnoughCoins;
    p.grantVehicle(v.id); // make sure the starter vehicle has a state record
    p.spend(coins: q.cost);
    final st = p.vehicleState(v.id);
    final upg = ((st['upg'] ??= <String, dynamic>{}) as Map).cast<String, dynamic>();
    upg[stat] = q.level + 1;
    st['upg'] = upg;
    st['loAt'] = st['loAt'] ?? 0;
    p.addCounter('upgrades', 1);
    return BuyResult.ok;
  }

  // ------------------------------------------------------------------ loadouts
  /// All slots that can be customised on a vehicle.
  static const slots = ['paint', 'rims', 'neon', 'exhaust', 'nitroFlame', 'sticker1', 'sticker2', 'plate', 'horn', 'celebration'];

  static String slotOf(String key) => key.startsWith('sticker') ? 'sticker' : key;

  static void equip(PlayerProfile p, Vehicle v, String key, String? skinId) {
    p.grantVehicle(v.id);
    final lo = Map<String, dynamic>.from(p.loadout(v.id));
    if (skinId == null) {
      lo.remove(key);
    } else {
      lo[key] = skinId;
    }
    p.setLoadout(v.id, lo);
  }

  /// Skins for [slot] that fit [v] and are currently listed (enabled, in window) or already owned.
  static List<Skin> skinsFor(ContentDb db, PlayerProfile p, Vehicle v, String slot) {
    final out = db.skins.where((s) => s.slot == slot && s.fits(v) && (ownsSkin(p, s) || db.itemAvailable(s))).toList();
    const order = {'common': 0, 'rare': 1, 'legendary': 2};
    out.sort((a, b) {
      final oa = ownsSkin(p, a) ? 0 : 1, ob = ownsSkin(p, b) ? 0 : 1;
      if (oa != ob) return oa.compareTo(ob);
      final r = (order[a.rarity] ?? 0).compareTo(order[b.rarity] ?? 0);
      return r != 0 ? r : a.id.compareTo(b.id);
    });
    return out;
  }

  // ------------------------------------------------------------------ daily deals
  static const dealDiscount = 0.25;

  /// Three rotating discounted items, identical for everybody on the same day; owned / unavailable items are skipped.
  static List<CatalogItem> dailyDeals(ContentDb db, PlayerProfile p, String dayKey, {DateTime? now}) {
    final pool = <CatalogItem>[
      ...db.skins.where((s) => availability(db, p, s, now: now).canBuy),
      ...db.outfits.where((o) => availability(db, p, o, now: now).canBuy),
    ]..sort((a, b) => a.id.compareTo(b.id));
    if (pool.isEmpty) return const [];
    final out = <CatalogItem>[];
    var seed = stableHash('deals$dayKey');
    final taken = <int>{};
    while (out.length < 3 && taken.length < pool.length) {
      final i = seed % pool.length;
      seed = stableHash('$seed|${out.length}|$dayKey');
      if (taken.add(i)) out.add(pool[i]);
    }
    return out;
  }

  static Price dealPrice(CatalogItem i) => Price((i.price.coins * (1 - dealDiscount)).round(), (i.price.gems * (1 - dealDiscount)).round());

  static BuyResult convertGemsToCoins(PlayerProfile p, int gems, int coins) {
    if (p.gems < gems) return BuyResult.notEnoughGems;
    p.spend(gems: gems);
    p.addCoins(coins);
    return BuyResult.ok;
  }

  // ------------------------------------------------------------------ chests
  static int chestsOwned(PlayerProfile p, String id) => p.counter('ch_${id}_g') - p.counter('ch_${id}_o');
  static void grantChest(PlayerProfile p, String id, [int n = 1]) => p.addCounter('ch_${id}_g', n);
}

class ChestReward {
  int coins = 0, gems = 0;
  String? skinId;
  int duplicateCoins = 0; // coins paid instead of a duplicate skin
  bool get isSkin => skinId != null;
}

class Chests {
  /// Rolls a chest. Mutates [p] (grants the loot and marks the chest opened).
  static ChestReward open(ContentDb db, PlayerProfile p, Map<String, dynamic> def, Random rnd) {
    final drops = (def['drops'] as List).cast<Map>();
    final total = drops.fold<int>(0, (a, d) => a + (d['w'] as num).toInt());
    var roll = rnd.nextInt(max(1, total));
    Map drop = drops.first;
    for (final d in drops) {
      roll -= (d['w'] as num).toInt();
      if (roll < 0) {
        drop = d;
        break;
      }
    }
    final r = ChestReward();
    int range(dynamic v) {
      final l = (v as List).map((e) => (e as num).toInt()).toList();
      return l[0] + rnd.nextInt(max(1, l[1] - l[0] + 1));
    }

    if (drop['coins'] != null) r.coins = range(drop['coins']);
    if (drop['gems'] != null) r.gems = range(drop['gems']);
    if (drop['skinRarity'] != null) {
      final pool = db.skins.where((s) => s.rarity == drop['skinRarity'] && !s.isExclusive && db.itemAvailable(s) && !Economy.ownsSkin(p, s) && !s.price.free).toList();
      if (pool.isEmpty) {
        // everything of that rarity is owned: pay the skin's value in coins instead
        final all = db.skins.where((s) => s.rarity == drop['skinRarity'] && !s.isExclusive).toList();
        final v = all.isEmpty ? 1000 : all[rnd.nextInt(all.length)].price.coins;
        r.duplicateCoins = max(300, (v * 0.4).round());
        r.coins += r.duplicateCoins;
      } else {
        r.skinId = pool[rnd.nextInt(pool.length)].id;
        p.grantSkin(r.skinId!);
      }
    }
    if (r.coins > 0) p.addCoins(r.coins);
    if (r.gems > 0) p.addGems(r.gems);
    final id = def['id'] as String;
    p.addCounter('ch_${id}_o', 1);
    p.addCounter('chests_opened', 1);
    return r;
  }
}
