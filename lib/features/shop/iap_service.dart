import '../../core/services/analytics_provider.dart';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../core/providers.dart';
import '../../data/models/profile.dart';
import '../../data/remote/firebase_boot.dart';
import '../career/progress.dart';
import '../content/content_db.dart';

/// Abstraction over the store so the delivery logic is testable.
abstract class IapPlatform {
  Future<bool> isAvailable();
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<Map<String, ProductDetails>> query(Set<String> ids);
  Future<bool> buy(ProductDetails product, {required bool consumable});
  Future<void> complete(PurchaseDetails p);
  Future<void> restore();
}

class StorePlatform implements IapPlatform {
  final InAppPurchase _iap = InAppPurchase.instance;
  @override
  Future<bool> isAvailable() => _iap.isAvailable();
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;
  @override
  Future<Map<String, ProductDetails>> query(Set<String> ids) async {
    final r = await _iap.queryProductDetails(ids);
    return {for (final d in r.productDetails) d.id: d};
  }

  @override
  Future<bool> buy(ProductDetails product, {required bool consumable}) {
    final param = PurchaseParam(productDetails: product);
    return consumable ? _iap.buyConsumable(purchaseParam: param) : _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> complete(PurchaseDetails p) => _iap.completePurchase(p);
  @override
  Future<void> restore() => _iap.restorePurchases();
}

class IapDelivery {
  /// Gives the player what [productId] sells. Idempotent per [purchaseId]. Returns false for unknown products.
  static bool deliver(PlayerProfile p, ContentDb db, String productId, String purchaseId, {DateTime? now}) {
    final flag = 'iap_${purchaseId.isEmpty ? productId : purchaseId}';
    if (p.flag(flag)) return true; // already delivered
    final packs = ((db.shop['gemPacks'] as List?) ?? const []).cast<Map>();
    final products = (db.shop['products'] as Map?) ?? const {};
    final pack = packs.where((e) => e['id'] == productId).firstOrNull;
    if (pack != null) {
      p.addGems((pack['gems'] as num).toInt());
    } else if (productId == products['removeAds']) {
      p.setFlag('adsRemoved');
    } else if (productId == (db.season['premiumProduct'] ?? products['battlePass'])) {
      Season.grantPremium(p, db, now);
    } else {
      return false;
    }
    p.setFlag(flag);
    p.addCounter('iap_purchases', 1);
    return true;
  }

  static Set<String> productIds(ContentDb db) {
    final packs = ((db.shop['gemPacks'] as List?) ?? const []).cast<Map>().map((e) => e['id'] as String);
    final products = ((db.shop['products'] as Map?) ?? const {}).values.whereType<String>();
    return {...packs, ...products, db.season['premiumProduct'] as String? ?? 'battle_pass_premium'};
  }

  static bool isConsumable(ContentDb db, String id) => ((db.shop['gemPacks'] as List?) ?? const []).cast<Map>().any((e) => e['id'] == id);
}

class IapState {
  final bool available;
  final bool loading;
  final Map<String, ProductDetails> products;
  final String? message;
  const IapState({this.available = false, this.loading = false, this.products = const {}, this.message});
  IapState copy({bool? available, bool? loading, Map<String, ProductDetails>? products, String? message}) => IapState(available: available ?? this.available, loading: loading ?? this.loading, products: products ?? this.products, message: message);

  String? priceOf(String id) => products[id]?.price;
  bool canBuy(String id) => available && products.containsKey(id) && !loading;
}

final iapPlatformProvider = Provider<IapPlatform>((ref) => StorePlatform());

class IapController extends Notifier<IapState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _started = false;

  @override
  IapState build() {
    ref.onDispose(() => _sub?.cancel());
    return const IapState();
  }

  /// Connects to the store (safe to call repeatedly; silently unavailable on devices without Google Play).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final platform = ref.read(iapPlatformProvider);
    try {
      if (!await platform.isAvailable()) {
        state = const IapState(message: 'المتجر غير متاح على هذا الجهاز');
        return;
      }
      _sub = platform.purchaseStream.listen(_onPurchases, onError: (Object e) => debugPrint('iap stream error: $e'));
      final db = ref.read(contentProvider);
      final products = await platform.query(IapDelivery.productIds(db));
      state = IapState(available: true, products: products, message: products.isEmpty ? 'لم يتم إعداد المنتجات في Google Play بعد' : null);
    } catch (e) {
      debugPrint('iap unavailable: $e');
      state = IapState(message: 'تعذّر الاتصال بالمتجر');
    }
  }

  Future<void> buy(String productId) async {
    final d = state.products[productId];
    if (d == null || !state.available) return;
    state = state.copy(loading: true);
    try {
      await ref.read(iapPlatformProvider).buy(d, consumable: IapDelivery.isConsumable(ref.read(contentProvider), productId));
    } catch (e) {
      state = state.copy(loading: false, message: 'تعذّر بدء عملية الشراء');
    }
  }

  Future<void> restore() async {
    try {
      await ref.read(iapPlatformProvider).restore();
    } catch (e) {
      debugPrint('restore failed: $e');
    }
  }

  Future<bool> _verify(PurchaseDetails pd) async {
    if (!FirebaseBoot.available) return true;
    try {
      final r = await FirebaseFunctions.instance.httpsCallable('verifyPurchase', options: HttpsCallableOptions(timeout: const Duration(seconds: 12))).call<Map<dynamic, dynamic>>({
        'productId': pd.productID,
        'purchaseToken': pd.verificationData.serverVerificationData,
        'source': pd.verificationData.source,
      });
      return r.data['valid'] != false;
    } catch (e) {
      // verification service not reachable / not deployed yet: deliver (the store already charged the user)
      debugPrint('verifyPurchase unavailable: $e');
      return true;
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    final db = ref.read(contentProvider);
    for (final pd in list) {
      switch (pd.status) {
        case PurchaseStatus.pending:
          state = state.copy(loading: true);
          break;
        case PurchaseStatus.error:
          state = state.copy(loading: false, message: 'لم تكتمل عملية الشراء');
          if (pd.pendingCompletePurchase) await ref.read(iapPlatformProvider).complete(pd);
          break;
        case PurchaseStatus.canceled:
          state = state.copy(loading: false);
          if (pd.pendingCompletePurchase) await ref.read(iapPlatformProvider).complete(pd);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final ok = await _verify(pd);
          if (ok) {
            var delivered = false;
            ref.read(profileProvider.notifier).update((p) => delivered = IapDelivery.deliver(p, db, pd.productID, pd.purchaseID ?? '${pd.productID}_${pd.transactionDate}'));
            if (delivered) ref.read(analyticsProvider).log('purchase', {'product': pd.productID});
            state = state.copy(loading: false, message: delivered ? 'تمت العملية بنجاح 🎉' : 'منتج غير معروف');
            ref.read(profileProvider.notifier).syncNow();
          } else {
            state = state.copy(loading: false, message: 'فشل التحقق من عملية الشراء');
          }
          if (pd.pendingCompletePurchase) await ref.read(iapPlatformProvider).complete(pd);
          break;
      }
    }
  }
}

final iapProvider = NotifierProvider<IapController, IapState>(IapController.new);
