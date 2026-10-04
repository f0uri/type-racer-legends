import '../ads/ads_ui.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../garage/garage_widgets.dart';
import '../garage/look.dart';
import '../career/progress.dart';
import 'chest_open_screen.dart';
import 'economy.dart';
import 'iap_service.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final enabled = db.featureOn('shop');
    final deals = enabled ? Economy.dailyDeals(db, p, dayKey()) : const <CatalogItem>[];
    final chests = ((db.shop['chests'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final bundles = ((db.shop['coinBundles'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !embedded,
        title: const Text('المتجر'),
        actions: [
          Padding(padding: const EdgeInsets.only(left: 6), child: CurrencyChip(icon: Icons.monetization_on, color: C.gold, value: fmtCompact(p.coins))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: CurrencyChip(icon: Icons.diamond, color: C.cyan, value: fmtCompact(p.gems))),
        ],
      ),
      body: GradientBg(
        child: !enabled
            ? const Center(child: Text('المتجر متوقف مؤقتاً', style: TextStyle(color: C.textDim)))
            : ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: [
                const RewardedAdCard(),
                const SizedBox(height: 12),
                _title('عروض اليوم', 'خصم 25% — تتجدد كل يوم'),
                if (deals.isEmpty) const Panel(child: Text('امتلكت كل العروض المتاحة', style: TextStyle(color: C.textDim))),
                SizedBox(
                  height: 168,
                  child: ListView(scrollDirection: Axis.horizontal, children: [for (final d in deals) _DealCard(item: d)]),
                ),
                const SizedBox(height: 18),
                _title('الصناديق', 'نسب الحصول على الجوائز معروضة بشفافية — تُشترى بالعملات أو الجواهر داخل اللعبة فقط'),
                for (final c in chests) _ChestCard(def: c),
                const SizedBox(height: 18),
                const PremiumSection(),
                const SizedBox(height: 18),
                _title('تحويل الجواهر إلى عملات', null),
                for (final b in bundles) _bundle(context, ref, b, p),
              ]),
      ),
    );
  }

  Widget _title(String t, String? sub) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if (sub != null) Text(sub, style: const TextStyle(color: C.textDim, fontSize: 12)),
        ]),
      );

  Widget _bundle(BuildContext context, WidgetRef ref, Map<String, dynamic> b, PlayerProfile p) {
    final gems = (b['gems'] as num).toInt(), coins = (b['coins'] as num).toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        child: Row(children: [
          const Icon(Icons.monetization_on, size: 28, color: C.gold),
          const SizedBox(width: 10),
          Expanded(child: Text('${fmtInt(coins)} عملة', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          SizedBox(
            width: 120,
            child: NeonButton(
              label: '$gems جوهرة',
              color: C.cyan,
              height: 40,
              onPressed: p.gems < gems
                  ? null
                  : () async {
                      if (!await confirmDialog(context, 'تأكيد', 'تحويل $gems جوهرة إلى ${fmtInt(coins)} عملة؟', ok: 'تحويل')) return;
                      ref.read(profileProvider.notifier).update((pp) => Economy.convertGemsToCoins(pp, gems, coins));
                      ref.read(audioProvider).play(Sfx.coin);
                      if (context.mounted) toast(context, 'تمت إضافة ${fmtInt(coins)} عملة');
                    },
            ),
          ),
        ]),
      ),
    );
  }
}

class _DealCard extends ConsumerWidget {
  const _DealCard({required this.item});
  final CatalogItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final price = Economy.dealPrice(item);
    final v = db.vehicle(p.selVehicle) ?? db.starterCar;
    Widget preview;
    if (item is Skin) {
      final s = item as Skin;
      final fits = s.fits(v) ? v : db.vehicles.firstWhere((x) => s.fits(x), orElse: () => v);
      preview = (s.slot == 'paint' || s.slot == 'rims' || s.slot == 'neon') ? MiniVehicle(look: Look.resolve(db, fits, {s.slot: s.id}), size: 96) : SkinGlyph(skin: s, look: Look.resolve(db, fits, {}));
    } else {
      final o = item as Outfit;
      preview = Icon(Icons.sports_motorsports_rounded, size: 40, color: hexColor(o.params['helmet'] as String?));
    }
    return Container(
      width: 150,
      margin: const EdgeInsets.only(left: 10),
      child: Panel(
        border: C.rarity(item.rarity),
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Expanded(child: Center(child: preview)),
          Text(loc(item.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          RarityBadge(item.rarity),
          const SizedBox(height: 4),
          SizedBox(
            height: 32,
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.gold, foregroundColor: Colors.black, padding: EdgeInsets.zero),
              onPressed: () async {
                if (price.gems > 0 && !await confirmDialog(context, 'تأكيد الشراء', 'سيتم خصم ${price.gems} جوهرة.', ok: 'شراء', okColor: C.gold)) return;
                BuyResult r = BuyResult.ok;
                ref.read(profileProvider.notifier).update((pp) => r = Economy.buy(db, pp, item, discount: Economy.dealDiscount));
                if (!context.mounted) return;
                toast(context, r == BuyResult.ok ? 'تم الشراء' : (r == BuyResult.notEnoughCoins ? 'لا تملك عملات كافية' : (r == BuyResult.notEnoughGems ? 'لا تملك جواهر كافية' : 'غير متاح')));
                if (r == BuyResult.ok) ref.read(audioProvider).play(Sfx.chest);
              },
              child: priceRow(price, color: Colors.black, size: 12),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ChestCard extends ConsumerWidget {
  const _ChestCard({required this.def});
  final Map<String, dynamic> def;

  static String dropLine(Map d, int total) {
    final pct = ((d['w'] as num) / total * 100).toStringAsFixed(0);
    if (d['coins'] != null) return '${(d['coins'] as List).join('–')} عملة  ($pct%)';
    if (d['gems'] != null) return '${(d['gems'] as List).join('–')} جوهرة  ($pct%)';
    return 'عنصر ${rarityLabel(d['skinRarity'] as String)}  ($pct%)';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final id = def['id'] as String;
    final owned = Economy.chestsOwned(p, id);
    final price = Price.from(def['price']);
    final color = hexColor(def['color'] as String?, C.gold);
    final drops = (def['drops'] as List).cast<Map>();
    final total = drops.fold<int>(0, (a, d) => a + (d['w'] as num).toInt());
    final afford = p.coins >= price.coins && p.gems >= price.gems;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        border: color.withValues(alpha: 0.6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 52, height: 44, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color, Color.lerp(color, Colors.black, 0.5)!])), alignment: Alignment.center, child: const Icon(Icons.card_giftcard, size: 22, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(child: Text(loc(def['name']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            if (owned > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: C.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.green)), child: Text('لديك $owned', style: const TextStyle(color: C.green, fontWeight: FontWeight.w900, fontSize: 12))),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 2, children: [for (final d in drops) Text(dropLine(d, total), style: const TextStyle(color: C.textDim, fontSize: 11))]),
          const SizedBox(height: 8),
          Row(children: [
            if (owned > 0) Expanded(child: NeonButton(label: 'افتح صندوقاً', height: 42, color: C.green, onPressed: () => ChestFlow.open(context, ref, def, fromInventory: true))),
            if (owned > 0) const SizedBox(width: 8),
            Expanded(child: NeonButton(label: 'شراء وفتح  ${priceText(price)}', height: 42, color: C.gold, filled: owned == 0, onPressed: afford ? () => ChestFlow.open(context, ref, def, fromInventory: false) : null)),
          ]),
        ]),
      ),
    );
  }
}

class ChestFlow {
  /// Opens a chest (spending currency when not taken from the inventory) and plays the animation.
  static Future<void> open(BuildContext context, WidgetRef ref, Map<String, dynamic> def, {required bool fromInventory}) async {
    final db = ref.read(contentProvider);
    final price = Price.from(def['price']);
    ChestReward? reward;
    final id = def['id'] as String;
    ref.read(profileProvider.notifier).update((p) {
      if (fromInventory) {
        if (Economy.chestsOwned(p, id) <= 0) return;
      } else {
        if (p.coins < price.coins || p.gems < price.gems) return;
        p.spend(coins: price.coins, gems: price.gems);
        Economy.grantChest(p, id);
      }
      reward = Chests.open(db, p, def, Random());
    });
    if (reward == null || !context.mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ChestOpenScreen(def: def, reward: reward!)));
  }
}

/// Real-money items (Google Play Billing): remove ads, gem packs and the Battle Pass. No randomised items are sold for money.
class PremiumSection extends ConsumerStatefulWidget {
  const PremiumSection({super.key});
  @override
  ConsumerState<PremiumSection> createState() => _PremiumSectionState();
}

class _PremiumSectionState extends ConsumerState<PremiumSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(iapProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final iap = ref.watch(iapProvider);
    if (!db.featureOn('iap')) return const SizedBox.shrink();
    final packs = ((db.shop['gemPacks'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final products = (db.shop['products'] as Map?) ?? const {};
    final removeAds = products['removeAds'] as String? ?? 'remove_ads';
    final pass = db.season['premiumProduct'] as String? ?? 'battle_pass_premium';
    ref.listen<IapState>(iapProvider, (prev, next) {
      if (next.message != null && next.message != prev?.message && context.mounted) toast(context, next.message!);
    });
    Widget row(IconData icon, String title, String sub, String id, {bool owned = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            child: Row(children: [
              Icon(icon, size: 28, color: C.gold),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), Text(sub, style: const TextStyle(color: C.textDim, fontSize: 11))])),
              SizedBox(
                width: 112,
                child: owned
                    ? const Center(child: Text('مفعّل', style: TextStyle(color: C.green, fontWeight: FontWeight.w900)))
                    : NeonButton(label: iap.priceOf(id) ?? '—', height: 38, color: C.gold, busy: iap.loading, onPressed: iap.canBuy(id) ? () => ref.read(iapProvider.notifier).buy(id) : null),
              ),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('العروض المميزة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
      if (!iap.available) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(iap.message ?? 'جارٍ الاتصال بالمتجر...', style: const TextStyle(color: C.textDim, fontSize: 12))),
      row(Icons.block, 'إزالة الإعلانات', 'الإعلانات اختيارية أصلاً؛ هذا يخفيها نهائياً', removeAds, owned: p.flag('adsRemoved')),
      row(Icons.card_membership, 'Battle Pass المميز', 'مكافآت إضافية طوال الموسم', pass, owned: Season.isPremium(db, p)),
      for (final g in packs) row(Icons.diamond, '${g['gems']} جوهرة', loc(g['name']), g['id'] as String),
      TextButton(onPressed: () => ref.read(iapProvider.notifier).restore(), child: const Text('استعادة المشتريات')),
    ]);
  }
}
