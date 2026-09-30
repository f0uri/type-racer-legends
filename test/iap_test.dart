import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:type_racer_legends/core/providers.dart';
import 'package:type_racer_legends/data/local/local_store.dart';
import 'package:type_racer_legends/data/models/profile.dart';
import 'package:type_racer_legends/features/career/progress.dart';
import 'package:type_racer_legends/features/shop/iap_service.dart';
import 'test_support.dart';

class FakePlatform implements IapPlatform {
  final ctrl = StreamController<List<PurchaseDetails>>.broadcast();
  bool available = true;
  final completed = <String>[];
  final bought = <String>[];
  final catalog = <String, ProductDetails>{};
  @override
  Future<bool> isAvailable() async => available;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => ctrl.stream;
  @override
  Future<Map<String, ProductDetails>> query(Set<String> ids) async => {for (final i in ids) if (catalog.containsKey(i)) i: catalog[i]!};
  @override
  Future<bool> buy(ProductDetails product, {required bool consumable}) async {
    bought.add('${product.id}:${consumable ? 'c' : 'n'}');
    return true;
  }

  @override
  Future<void> complete(PurchaseDetails p) async => completed.add(p.purchaseID ?? '');
  @override
  Future<void> restore() async {}
}

PurchaseDetails pd(String product, String id, {PurchaseStatus status = PurchaseStatus.purchased}) => PurchaseDetails(
      productID: product,
      purchaseID: id,
      verificationData: PurchaseVerificationData(localVerificationData: 'l', serverVerificationData: 'tok', source: 'google_play'),
      transactionDate: '1',
      status: status,
    )..pendingCompletePurchase = true;

ProductDetails product(String id, String price) => ProductDetails(id: id, title: id, description: id, price: price, rawPrice: 1, currencyCode: 'USD');

void main() {
  final db = loadSeedContent();

  group('delivery', () {
    test('gem packs credit gems exactly once per purchase id', () {
      final p = PlayerProfile.fresh('d');
      expect(IapDelivery.deliver(p, db, 'gems_medium', 'order1'), isTrue);
      expect(p.gems, 650);
      expect(IapDelivery.deliver(p, db, 'gems_medium', 'order1'), isTrue); // replayed stream event
      expect(p.gems, 650);
      IapDelivery.deliver(p, db, 'gems_medium', 'order2');
      expect(p.gems, 1300);
    });

    test('remove ads sets the flag, battle pass activates premium for the current season', () {
      final p = PlayerProfile.fresh('d');
      expect(IapDelivery.deliver(p, db, 'remove_ads', 'o1'), isTrue);
      expect(p.flag('adsRemoved'), isTrue);
      final now = DateTime(2026, 10, 3);
      expect(IapDelivery.deliver(p, db, 'battle_pass_premium', 'o2', now: now), isTrue);
      expect(Season.isPremium(db, p, now), isTrue);
    });

    test('unknown products are rejected and nothing changes', () {
      final p = PlayerProfile.fresh('d');
      expect(IapDelivery.deliver(p, db, 'free_money', 'x'), isFalse);
      expect(p.gems, 0);
    });

    test('product ids come from the shop catalog and gem packs are the only consumables', () {
      final ids = IapDelivery.productIds(db);
      expect(ids, containsAll(['remove_ads', 'battle_pass_premium', 'gems_small', 'gems_medium', 'gems_large']));
      expect(IapDelivery.isConsumable(db, 'gems_small'), isTrue);
      expect(IapDelivery.isConsumable(db, 'remove_ads'), isFalse);
    });
  });

  group('controller', () {
    late ProviderContainer c;
    late FakePlatform fake;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('trl_iap');
      final store = await LocalStore.forTest(dir.path);
      fake = FakePlatform()
        ..catalog['gems_small'] = product('gems_small', r'$0.99')
        ..catalog['remove_ads'] = product('remove_ads', r'$2.99');
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store), initialContentProvider.overrideWithValue(db), iapPlatformProvider.overrideWithValue(fake)]);
    });
    tearDown(() async {
      c.dispose();
      await Hive.close();
    });

    test('loads the products that exist in the store and reports missing ones', () async {
      await c.read(iapProvider.notifier).start();
      final s = c.read(iapProvider);
      expect(s.available, isTrue);
      expect(s.priceOf('gems_small'), r'$0.99');
      expect(s.canBuy('gems_small'), isTrue);
      expect(s.canBuy('gems_large'), isFalse);
    });

    test('stores without billing leave the shop usable with a message', () async {
      fake.available = false;
      await c.read(iapProvider.notifier).start();
      expect(c.read(iapProvider).available, isFalse);
      expect(c.read(iapProvider).message, isNotNull);
    });

    test('purchase flow: buy -> stream event -> delivery -> completion acknowledged', () async {
      await c.read(iapProvider.notifier).start();
      await c.read(iapProvider.notifier).buy('gems_small');
      expect(fake.bought, ['gems_small:c']);
      fake.ctrl.add([pd('gems_small', 'GPA.1')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(profileProvider).gems, 120);
      expect(fake.completed, ['GPA.1']);
      // duplicate delivery of the same order (app restart) does not pay twice
      fake.ctrl.add([pd('gems_small', 'GPA.1')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(profileProvider).gems, 120);
    });

    test('cancelled and failed purchases deliver nothing', () async {
      await c.read(iapProvider.notifier).start();
      fake.ctrl.add([pd('gems_small', 'GPA.2', status: PurchaseStatus.canceled), pd('gems_small', 'GPA.3', status: PurchaseStatus.error)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(profileProvider).gems, 0);
      expect(c.read(iapProvider).loading, isFalse);
    });

    test('restored purchases re-apply non-consumables', () async {
      await c.read(iapProvider.notifier).start();
      fake.ctrl.add([pd('remove_ads', 'GPA.9', status: PurchaseStatus.restored)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(profileProvider).flag('adsRemoved'), isTrue);
    });
  });
}
