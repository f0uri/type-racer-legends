import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/misc.dart';
import '../../../core/widgets/common.dart';
import '../../ads/ads_service.dart';
import '../../ads/ads_ui.dart';
import '../../career/rank.dart';
import '../../career/challenge_link.dart';
import '../../profile/card_builder.dart';
import '../../profile/share_card.dart';
import '../engine/race_models.dart';
import '../race_outcome.dart';
import 'race_screen.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.result, required this.outcome, this.rebuild, this.extra, this.primaryLabel, this.onPrimary});
  final RaceResult result;
  final RaceOutcome outcome;
  final RaceConfig Function()? rebuild;

  /// Extra widgets shown under the stats (e.g. campaign stars, tournament bracket).
  final List<Widget>? extra;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.outcome.breakDue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('وقت الاستراحة'),
            content: const Text('تلعب منذ وقت طويل. خذ استراحة قصيرة: مدّ يديك، انظر بعيداً عن الشاشة واشرب الماء. تقدّمك محفوظ.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result, o = widget.outcome;
    final db = ref.watch(contentProvider);
    final hasOpp = r.opponents > 0;
    final title = r.timeUp ? 'انتهى الوقت' : (hasOpp ? (r.won ? 'فوز!' : 'المركز ${r.playerRank} من ${r.standings.length}') : 'اكتمل السباق');
    final color = r.won && hasOpp ? C.gold : (r.playerRank <= 3 && hasOpp ? C.cyan : Colors.white);
    final avg = ref.read(profileProvider).avgWpm;
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Center(child: Text(title, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: color))),
            if (r.photoFinish) const Center(child: Padding(padding: EdgeInsets.only(top: 4), child: Text('Photo Finish!', style: TextStyle(color: C.gold, fontWeight: FontWeight.w800)))),
            if (r.suspicious)
              const Padding(padding: EdgeInsets.only(top: 8), child: Panel(border: C.red, child: Text('تم اكتشاف إدخال غير طبيعي (لصق أو كتابة آلية). لا تُحتسب هذه النتيجة في المكافآت أو اللوحات.', style: TextStyle(color: C.red)))),
            const SizedBox(height: 14),
            Row(children: [
              _big('WPM', r.wpm.toStringAsFixed(0), C.cyan, sub: avg > 0 ? '${r.wpm >= avg ? '▲' : '▼'} معدلك ${avg.toStringAsFixed(0)}' : null),
              const SizedBox(width: 10),
              _big('الدقة', '${r.accuracy.toStringAsFixed(1)}%', r.accuracy >= 95 ? C.green : C.gold),
            ]),
            const SizedBox(height: 10),
            Panel(
              child: Wrap(alignment: WrapAlignment.spaceAround, runSpacing: 10, spacing: 14, children: [
                _mini('الزمن', '${r.time.toStringAsFixed(1)}s'),
                _mini('أعلى كومبو', '${r.maxCombo}'),
                _mini('الأخطاء', '${r.errors}'),
                _mini('الأحرف', '${r.chars}'),
                if (r.nitroUses > 0) _mini('نيترو', '${r.nitroUses}'),
                if (r.perfectWords > 0) _mini('كلمات مثالية', '${r.perfectWords}'),
              ]),
            ),
            if (o.records.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final rec in o.records)
                  Chip(
                    backgroundColor: C.gold.withValues(alpha: 0.2),
                    side: const BorderSide(color: C.gold),
                    label: Text(const {'best_wpm': 'رقم قياسي في السرعة', 'best_acc': 'رقم قياسي في الدقة', 'combo_max': 'أعلى كومبو'}[rec] ?? rec, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            if (o.rewarded)
              Panel(
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _reward(Icons.monetization_on, C.gold, o.coins, 'عملات'),
                    _reward(Icons.bolt_rounded, C.cyan, o.xp, 'خبرة'),
                    if (o.gems > 0) _reward(Icons.diamond, C.magenta, o.gems, 'جواهر'),
                    if (r.config.ranked && hasOpp) _reward(Icons.emoji_events_rounded, o.rpDelta >= 0 ? C.green : C.red, o.rpDelta, 'نقاط تصنيف', signed: true),
                  ]),
                  if (o.capped) const Padding(padding: EdgeInsets.only(top: 8), child: Text('بلغت الحد اليومي للعملات — تحصل على المكافأة الدنيا المضمونة.', style: TextStyle(color: C.textDim, fontSize: 12))),
                  if (o.levelUp) Padding(padding: const EdgeInsets.only(top: 10), child: Text('ارتقيت إلى المستوى ${o.newLevel}!', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w900, fontSize: 16))),
                  if (o.tierUp) Padding(padding: const EdgeInsets.only(top: 6), child: Text('ترقية التصنيف: ${Ranks.tierOf(db, o.rpAfter).icon} ${Ranks.tierOf(db, o.rpAfter).label}', style: const TextStyle(color: C.green, fontWeight: FontWeight.w900))),
                  if (o.tierDown) Padding(padding: const EdgeInsets.only(top: 6), child: Text('انخفض تصنيفك إلى ${Ranks.tierOf(db, o.rpAfter).label}', style: const TextStyle(color: C.red, fontWeight: FontWeight.w800))),
                ]),
              ),
            if (o.rewarded && o.coins > 0 && !r.suspicious) ...[const SizedBox(height: 12), RewardedAdCard(doubleCoins: o.coins)],
            if (widget.extra != null) ...[const SizedBox(height: 12), ...widget.extra!],
            if (r.standings.length > 1) ...[
              const SizedBox(height: 12),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('الترتيب', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  for (final s in r.standings)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(color: s.isPlayer ? C.cyan.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        SizedBox(width: 26, child: Text('${s.rank}', style: TextStyle(fontWeight: FontWeight.w900, color: s.rank == 1 ? C.gold : Colors.white70))),
                        if (!s.isGhost && s.cc.isNotEmpty) Text('${flagEmoji(s.cc)} ') else if (s.isGhost) const Icon(Icons.visibility, size: 16, color: C.textDim),
                        Expanded(child: Text(s.isPlayer ? '${s.name} (أنت)' : s.name, style: TextStyle(fontWeight: s.isPlayer ? FontWeight.w900 : FontWeight.w600), overflow: TextOverflow.ellipsis)),
                        if (s.isAi) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(border: Border.all(color: C.cyan.withValues(alpha: .6)), borderRadius: BorderRadius.circular(6)), child: const Text('AI', style: TextStyle(fontSize: 9, color: C.cyan, fontWeight: FontWeight.w900))),
                        const SizedBox(width: 8),
                        SizedBox(width: 70, child: Text('${s.wpm.round()} WPM', textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: const TextStyle(fontFamily: 'FiraMono', fontSize: 12))),
                      ]),
                    ),
                  const SizedBox(height: 6),
                  const Text('المنافسون ذكاء اصطناعي. أرقامهم محاكاة وليست للاعبين حقيقيين.', style: TextStyle(color: C.textDim, fontSize: 11)),
                ]),
              ),
            ],
            if (_weakKeys(r).isNotEmpty) ...[
              const SizedBox(height: 12),
              Panel(child: Row(children: [const Icon(Icons.track_changes, size: 18, color: C.gold), const SizedBox(width: 6), Expanded(child: Text('أكثر الحروف أخطاءً: ${_weakKeys(r).join('  ')}', style: const TextStyle(fontWeight: FontWeight.w700)))])),
            ],
            const SizedBox(height: 18),
            if (widget.onPrimary != null) NeonButton(label: widget.primaryLabel ?? 'متابعة', icon: Icons.arrow_forward_rounded, onPressed: widget.onPrimary),
            if (widget.rebuild != null) ...[
              const SizedBox(height: 10),
              NeonButton(
                label: 'سباق جديد',
                icon: Icons.replay_rounded,
                filled: widget.onPrimary == null,
                color: widget.onPrimary == null ? C.cyan : C.magenta,
                onPressed: () async {
                  // the only place an interstitial can appear: between two races, at the player's own request
                  await ref.read(adsProvider).betweenRaces(tutorialOrLesson: r.config.modeId == 'lesson');
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => RaceScreen(config: widget.rebuild!(), rebuild: widget.rebuild)));
                },
              ),
            ],
            if (!r.suspicious && r.chars >= RaceRewards.minCharsForStats && db.textById(r.config.text.id) != null && db.featureOn('link_challenge')) ...[
              const SizedBox(height: 10),
              NeonButton(
                label: 'تحدَّ صديقاً بهذه النتيجة',
                icon: Icons.share_rounded,
                filled: false,
                color: C.magenta,
                onPressed: () => ChallengeLink.share(context, r, ref.read(profileProvider).name, ref.read(profileProvider).country),
              ),
            ],
            if (!r.suspicious && r.chars >= RaceRewards.minCharsForStats) ...[
              const SizedBox(height: 10),
              NeonButton(
                label: r.won && hasOpp ? 'شارك صورة الفوز' : 'شارك صورة النتيجة',
                icon: Icons.photo_camera_rounded,
                filled: false,
                color: C.gold,
                onPressed: () async {
                  try {
                    await ShareCardRenderer.share(CardBuilder.race(db, ref.read(profileProvider), r), text: '${r.wpm.round()} WPM بدقة ${r.accuracy.round()}% في Type Racer Legends');
                  } catch (_) {
                    if (context.mounted) toast(context, 'تعذّرت المشاركة');
                  }
                },
              ),
            ],
            const SizedBox(height: 10),
            NeonButton(label: 'الرئيسية', icon: Icons.home_rounded, filled: false, color: C.textDim, onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
          ]),
        ),
      ),
    );
  }

  List<String> _weakKeys(RaceResult r) {
    final list = r.charStats.entries.where((e) => e.value[1] > 0 && e.key.trim().isNotEmpty).toList()..sort((a, b) => b.value[1].compareTo(a.value[1]));
    return list.take(4).map((e) => e.key.toUpperCase()).toList();
  }

  Widget _big(String label, String value, Color c, {String? sub}) => Expanded(
        child: Panel(
          child: Column(children: [
            Text(label, style: const TextStyle(color: C.textDim)),
            Text(value, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: c, fontFamily: 'FiraMono')),
            if (sub != null) Text(sub, style: const TextStyle(color: C.textDim, fontSize: 11)),
          ]),
        ),
      );

  Widget _mini(String l, String v) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(v, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        Text(l, style: const TextStyle(color: C.textDim, fontSize: 11)),
      ]);

  Widget _reward(IconData i, Color c, int v, String label, {bool signed = false}) => Column(children: [
        Icon(i, color: c),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v.toDouble()),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOut,
          builder: (_, val, _) => Text('${signed && v > 0 ? '+' : ''}${val.round()}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: c)),
        ),
        Text(label, style: const TextStyle(color: C.textDim, fontSize: 11)),
      ]);
}
