import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/data/merge/profile_merge.dart';
import 'package:type_racer_legends/data/models/profile.dart';

PlayerProfile mk(String dev) => PlayerProfile.fresh(dev);

void main() {
  group('Wallet & counters', () {
    test('coins and gems are earned/spent counters', () {
      final p = mk('A');
      p.addCoins(500);
      expect(p.coins, 500);
      expect(p.spend(coins: 200), isTrue);
      expect(p.coins, 300);
      expect(p.spend(coins: 1000), isFalse);
      expect(p.coins, 300);
      p.addGems(10);
      expect(p.spend(gems: 11), isFalse);
      expect(p.spend(gems: 4), isTrue);
      expect(p.gems, 6);
    });

    test('level derives from xp', () {
      expect(levelInfoFor(0).level, 1);
      expect(levelInfoFor(119).level, 1);
      expect(levelInfoFor(120).level, 2);
      expect(levelInfoFor(120 + 165).level, 3);
      final li = levelInfoFor(50);
      expect(li.xpInLevel, 50);
      expect(li.progress, closeTo(50 / 120, 1e-9));
    });

    test('rank points never negative', () {
      final p = mk('A');
      p.addRankPoints(30);
      p.addRankPoints(-50);
      expect(p.rankPoints, 0);
    });
  });

  group('Merge (guest -> google, two devices)', () {
    test('coins from both devices are summed without double counting', () {
      final guest = mk('guest-dev')..addCoins(1000);
      final cloud = mk('other-dev')..addCoins(700);
      final merged = ProfileMerger.merge(guest, cloud);
      expect(merged.coins, 1700);
      // merging again (idempotent) must not change the balance
      final again = ProfileMerger.merge(merged, cloud);
      expect(again.coins, 1700);
      final again2 = ProfileMerger.merge(cloud, merged);
      expect(again2.coins, 1700);
    });

    test('same device merged with its own older snapshot keeps the newest balance', () {
      final a = mk('dev')..addCoins(100);
      final older = a.clone();
      a.addCoins(50);
      a.spend(coins: 30);
      final merged = ProfileMerger.merge(older, a);
      expect(merged.coins, 120);
    });

    test('xp, level and best values take the highest; vehicles are unioned; upgrades max', () {
      final a = mk('A')..addXp(500)..setBest('bestWpm', 70)..grantVehicle('c_urban');
      final b = mk('B')..addXp(900)..setBest('bestWpm', 55)..grantVehicle('b_fang')..grantVehicle('c_urban');
      a.vehicleState('c_urban')['upg']['accel'] = 3;
      b.vehicleState('c_urban')['upg']['accel'] = 1;
      b.vehicleState('c_urban')['upg']['nitro'] = 2;
      final m = ProfileMerger.merge(a, b);
      expect(m.xp, 1400); // both devices' XP counted
      expect(m.best('bestWpm'), 70);
      expect(m.ownsVehicle('c_urban') && m.ownsVehicle('b_fang'), isTrue);
      expect(m.upgradeLevel('c_urban', 'accel'), 3);
      expect(m.upgradeLevel('c_urban', 'nitro'), 2);
    });

    test('achievements, skins and flags union; streak picks the most recent', () {
      final a = mk('A');
      final b = mk('B');
      a.m('ach')['a_races_1'] = 100;
      b.m('ach')['a_wins_1'] = 200;
      a.grantSkin('p_red');
      b.grantSkin('p_blue');
      a.setFlag('tutorialDone');
      b.setFlag('adsRemoved');
      a.d['streak'] = {'count': 5, 'best': 9, 'last': '2026-09-20'};
      b.d['streak'] = {'count': 2, 'best': 4, 'last': '2026-09-29'};
      final m = ProfileMerger.merge(a, b);
      expect(m.m('ach').keys, containsAll(['a_races_1', 'a_wins_1']));
      expect(m.ownsSkin('p_red') && m.ownsSkin('p_blue'), isTrue);
      expect(m.flag('tutorialDone') && m.flag('adsRemoved'), isTrue);
      expect(m.d['streak']['count'], 2);
      expect(m.d['streak']['best'], 9);
    });

    test('settings and selection are last-writer-wins', () {
      final a = mk('A')..setSetting('sound', false);
      a.d['settingsAt'] = 1000;
      final b = mk('B')..setSetting('sound', true);
      b.d['settingsAt'] = 2000;
      expect(ProfileMerger.merge(a, b).settings['sound'], true);
      expect(ProfileMerger.merge(b, a).settings['sound'], true);
    });

    test('merge keeps the local deviceId and is commutative for totals', () {
      final a = mk('A')..addCoins(10)..addXp(20);
      final b = mk('B')..addCoins(5)..addXp(40);
      final ab = ProfileMerger.merge(a, b), ba = ProfileMerger.merge(b, a);
      expect(ab.deviceId, 'A');
      expect(ba.deviceId, 'B');
      expect(ab.coins, ba.coins);
      expect(ab.xp, ba.xp);
    });

    test('season: newer season wins, same season unions claims', () {
      final a = mk('A')..d['season'] = {'id': 1, 'premium': false, 'free': [1, 2], 'prem': []};
      final b = mk('B')..d['season'] = {'id': 1, 'premium': true, 'free': [2, 3], 'prem': [1]};
      final m = ProfileMerger.merge(a, b);
      expect(m.d['season']['premium'], true);
      expect((m.d['season']['free'] as List).toSet(), {1, 2, 3});
      final c = mk('C')..d['season'] = {'id': 2, 'premium': false, 'free': [], 'prem': []};
      expect(ProfileMerger.merge(m, c).d['season']['id'], 2);
    });

    test('summary mirrors key values for Firestore rules', () {
      final p = mk('A')..addCoins(300)..addXp(130)..setBest('best_wpm', 88.6);
      final s = ProfileMerger.summary(p);
      expect(s['coins'], 300);
      expect(s['level'], 2);
      expect(s['bestWpm'], 89);
    });
  });

  group('Streak', () {
    test('increments on consecutive days and resets after a gap', () {
      final p = mk('A');
      expect(p.registerActivity(DateTime(2026, 9, 1, 10)), 1);
      expect(p.registerActivity(DateTime(2026, 9, 1, 20)), 1);
      expect(p.registerActivity(DateTime(2026, 9, 2, 9)), 2);
      expect(p.registerActivity(DateTime(2026, 9, 3, 9)), 3);
      expect(p.activeStreak(DateTime(2026, 9, 4)), 3);
      expect(p.activeStreak(DateTime(2026, 9, 6)), 0);
      expect(p.registerActivity(DateTime(2026, 9, 7)), 1);
      expect(p.d['streak']['best'], 3);
    });
  });

  test('clone is deep', () {
    final a = mk('A')..addCoins(5);
    final b = a.clone()..addCoins(5);
    expect(a.coins, 5);
    expect(b.coins, 10);
  });
}
