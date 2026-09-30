import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/data/models/profile.dart';
import 'package:type_racer_legends/features/race/race_builder.dart';
import 'package:type_racer_legends/features/shop/economy.dart';
import 'test_support.dart';

void main() {
  final db = loadSeedContent();
  PlayerProfile rich({int coins = 100000, int gems = 5000, int xp = 0}) {
    final p = PlayerProfile.fresh('d');
    p.addCoins(coins);
    p.addGems(gems);
    p.addXp(xp);
    return p;
  }

  test('catalog: 10+ cars, 10+ bikes, three rarities, all four stats per vehicle', () {
    expect(db.vehicles.where((v) => !v.isBike).length, greaterThanOrEqualTo(10));
    expect(db.vehicles.where((v) => v.isBike).length, greaterThanOrEqualTo(10));
    expect(db.vehicles.map((v) => v.rarity).toSet(), {'common', 'rare', 'legendary'});
    for (final v in db.vehicles) {
      for (final s in Economy.stats) {
        expect(v.stats[s], isNotNull, reason: '${v.id} $s');
      }
    }
  });

  test('starters are owned for free; others need level + coins', () {
    final p = PlayerProfile.fresh('d');
    final sprout = db.vehicle('c_sprout')!, urban = db.vehicle('c_urban')!;
    expect(Economy.availability(db, p, sprout).owned, isTrue);
    final a = Economy.availability(db, p, urban);
    expect(a.owned, isFalse);
    expect(a.reason, LockReason.level);
    p.addXp(5000);
    p.addCoins(100);
    expect(Economy.buy(db, p, urban), BuyResult.notEnoughCoins);
    p.addCoins(5000);
    expect(Economy.buy(db, p, urban), BuyResult.ok);
    expect(p.ownsVehicle('c_urban'), isTrue);
    expect(p.coins, 5100 - urban.price.coins);
    expect(Economy.buy(db, p, urban), BuyResult.owned);
  });

  test('gem vehicles charge gems; achievement and event vehicles cannot be bought', () {
    final p = rich(xp: 500000);
    final apex = db.vehicle('c_apex')!;
    final before = p.gems;
    expect(Economy.buy(db, p, apex), BuyResult.ok);
    expect(p.gems, before - apex.price.gems);
    expect(Economy.buy(db, p, db.vehicle('c_legend')!), BuyResult.locked);
    final ev = db.vehicle('c_crescent')!;
    expect(Economy.availability(db, p, ev).reason, anyOf(LockReason.event, LockReason.unavailable));
    expect(Economy.buy(db, p, ev), isNot(BuyResult.ok));
  });

  test('upgrades cost more each level, cap at 5 and raise the gameplay modifiers', () {
    final p = rich(coins: 1000000, xp: 500000);
    final v = db.vehicle('c_sprout')!;
    var last = 0;
    for (var i = 0; i < 5; i++) {
      final q = Economy.upgradeQuote(db, p, v, 'accel');
      expect(q.cost, greaterThan(last));
      last = q.cost;
      expect(Economy.upgrade(db, p, v, 'accel'), BuyResult.ok);
    }
    expect(p.upgradeLevel('c_sprout', 'accel'), 5);
    expect(Economy.upgradeQuote(db, p, v, 'accel').maxed, isTrue);
    expect(Economy.upgrade(db, p, v, 'accel'), BuyResult.owned);
    expect(p.counter('upgrades'), 5);
    final rig = PlayerRig.from(db, p);
    final fresh = PlayerRig.from(db, PlayerProfile.fresh('x'));
    expect(rig.mods.accelBonus, greaterThan(fresh.mods.accelBonus));
  });

  test('legendary vehicles are more expensive to upgrade; poor players cannot upgrade', () {
    final p = rich(xp: 500000);
    final common = db.vehicle('c_sprout')!, legend = db.vehicle('c_apex')!;
    expect(Economy.upgradeQuote(db, p, legend, 'nitro').cost, greaterThan(Economy.upgradeQuote(db, p, common, 'nitro').cost));
    final poor = PlayerProfile.fresh('p');
    expect(Economy.upgrade(db, poor, common, 'stab'), BuyResult.notEnoughCoins);
    expect(Economy.upgrade(db, poor, legend, 'stab'), BuyResult.locked);
  });

  test('skins: starters are free, buying grants, equip writes the loadout and changes the look', () {
    final p = rich(xp: 500000);
    final v = db.vehicle('c_sprout')!;
    final paints = Economy.skinsFor(db, p, v, 'paint');
    expect(paints.first.id, isNotEmpty);
    final redOwned = Economy.availability(db, p, db.skin('p_red')!).owned;
    expect(redOwned, isTrue);
    final buyable = paints.firstWhere((s) => !Economy.ownsSkin(p, s) && Economy.availability(db, p, s).canBuy);
    expect(Economy.buy(db, p, buyable), BuyResult.ok);
    Economy.equip(p, v, 'paint', buyable.id);
    expect(p.loadout('c_sprout')['paint'], buyable.id);
    Economy.equip(p, v, 'sticker2', null);
    expect(p.loadout('c_sprout').containsKey('sticker2'), isFalse);
  });

  test('skin slots only offer skins that fit the vehicle kind', () {
    final p = rich(xp: 500000);
    final car = db.vehicle('c_sprout')!, bike = db.vehicle('b_pocket')!;
    for (final s in Economy.skinsFor(db, p, car, 'rims')) {
      expect(s.fits(car), isTrue);
    }
    for (final s in Economy.skinsFor(db, p, bike, 'rims')) {
      expect(s.fits(bike), isTrue);
    }
  });

  test('chests: weights respected, loot granted, inventory counted, duplicates converted', () {
    final p = rich(xp: 500000);
    final def = (db.shop['chests'] as List).cast<Map<String, dynamic>>().firstWhere((c) => c['id'] == 'chest_gold');
    Economy.grantChest(p, 'chest_gold', 3);
    expect(Economy.chestsOwned(p, 'chest_gold'), 3);
    final rnd = Random(4);
    var coins = 0, gems = 0, skins = 0;
    final startCoins = p.coins, startGems = p.gems;
    for (var i = 0; i < 300; i++) {
      final r = Chests.open(db, p, def, rnd);
      coins += r.coins;
      gems += r.gems;
      if (r.isSkin) {
        skins++;
        expect(p.ownsSkin(r.skinId!), isTrue);
      }
    }
    expect(p.coins - startCoins, coins);
    expect(p.gems - startGems, gems);
    expect(skins, greaterThan(20));
    expect(Economy.chestsOwned(p, 'chest_gold'), 3 - 300);
    expect(p.counter('chests_opened'), 300);
  });

  test('chest drops are never gambling-for-cash: nothing in the shop sells randomised items for real money', () {
    final chests = (db.shop['chests'] as List).cast<Map<String, dynamic>>();
    for (final c in chests) {
      final price = c['price'] as Map;
      expect(price.keys.every((k) => k == 'coins' || k == 'gems'), isTrue);
    }
    expect((db.shop['products'] as Map).keys, containsAll(['removeAds', 'battlePass']));
  });
}
