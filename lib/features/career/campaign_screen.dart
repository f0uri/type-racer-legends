import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/models/content_models.dart';
import '../race/engine/race_models.dart';
import '../race/game/env_painter.dart';
import '../race/race_outcome.dart';
import '../race/ui/result_screen.dart';
import 'campaign_logic.dart';
import 'mode_flow.dart';

class CampaignScreen extends ConsumerStatefulWidget {
  const CampaignScreen({super.key});
  @override
  ConsumerState<CampaignScreen> createState() => _CampaignScreenState();
}

class _CampaignScreenState extends ConsumerState<CampaignScreen> {
  late final PageController _pc;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    final db = ref.read(contentProvider);
    final p = ref.read(profileProvider);
    // open on the biome of the first stage that is not cleared yet
    var page = 0;
    for (final s in db.stages) {
      if (p.campaignStars(s.n) == 0) {
        page = max(0, db.biomes.indexWhere((b) => b.id == s.biome));
        break;
      }
      page = max(0, db.biomes.indexWhere((b) => b.id == s.biome));
    }
    _page = page;
    _pc = PageController(initialPage: page);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الحملة'), actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star, size: 16, color: C.gold),
              const SizedBox(width: 4),
              Text('${p.totalStars}/${db.stages.length * 3}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ]),
      body: GradientBg(
        child: Column(children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: db.biomes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final b = db.biomes[i];
                final sel = i == _page;
                final done = db.stages.where((s) => s.biome == b.id && p.campaignStars(s.n) > 0).length;
                return ChoiceChip(
                  selected: sel,
                  label: Text('${loc(b.name)}  $done/${db.stages.where((s) => s.biome == b.id).length}'),
                  onSelected: (_) => _pc.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                );
              },
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: db.biomes.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _BiomePage(biome: db.biomes[i]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BiomePage extends ConsumerWidget {
  const _BiomePage({required this.biome});
  final Biome biome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final stages = db.stages.where((s) => s.biome == biome.id).toList();
    const step = 104.0;
    final h = stages.length * step + 80;
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final pts = <Offset>[for (var i = 0; i < stages.length; i++) Offset(w / 2 + sin(i * 1.15) * w * 0.26, 60 + (stages.length - 1 - i) * step)];
      return SingleChildScrollView(
        reverse: true,
        child: SizedBox(
          height: max(h, cons.maxHeight),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _MapPainter(EnvPainter(EnvSpec.fromBiome(biome)), pts, stages.map((s) => p.campaignStars(s.n) > 0).toList()))),
            for (var i = 0; i < stages.length; i++)
              Positioned(
                left: pts[i].dx - 44,
                top: pts[i].dy - 34 + (max(h, cons.maxHeight) - h),
                width: 88,
                child: _Node(stage: stages[i], index: i, onTap: () => _open(context, ref, stages[i])),
              ),
          ]),
        ),
      );
    });
  }

  void _open(BuildContext context, WidgetRef ref, Stage s) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => StageSheet(stage: s));
  }
}

class _Node extends ConsumerWidget {
  const _Node({required this.stage, required this.index, required this.onTap});
  final Stage stage;
  final int index;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final stars = p.campaignStars(stage.n);
    final open = CampaignLogic.unlocked(p, stage.n);
    final boss = stage.isBoss;
    final color = !open ? Colors.white24 : (stars > 0 ? C.green : C.cyan);
    final size = boss ? 66.0 : 54.0;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: C.surface,
            border: Border.all(color: boss ? C.gold : color, width: boss ? 3.5 : 2.5),
            boxShadow: open ? [BoxShadow(color: (boss ? C.gold : color).withValues(alpha: 0.5), blurRadius: 12)] : null,
          ),
          alignment: Alignment.center,
          child: !open ? const Icon(Icons.lock_rounded, color: Colors.white38) : (boss ? const Icon(Icons.workspace_premium, size: 28, color: C.gold) : Text('${stage.n}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20))),
        ),
        const SizedBox(height: 4),
        starRow(stars, size: 15),
      ]),
    );
  }
}

class _MapPainter extends CustomPainter {
  final EnvPainter env;
  final List<Offset> pts;
  final List<bool> done;
  _MapPainter(this.env, this.pts, this.done);
  @override
  void paint(Canvas canvas, Size size) {
    // themed backdrop: sky, skyline and road of the biome (static)
    canvas.save();
    final sceneH = min(size.height, 420.0);
    env.paint(canvas, Size(size.width, sceneH), 300, 0);
    canvas.restore();
    canvas.drawRect(Rect.fromLTWH(0, sceneH, size.width, size.height - sceneH), Paint()..color = env.spec.ground);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0x99000000));
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      path.cubicTo(a.dx, (a.dy + b.dy) / 2, b.dx, (a.dy + b.dy) / 2, b.dx, b.dy);
    }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 12..strokeCap = StrokeCap.round..color = const Color(0x33FFFFFF));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = env.spec.accent.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.done != done;
}

class StageSheet extends ConsumerWidget {
  const StageSheet({super.key, required this.stage});
  final Stage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final open = CampaignLogic.unlocked(p, stage.n);
    final stars = p.campaignStars(stage.n);
    final boss = stage.boss == null ? null : db.boss(stage.boss!);
    final biome = db.biomeOf(stage.biome);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(loc(stage.title), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            starRow(stars, size: 22),
          ]),
          Text('${loc(biome.name)}  •  المرحلة ${stage.n} من ${db.stages.length}', style: const TextStyle(color: C.textDim)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _chip('${stage.oppCount} منافسين (AI)'),
            _chip('~${stage.oppWpm.round()} WPM'),
            _chip('${stage.lenMin}–${stage.lenMax} حرف'),
            if (stage.mod != 'none') _chip(const {'fog': 'ضباب', 'ice': 'جليد', 'blackout': 'ظلام', 'storm': 'عاصفة'}[stage.mod] ?? stage.mod, color: C.magenta),
          ]),
          if (boss != null) ...[
            const SizedBox(height: 12),
            Panel(
              border: C.gold,
              child: Row(children: [
                const Icon(Icons.workspace_premium, size: 30, color: C.gold),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('الزعيم: ${loc(boss.name)}  ${flagEmoji(boss.cc)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text('"${(boss.taunts['ar'] as List?)?.first ?? ''}"', style: const TextStyle(color: C.textDim, fontSize: 12)),
                  const Text('منافس ذكاء اصطناعي', style: TextStyle(color: C.cyan, fontSize: 11)),
                ])),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('النجوم', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              _goal(1, 'أنهِ السباق في المركز الأول أو الثاني', stars),
              _goal(2, 'فُز بالمركز الأول', stars),
              _goal(3, 'فُز بدقة ${stage.accStar}% أو أكثر', stars),
            ]),
          ),
          const SizedBox(height: 10),
          Text('مكافأة أول إنجاز: ${stage.reward['coins'] ?? 0} عملة + ${stage.reward['xp'] ?? 0} خبرة${((stage.reward['gems'] as num?) ?? 0) > 0 ? ' + ${stage.reward['gems']} جوهرة' : ''}', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          NeonButton(
            label: open ? 'ابدأ المرحلة' : 'أكمل المرحلة السابقة أولاً',
            icon: open ? Icons.flag_rounded : Icons.lock_rounded,
            onPressed: open
                ? () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    CampaignFlow.play(nav.context, stage.n);
                  }
                : null,
          ),
        ]),
      ),
    );
  }

  Widget _chip(String t, {Color color = C.cyan}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.6))),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _goal(int n, String t, int stars) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(n <= stars ? Icons.star_rounded : Icons.star_border_rounded, color: n <= stars ? C.gold : Colors.white38, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(t, style: TextStyle(fontSize: 13, color: n <= stars ? Colors.white : C.textDim))),
        ]),
      );
}

class CampaignFlow {
  static void play(BuildContext context, int stageNo) {
    final c = ModeFlow.container(context);
    final db = c.read(contentProvider);
    final stage = db.stage(stageNo);
    if (stage == null) return;
    ModeFlow.race(
      context,
      config: () => CampaignLogic.buildConfig(db, c.read(profileProvider), c.read(settingsProvider), stage),
      finish: (ctx, result, outcome, rebuild) {
        late StageOutcome so;
        c.read(profileProvider.notifier).update((p) => so = CampaignLogic.apply(p, stage, result, db));
        return _CampaignResult(result: result, outcome: outcome, stage: stage, so: so, rebuild: rebuild);
      },
    );
  }
}

class _CampaignResult extends ConsumerWidget {
  const _CampaignResult({required this.result, required this.outcome, required this.stage, required this.so, this.rebuild});
  final RaceResult result;
  final RaceOutcome outcome;
  final Stage stage;
  final StageOutcome so;
  final RaceConfig Function()? rebuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final boss = stage.boss == null ? null : db.boss(stage.boss!);
    final cleared = so.stars > 0;
    final hasNext = cleared && stage.n < db.stages.length;
    return ResultScreen(
      result: result,
      outcome: outcome,
      rebuild: rebuild,
      primaryLabel: hasNext ? 'المرحلة التالية' : null,
      onPrimary: hasNext
          ? () {
              final nav = Navigator.of(context);
              nav.pop();
              CampaignFlow.play(nav.context, stage.n + 1);
            }
          : null,
      extra: [
        Panel(
          border: cleared ? C.gold : C.red,
          child: Column(children: [
            Text(cleared ? 'تم اجتياز المرحلة ${stage.n}' : 'لم تُجتز المرحلة — حاول مجدداً', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cleared ? C.gold : C.red)),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: so.stars.toDouble()),
              duration: const Duration(milliseconds: 900),
              builder: (_, v, _) => starRow(v.ceil().clamp(0, 3), size: 34),
            ),
            if (boss != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${loc(boss.name)}: "${loc(result.won ? boss.win : boss.lose)}"', textAlign: TextAlign.center, style: const TextStyle(color: C.textDim))),
            if (so.bossBeaten) const Padding(padding: EdgeInsets.only(top: 6), child: Text('هزمت الزعيم لأول مرة!', style: TextStyle(color: C.gold, fontWeight: FontWeight.w900))),
          ]),
        ),
        if (so.coins + so.xp + so.gems > 0) ...[
          const SizedBox(height: 10),
          ModeFlow.rewardPanel(so.firstClear ? 'مكافأة أول إنجاز' : 'مكافأة تحسين النجوم', coins: so.coins, xp: so.xp, gems: so.gems),
        ],
      ],
    );
  }
}
