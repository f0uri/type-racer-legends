import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/services/audio_service.dart';
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
import '../game/particles.dart';
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
  /// Where the coin burst starts (measured from the real reward row) and where it lands.
  final GlobalKey _coinKey = GlobalKey();
  Offset? _coinsFrom;
  Offset _coinsTo = Offset.zero;
  bool _burst = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(raceChainProvider.notifier).bump();
      _startCoinBurst();
      // A win opens with its own sound and thump. Waiting for the hit-test of a button would be a
      // silent, motionless first beat on the one screen that is supposed to feel earned.
      final r = widget.result;
      if (r.won && !r.suspicious && r.opponents > 0) {
        ref.read(audioProvider).play(Sfx.fanfare);
        ref.read(hapticsProvider).finish();
      }
    });
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

  /// The reward ceremony: the coins that were just earned fly out of the reward row towards
  /// the wallet corner, where the total pops. Nothing moves the numbers by itself — the player
  /// watches their own reward travel, which is the whole point of a result screen.
  void _startCoinBurst() {
    final o = widget.outcome;
    if (!o.rewarded || o.coins <= 0 || widget.result.suspicious) return;
    final box = _coinKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    setState(() {
      _coinsFrom = center;
      _coinsTo = const Offset(46, 34);
      _burst = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result, o = widget.outcome;
    final chain = ref.watch(raceChainProvider);
    final db = ref.watch(contentProvider);
    final hasOpp = r.opponents > 0;
    final title = r.timeUp ? 'انتهى الوقت' : (hasOpp ? (r.won ? 'فوز!' : 'المركز ${r.playerRank} من ${r.standings.length}') : 'اكتمل السباق');
    final color = r.won && hasOpp ? C.gold : (r.playerRank <= 3 && hasOpp ? C.cyan : Colors.white);
    final avg = ref.read(profileProvider).avgWpm;
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Stack(children: [
            ListView(padding: const EdgeInsets.all(16), children: [
            ResultBanner(title: title, color: color, chain: chain, photoFinish: r.photoFinish, celebrate: r.won && hasOpp),
            if (r.suspicious)
              const Padding(padding: EdgeInsets.only(top: 8), child: Panel(border: C.red, child: Text('تم اكتشاف إدخال غير طبيعي (لصق أو كتابة آلية). لا تُحتسب هذه النتيجة في المكافآت أو اللوحات.', style: TextStyle(color: C.red)))),
            const SizedBox(height: 14),
            _RiseIn(delay: 0.10, child: Row(children: [
              _big('WPM', r.wpm, C.cyan, sub: avg > 0 ? '${r.wpm >= avg ? '▲' : '▼'} معدلك ${avg.toStringAsFixed(0)}' : null),
              const SizedBox(width: 10),
              _big('الدقة', r.accuracy, r.accuracy >= 95 ? C.green : C.gold, suffix: '%', decimals: 1),
            ])),
            const SizedBox(height: 10),
            _RiseIn(
              delay: 0.18,
              child: Panel(
                child: Wrap(alignment: WrapAlignment.spaceAround, runSpacing: 10, spacing: 14, children: [
                  _mini('الزمن', '${r.time.toStringAsFixed(1)}s'),
                  _mini('أعلى كومبو', '${r.maxCombo}'),
                  _mini('الأخطاء', '${r.errors}'),
                  _mini('الأحرف', '${r.chars}'),
                  if (r.nitroUses > 0) _mini('نيترو', '${r.nitroUses}'),
                  if (r.perfectWords > 0) _mini('كلمات مثالية', '${r.perfectWords}'),
                ]),
              ),
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
                    KeyedSubtree(key: _coinKey, child: _reward(Icons.monetization_on, C.gold, o.coins, 'عملات')),
                    _reward(Icons.bolt_rounded, C.cyan, o.xp, 'خبرة'),
                    if (o.gems > 0) _reward(Icons.diamond, C.magenta, o.gems, 'جواهر'),
                    if (r.config.ranked && hasOpp) _reward(Icons.emoji_events_rounded, o.rpDelta >= 0 ? C.green : C.red, o.rpDelta, 'نقاط تصنيف', signed: true),
                  ]),
                  if (o.capped) const Padding(padding: EdgeInsets.only(top: 8), child: Text('بلغت الحد اليومي للعملات — تحصل على المكافأة الدنيا المضمونة.', style: TextStyle(color: C.textDim, fontSize: 12))),
                  if (o.levelUp)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star, size: 18, color: C.gold),
                        const SizedBox(width: 6),
                        Text('ارتقيت إلى المستوى ${o.newLevel}!', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w900, fontSize: 16)),
                      ]),
                    ),
                  if (o.tierUp)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Ranks.tierOf(db, o.rpAfter).icon, size: 16, color: C.green),
                        const SizedBox(width: 5),
                        Text('ترقية التصنيف: ${Ranks.tierOf(db, o.rpAfter).label}', style: const TextStyle(color: C.green, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                  if (o.tierDown) Padding(padding: const EdgeInsets.only(top: 6), child: Text('انخفض تصنيفك إلى ${Ranks.tierOf(db, o.rpAfter).label}', style: const TextStyle(color: C.red, fontWeight: FontWeight.w800))),
                ]),
              ),
            if (o.rewarded) ...[const SizedBox(height: 10), _xpBar(o)],
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
                  // The next race answers the press immediately: a whoosh and a thump before the
                  // ad/navigation gap, so the button never feels like it dropped the request.
                  ref.read(audioProvider).play(Sfx.whoosh, vol: 0.7);
                  ref.read(hapticsProvider).light();
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
            NeonButton(
              label: 'الرئيسية',
              icon: Icons.home_rounded,
              filled: false,
              color: C.textDim,
              onPressed: () {
                // leaving to the lobby ends the round chain: it counts races in a row, not total races
                ref.read(raceChainProvider.notifier).reset();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
            ]),
            if (_burst && _coinsFrom != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: _CoinBurst(from: _coinsFrom!, to: _coinsTo, coins: o.coins),
                ),
              ),
            // A win gets rain: the one moment the player earned a real celebration — unless the
            // OS asks for reduced motion, in which case the ceremony stays and the rain does not.
            if (r.won && hasOpp && !r.suspicious && !reduceMotion(context))
              const Positioned.fill(child: IgnorePointer(child: _WinConfetti())),
          ]),
        ),
      ),
    );
  }

  List<String> _weakKeys(RaceResult r) {
    final list = r.charStats.entries.where((e) => e.value[1] > 0 && e.key.trim().isNotEmpty).toList()..sort((a, b) => b.value[1].compareTo(a.value[1]));
    return list.take(4).map((e) => e.key.toUpperCase()).toList();
  }

  /// Big stat that counts itself up on entry: numbers that simply appear feel like a web report.
  Widget _big(String label, double value, Color c, {String? sub, String suffix = '', int decimals = 0}) => Expanded(
        child: Panel(
          child: Column(children: [
            Text(label, style: const TextStyle(color: C.textDim)),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 850),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text('${v.toStringAsFixed(decimals)}$suffix', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: c, fontFamily: 'FiraMono')),
            ),
            if (sub != null) Text(sub, style: const TextStyle(color: C.textDim, fontSize: 11)),
          ]),
        ),
      );

  /// XP bar that fills from where the player was before this race to where they are now.
  Widget _xpBar(RaceOutcome o) {
    final li = ref.watch(levelInfoProvider);
    final per = li.xpForNext <= 0 ? 1 : li.xpForNext;
    final after = li.progress.clamp(0.0, 1.0).toDouble();
    // a level-up refills the bar from empty, otherwise it grows by the XP just earned
    final before = o.levelUp ? 0.0 : ((li.xpInLevel - o.xp) / per).clamp(0.0, after).toDouble();
    return Panel(
      child: Column(children: [
        Row(children: [
          const Icon(Icons.bolt_rounded, size: 20, color: C.cyan),
          const SizedBox(width: 6),
          Text('المستوى ${li.level}', style: const TextStyle(fontWeight: FontWeight.w900)),
          const Spacer(),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: o.xp.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (_, v, _) => Text('+${v.round()} خبرة', style: const TextStyle(color: C.cyan, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: before, end: after),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => ProgressBar(value: v, height: 10),
        ),
      ]),
    );
  }

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

/// Coins flying from the reward row to the wallet corner, then a total badge that pops.
/// Confetti rain for a win, built on the race's own particle pool: no new drawing code, one
/// CustomPaint, and the ticker stops by itself once the last piece has fallen so the result
/// screen goes back to costing nothing.
/// The headline of a result: it drops in from above with a small overshoot, the way a mobile game
/// announces a win, and it carries a glow when the player actually won one. Reduced motion turns
/// the entrance into a single frame rather than a movement.
@visibleForTesting
class ResultBanner extends StatelessWidget {
  const ResultBanner({super.key, required this.title, required this.color, this.chain = 0, this.photoFinish = false, this.celebrate = false});
  final String title;
  final Color color;
  final int chain;
  final bool photoFinish;
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 480),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(offset: Offset(0, (1 - t) * -44), child: Transform.scale(scale: 0.94 + 0.06 * t, child: child)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: displayStyle(size: 30, color: color).copyWith(shadows: celebrate ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 24)] : null),
        ),
        if (chain >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.local_fire_department, size: 18, color: C.gold),
              const SizedBox(width: 5),
              Text('سلسلة الجولات: $chain', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w900)),
            ]),
          ),
        if (photoFinish) const Padding(padding: EdgeInsets.only(top: 4), child: Text('Photo Finish!', style: TextStyle(color: C.gold, fontWeight: FontWeight.w800))),
      ]),
    );
  }
}

/// Everything under the headline arrives in order instead of all at once: a result screen that
/// appears fully formed reads like a web page, one that assembles reads like a game.
class _RiseIn extends StatelessWidget {
  const _RiseIn({required this.child, this.delay = 0});
  final Widget child;

  /// Share of the total entrance to wait through, 0..0.6.
  final double delay;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 560),
      curve: Interval(delay.clamp(0.0, 0.6).toDouble(), 1, curve: Curves.easeOutCubic),
      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 24), child: child)),
      child: child,
    );
  }
}

class _WinConfetti extends StatefulWidget {
  const _WinConfetti();
  @override
  State<_WinConfetti> createState() => _WinConfettiState();
}

class _WinConfettiState extends State<_WinConfetti> with SingleTickerProviderStateMixin {
  static const _rainSeconds = 2.4;
  static const _hardStop = 8.0; // belt and braces: the ticker can never run forever
  static const _colors = [C.gold, Colors.white, C.cyan, C.magenta];

  final ParticleSystem _ps = ParticleSystem(220);
  late final Ticker _tk = createTicker(_tick)..start();
  Duration _last = Duration.zero;
  double _t = 0, _nextEmit = 0;

  @override
  void dispose() {
    _tk.dispose();
    super.dispose();
  }

  void _tick(Duration d) {
    final dt = min(0.05, _last == Duration.zero ? 0.016 : (d - _last).inMicroseconds / 1e6);
    _last = d;
    _t += dt;
    if (_t < _rainSeconds && _t >= _nextEmit) {
      // a new handful every 80ms, swinging across the width so it reads as rain, not a fountain
      _nextEmit = _t + 0.08;
      final w = context.size?.width ?? 360;
      _ps.burst(
        PKind.confetti,
        w * (0.1 + 0.8 * (0.5 + 0.5 * sin(_t * 4.7))),
        -12,
        3,
        speed: 80,
        life: 2.6,
        size: 5,
        g: 300,
        spread: 1.1,
        angle: 1.4,
        colors: _colors,
      );
    }
    _ps.update(dt);
    if (!mounted) return;
    if ((_t > _rainSeconds && _ps.alive == 0) || _t > _hardStop) {
      _tk.stop();
      return;
    }
    setState(() {}); // only this subtree repaints; the result list is untouched
  }

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_ps));
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.ps);
  final ParticleSystem ps;
  @override
  void paint(Canvas canvas, Size size) => ps.render(canvas);
  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => true;
}

class _CoinBurst extends StatefulWidget {
  const _CoinBurst({required this.from, required this.to, required this.coins});
  final Offset from, to;
  final int coins;

  @override
  State<_CoinBurst> createState() => _CoinBurstState();
}

class _CoinBurstState extends State<_CoinBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1050))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 4..8 coins: more than that is visual noise on a phone screen
    final n = (3 + widget.coins ~/ 60).clamp(4, 8);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final kids = <Widget>[];
        for (var i = 0; i < n; i++) {
          // each coin leaves a little after the previous one: a stream, not a single object
          final t = ((_c.value - i * 0.07) / 0.58).clamp(0.0, 1.0);
          if (t <= 0) continue;
          final e = Curves.easeOutCubic.transform(t);
          final bow = sin(t * pi) * (20 + 9 * (i % 3));
          final x = widget.from.dx + (widget.to.dx - widget.from.dx) * e + (i.isEven ? 1 : -1) * bow * 0.5;
          final y = widget.from.dy + (widget.to.dy - widget.from.dy) * e - bow;
          final fade = 1 - (((t - 0.62) / 0.38).clamp(0.0, 1.0));
          kids.add(Positioned(
            left: x - 11,
            top: y - 11,
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.scale(scale: 1 - 0.45 * e, child: const Icon(Icons.monetization_on, size: 22, color: C.gold)),
            ),
          ));
        }
        // the wallet badge pops once the first coins land
        final pop = ((_c.value - 0.55) / 0.25).clamp(0.0, 1.0);
        if (pop > 0) {
          kids.add(Positioned(
            left: widget.to.dx - 30,
            top: widget.to.dy - 15,
            child: Opacity(
              opacity: pop,
              child: Transform.scale(
                scale: 0.7 + 0.3 * pop,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: C.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.gold),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.monetization_on, size: 14, color: C.gold),
                    const SizedBox(width: 4),
                    Text('+${fmtInt(widget.coins)}', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w900, fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ));
        }
        return Stack(children: kids);
      },
    );
  }
}
