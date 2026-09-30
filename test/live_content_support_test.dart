import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/remote_settings.dart';
import 'package:type_racer_legends/data/models/profile.dart';
import 'package:type_racer_legends/features/content/new_items.dart';
import 'package:type_racer_legends/features/race/race_outcome.dart';
import 'modes_logic_test.dart' show res;
import 'test_support.dart';

void main() {
  final db = loadSeedContent();

  test('remote settings parse csv, json kill switch and numeric overrides; junk is ignored', () {
    final r = RemoteSettings.fromMap({
      'kill_features': 'ads, tournament',
      'kill_items': 'c_apex',
      'kill_switch': '{"features":["combat"],"items":["p_gold"]}',
      'min_supported_version': '120',
      'daily_coin_cap': '1800',
      'interstitial_every_n': '5',
      'interstitial_enabled': 'false',
      'rewarded_daily_limit': 'abc',
      'maintenance_message': '',
    });
    expect(r.killFeatures, {'ads', 'tournament', 'combat'});
    expect(r.killItems, {'c_apex', 'p_gold'});
    expect(r.minSupportedVersion, 120);
    expect(r.dailyCoinCap, 1800);
    expect(r.interstitialEveryN, 5);
    expect(r.interstitialEnabled, isFalse);
    expect(r.rewardedDailyLimit, isNull);
    expect(r.maintenanceMessage, isNull);
    expect(RemoteSettings.fromMap({'kill_switch': '{not json'}).killFeatures, isEmpty);
    expect(RemoteSettings.empty.economyPatch, isEmpty);
  });

  test('remote overrides: kill switch disables features/items and economy patches change the rules', () {
    final r = RemoteSettings.fromMap({'kill_features': 'ads', 'kill_items': 'c_apex', 'daily_coin_cap': '100', 'interstitial_every_n': '9'});
    final d = db.withOverrides(killFeatures: r.killFeatures, killItems: r.killItems, economyPatch: r.economyPatch);
    expect(db.featureOn('ads'), isTrue);
    expect(d.featureOn('ads'), isFalse);
    expect(d.itemAvailable(d.vehicle('c_apex')!), isFalse);
    expect(db.itemAvailable(db.vehicle('c_apex')!), isTrue);
    expect(d.econ('race')['dailyCoinCap'], 100);
    expect(d.econ('race')['baseCoins'], db.econ('race')['baseCoins']); // untouched keys survive
    expect(d.econ('ads')['interstitialEveryNRaces'], 9);
    // the daily cap override is honoured by the reward code
    final p = PlayerProfile.fresh('d');
    p.addCounter('dc_20260930', 100);
    final o = RaceRewards.apply(p, res(), d, now: DateTime(2026, 9, 30, 12));
    expect(o.capped, isTrue);
  });

  test('new-item badges: the shipped catalog is the baseline, later additions are NEW until seen', () {
    final p = PlayerProfile.fresh('d');
    expect(NewItems.unseen(db, p), isEmpty); // before the baseline nothing is flagged
    expect(NewItems.ensureBaseline(db, p), isTrue);
    expect(NewItems.ensureBaseline(db, p), isFalse);
    expect(NewItems.unseen(db, p), isEmpty);
    // a live update adds a vehicle
    final bigger = db.withOverrides(); // same content
    expect(bigger.vehicles.length, db.vehicles.length);
    p.m('seenItems').remove('c_urban');
    expect(NewItems.unseen(db, p), {'c_urban'});
    expect(NewItems.isNew(p, 'c_urban'), isTrue);
    NewItems.markSeen(p, ['c_urban']);
    expect(NewItems.unseen(db, p), isEmpty);
  });
}

