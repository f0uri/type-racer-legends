import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/services/analytics_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'ad_policy.dart';
import 'ads_service.dart';

/// Optional "watch an ad for coins" card. Hidden when ads are off / removed; explains it is optional.
class RewardedAdCard extends ConsumerStatefulWidget {
  const RewardedAdCard({super.key, this.doubleCoins, this.onGranted, this.compactLabel});

  /// When set, the ad doubles these coins (results screen) instead of granting the standard bonus.
  final int? doubleCoins;
  final void Function(int coins)? onGranted;
  final String? compactLabel;

  @override
  ConsumerState<RewardedAdCard> createState() => _RewardedAdCardState();
}

class _RewardedAdCardState extends ConsumerState<RewardedAdCard> {
  bool busy = false, done = false;

  Future<void> _watch() async {
    setState(() => busy = true);
    final ads = ref.read(adsProvider);
    await ads.init();
    final ok = await ads.showRewarded();
    if (!mounted) return;
    if (ok) {
      var got = 0;
      ref.read(profileProvider.notifier).update((p) => got = AdPolicy.grantRewarded(ref.read(contentProvider), p, coins: widget.doubleCoins));
      ref.read(analyticsProvider).log('ad_reward', {'coins': got});
      setState(() => done = true);
      widget.onGranted?.call(got);
      toast(context, got > 0 ? 'حصلت على $got عملة 🪙' : 'بلغت الحد اليومي للمكافآت الإعلانية');
    } else {
      toast(context, 'لا يتوفر إعلان الآن — جرّب لاحقاً');
    }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final left = AdPolicy.rewardedLeft(db, p);
    if (!AdPolicy.enabled(db, p) || !ref.read(adsProvider).supported) return const SizedBox.shrink();
    if (done || left <= 0) {
      return widget.doubleCoins != null ? const SizedBox.shrink() : Panel(child: Text(left <= 0 ? '🎬 استهلكت مكافآت الإعلانات لهذا اليوم. عد غداً!' : '✅ تم', style: const TextStyle(color: C.textDim)));
    }
    final coins = widget.doubleCoins ?? AdPolicy.rewardedCoins(db);
    return Panel(
      border: C.gold.withValues(alpha: 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.compactLabel ?? (widget.doubleCoins != null ? '🎬 ضاعف عملات هذا السباق' : '🎬 مكافأة مجانية'), style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('اختياري تماماً: شاهد إعلاناً قصيراً لتحصل على +$coins عملة. المتبقي اليوم: $left', style: const TextStyle(color: C.textDim, fontSize: 12)),
        const SizedBox(height: 8),
        NeonButton(label: 'شاهد واربح +$coins', icon: Icons.play_circle_rounded, color: C.gold, busy: busy, height: 46, onPressed: _watch),
      ]),
    );
  }
}
