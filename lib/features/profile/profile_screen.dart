import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/countries.dart';
import '../../core/util/misc.dart';
import '../auth/auth_controller.dart';
import '../../core/widgets/common.dart';
import '../career/rank.dart';
import '../learn/learn_screens.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import 'card_builder.dart';
import 'referral_service.dart';
import 'share_card.dart';

final referralProvider = Provider<ReferralService>((ref) => ReferralService(ref.watch(cloudSyncProvider)));

/// Player profile tab: identity, rank, stats, weekly goal, player card, invites, certificates.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final codeCtl = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    codeCtl.dispose();
    super.dispose();
  }

  Future<void> _shareCard() async {
    setState(() => busy = true);
    try {
      final db = ref.read(contentProvider);
      await ShareCardRenderer.share(CardBuilder.player(db, ref.read(profileProvider)), text: 'هذه بطاقتي في ${AppConfig.appName}');
    } catch (_) {
      if (mounted) toast(context, 'تعذّرت مشاركة البطاقة');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _redeem() async {
    final code = codeCtl.text.trim();
    if (code.length < 4) {
      toast(context, 'اكتب رمز صديقك أولاً');
      return;
    }
    setState(() => busy = true);
    final r = await ref.read(referralProvider).redeem(code);
    if (!mounted) return;
    if (r.ok) {
      ref.read(profileProvider.notifier).update((p) => p.setFlag(ReferralService.redeemedFlag));
      codeCtl.clear();
    }
    setState(() => busy = false);
    toast(context, r.message);
  }

  Future<void> _claim() async {
    setState(() => busy = true);
    final r = await ref.read(referralProvider).claim();
    if (!mounted) return;
    if (r.coins > 0 || r.gems > 0) ref.read(profileProvider.notifier).update((p) => ReferralService.apply(p, r));
    setState(() => busy = false);
    toast(context, r.message);
  }

  void _nav(Widget w) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(profileProvider);
    final db = ref.watch(contentProvider);
    final li = ref.watch(levelInfoProvider);
    final tier = Ranks.tierOf(db, p.rankPoints);
    final next = Ranks.nextAt(db, p.rankPoints);
    final auth = ref.watch(authProvider);
    final redeemed = p.flag(ReferralService.redeemedFlag);
    final minLevel = (db.economy['referral'] as Map?)?['level'] ?? 5;
    final certs = p.m('certs').length;
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
            Row(children: [
              const Expanded(child: Text('ملفي', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
              IconButton(icon: const Icon(Icons.settings), onPressed: () => _nav(const SettingsScreen())),
            ]),
            Panel(
              child: Column(children: [
                Row(children: [
                  CircleAvatar(radius: 34, backgroundColor: C.surface2, child: Icon(avatars[p.avatar % avatars.length], size: 32, color: C.cyan)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p.country.isEmpty ? '' : '${flagEmoji(p.country)} '}${p.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      Text(CardBuilder.titleLabel(db, p), style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800)),
                      Text(auth.isGoogle ? 'حساب جوجل' : 'زائر', style: const TextStyle(color: C.textDim, fontSize: 12)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Text('المستوى ${li.level}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Expanded(child: ProgressBar(value: li.progress, height: 8)),
                  const SizedBox(width: 8),
                  Text('${li.xpInLevel}/${li.xpForNext}', textDirection: TextDirection.ltr, style: const TextStyle(color: C.textDim, fontSize: 11)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(tier.icon, color: tier.color, size: 18),
                  const SizedBox(width: 4),
                  Text(tier.label, style: TextStyle(color: tier.color, fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(child: ProgressBar(value: Ranks.progress(db, p.rankPoints), color: tier.color, height: 8)),
                  const SizedBox(width: 8),
                  Text(next == null ? '${p.rankPoints} RP' : '${p.rankPoints}/$next', textDirection: TextDirection.ltr, style: const TextStyle(color: C.textDim, fontSize: 11)),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            NeonButton(label: 'شارك بطاقة اللاعب', icon: Icons.ios_share_rounded, color: C.magenta, busy: busy, onPressed: _shareCard),
            const SizedBox(height: 10),
            StatsBody(profile: p),
            const SizedBox(height: 10),
            Panel(
              onTap: () => _nav(const CertificatesScreen()),
              child: Row(children: [const Icon(Icons.verified, size: 26, color: C.gold), const SizedBox(width: 10), Expanded(child: Text(certs == 0 ? 'شهادات السرعة (WPM)' : 'شهاداتي ($certs)', style: const TextStyle(fontWeight: FontWeight.w800))), const Icon(Icons.chevron_left)]),
            ),
            const SizedBox(height: 10),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ادعُ أصدقاءك', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text('عندما يصل صديقك للمستوى $minLevel تربحان معاً: أنت ${(db.economy['referral'] as Map?)?['inviterReward']?['coins'] ?? 3000} عملة وهو ${(db.economy['referral'] as Map?)?['inviteeReward']?['coins'] ?? 2000} عملة، إضافة إلى الجواهر.', style: const TextStyle(color: C.textDim, fontSize: 12)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12), alignment: Alignment.center, decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)), child: SelectableText(p.refCode, textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'FiraMono', fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.w900, color: C.cyan)))),
                  IconButton(icon: const Icon(Icons.copy_rounded), onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.refCode));
                    if (mounted) toast(context, 'تم نسخ الرمز');
                  }),
                  IconButton(
                    icon: const Icon(Icons.share_rounded, color: C.magenta),
                    onPressed: () => SharePlus.instance.share(ShareParams(text: 'جرّب ${AppConfig.appName} — سباقات كتابة ضد الذكاء الاصطناعي\nاستخدم رمز الدعوة: ${p.refCode}\nhttps://f0uri.github.io/type-racer-legends/')),
                  ),
                ]),
                if (!auth.isGoogle) const Padding(padding: EdgeInsets.only(top: 8), child: Text('اربط حساب جوجل (من الإعدادات) لتفعيل مكافآت الدعوة.', style: TextStyle(color: C.gold, fontSize: 12))),
                if (auth.isGoogle) ...[
                  const Divider(height: 24),
                  if (!redeemed)
                    Row(children: [
                      Expanded(child: TextField(controller: codeCtl, textCapitalization: TextCapitalization.characters, textDirection: TextDirection.ltr, maxLength: 10, decoration: const InputDecoration(hintText: 'عندك رمز من صديق؟', counterText: ''))),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: busy ? null : _redeem, child: const Text('تفعيل')),
                    ])
                  else
                    const Text('فعّلت رمز دعوة سابقاً', style: TextStyle(color: C.green)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: busy ? null : _claim, icon: const Icon(Icons.card_giftcard_rounded), label: const Text('استلام مكافآت الدعوات')),
                  if (p.counter('ref_invites') > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('أصدقاء دعوتهم: ${p.counter('ref_invites')}', style: const TextStyle(color: C.textDim, fontSize: 12))),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            Panel(
              onTap: () => _nav(const StatsScreen()),
              child: const Row(children: [Icon(Icons.bar_chart, size: 26, color: C.cyan), SizedBox(width: 10), Expanded(child: Text('صفحة الإحصائيات الكاملة', style: TextStyle(fontWeight: FontWeight.w800))), Icon(Icons.chevron_left)]),
            ),
          ]),
        ),
      ),
    );
  }
}
