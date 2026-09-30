import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/profile.dart';
import '../learn/keyboard_guide.dart';
import '../learn/learn_logic.dart';
import 'stats_logic.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  static String fmtDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}س ${d.inMinutes % 60}د';
    if (d.inMinutes >= 1) return '${d.inMinutes}د';
    return '${d.inSeconds}ث';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('إحصائياتي')),
      body: GradientBg(child: ListView(padding: const EdgeInsets.all(16), children: [StatsBody(profile: p)])),
    );
  }
}

/// The statistics content (also embedded in the profile screen).
class StatsBody extends ConsumerWidget {
  const StatsBody({super.key, required this.profile});
  final PlayerProfile profile;

  Widget _tile(String label, String value, Color c, {String? sub}) => Expanded(
        child: Panel(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(children: [
            FittedBox(child: Text(value, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c, fontFamily: 'FiraMono'))),
            Text(label, style: const TextStyle(color: C.textDim, fontSize: 11)),
            if (sub != null) Text(sub, style: const TextStyle(fontSize: 10, color: C.textDim)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final hist = p.history;
    final trend = StatsLogic.trend(p);
    final days = StatsLogic.lastDays(p, 14);
    final heat = TrainingLogic.heat(p, 'en');
    final weak = TrainingLogic.weakKeys(p, 'en');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _tile('أفضل WPM', p.best('best_wpm').round().toString(), C.cyan),
        _tile('المعدل', p.avgWpm.round().toString(), C.green),
        _tile('الدقة', '${StatsLogic.avgAccuracy(p).toStringAsFixed(1)}%', C.gold),
      ]),
      Row(children: [
        _tile('السباقات', '${p.counter('races')}', Colors.white),
        _tile('الانتصارات', '${p.counter('wins')}', C.gold),
        _tile('وقت اللعب', StatsScreen.fmtDuration(StatsLogic.playTime(p)), C.magenta),
      ]),
      const SizedBox(height: 8),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('تطور السرعة (آخر سباقاتك)', style: TextStyle(fontWeight: FontWeight.w900))),
            if (hist.length >= 6)
              Text('${trend >= 0 ? '▲' : '▼'} ${trend.abs().toStringAsFixed(1)} WPM', textDirection: TextDirection.ltr, style: TextStyle(color: trend >= 0 ? C.green : C.red, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: hist.length < 2
                ? const Center(child: Text('أكمل سباقين على الأقل لرؤية المنحنى', style: TextStyle(color: C.textDim)))
                : CustomPaint(size: const Size(double.infinity, 150), painter: LineChartPainter(hist.length > 60 ? hist.sublist(hist.length - 60) : hist)),
          ),
          if (hist.length >= 6) Padding(padding: const EdgeInsets.only(top: 4), child: Text(trend >= 1 ? 'اتجاهك صاعد — استمر!' : (trend <= -1 ? 'انخفاض بسيط؛ ركّز على الدقة أولاً.' : 'أداؤك مستقر.'), style: const TextStyle(color: C.textDim, fontSize: 12))),
        ]),
      ),
      const SizedBox(height: 10),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('أفضل سرعة يومياً — آخر 14 يوماً', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SizedBox(height: 110, child: CustomPaint(size: const Size(double.infinity, 110), painter: BarsPainter([for (final d in days) d.best], [for (final d in days) d.day.substring(8)])) ),
          const SizedBox(height: 4),
          Text('أيام اللعب: ${days.where((d) => d.races > 0).length} من 14  •  أحرف مكتوبة: ${days.fold<int>(0, (a, d) => a + d.chars)}', style: const TextStyle(color: C.textDim, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 10),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('خريطة الحروف الحرارية', style: TextStyle(fontWeight: FontWeight.w900)),
          const Text('الأحمر = حروف تخطئ فيها أكثر', style: TextStyle(color: C.textDim, fontSize: 12)),
          const SizedBox(height: 8),
          if (heat.isEmpty) const Text('ستظهر بعد بعض السباقات.', style: TextStyle(color: C.textDim)) else KeyboardGuide(heat: heat, showFingers: false),
          if (weak.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('أضعف حروفك: ${weak.map((e) => e.toUpperCase()).join('  ')}', textDirection: TextDirection.ltr, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800))),
        ]),
      ),
      const SizedBox(height: 10),
      GoalCard(profile: p),
    ]);
  }
}

class GoalCard extends ConsumerWidget {
  const GoalCard({super.key, required this.profile});
  final PlayerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final g = Goal.current(p);
    final ctl = ref.read(profileProvider.notifier);
    Future<void> setGoal(int initial) async {
      var v = initial.toDouble();
      final res = await showDialog<int>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
            title: const Text('هدفي الأسبوعي (WPM)'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${v.round()} WPM', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: C.cyan)),
              Slider(value: v, min: 10, max: 200, divisions: 190, onChanged: (x) => set(() => v = x)),
              Text('المقترح لك: ${Goal.suggest(p)} WPM', style: const TextStyle(color: C.textDim, fontSize: 12)),
            ]),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, v.round()), child: const Text('حفظ'))],
          ),
        ),
      );
      if (res != null) ctl.update((pp) => Goal.set(pp, res));
    }

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🎯 هدفي الأسبوعي', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (g == null) ...[
          Text('حدد سرعة تريد بلوغها هذا الأسبوع. المقترح لك: ${Goal.suggest(p)} WPM', style: const TextStyle(color: C.textDim)),
          const SizedBox(height: 8),
          NeonButton(label: 'تحديد الهدف', icon: Icons.flag_rounded, onPressed: () => setGoal(Goal.suggest(p))),
        ] else ...[
          Row(children: [
            Text('${Goal.weekBest(p).round()} / ${(g['target'] as num).toInt()} WPM', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'FiraMono')),
            const Spacer(),
            TextButton(onPressed: () => setGoal((g['target'] as num).toInt()), child: const Text('تعديل')),
          ]),
          ProgressBar(value: Goal.progress(p), color: Goal.achieved(p) ? C.green : C.cyan, height: 10),
          const SizedBox(height: 8),
          if (Goal.claimed(p))
            const Text('✅ استلمت مكافأة هذا الأسبوع', style: TextStyle(color: C.green, fontWeight: FontWeight.w800))
          else if (Goal.achieved(p))
            NeonButton(label: 'استلم 300 عملة + 5 جواهر', icon: Icons.card_giftcard_rounded, color: C.gold, onPressed: () {
              var ok = false;
              ctl.update((pp) => ok = Goal.claim(pp));
              if (ok) toast(context, 'مبروك! حققت هدفك الأسبوعي 🎉');
            })
          else
            const Text('العب في أي وضع لرفع أفضل سرعة لهذا الأسبوع.', style: TextStyle(color: C.textDim, fontSize: 12)),
        ],
      ]),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> v;
  LineChartPainter(this.v);
  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final maxV = max(10.0, v.reduce(max) * 1.1), minV = max(0.0, v.reduce(min) * 0.85);
    const padL = 30.0, padB = 4.0;
    final w = size.width - padL, h = size.height - padB;
    double x(int i) => padL + w * i / (v.length - 1);
    double y(double val) => h - h * ((val - minV) / (maxV - minV));
    final grid = Paint()..color = Colors.white12..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final gy = h * i / 3;
      canvas.drawLine(Offset(padL, gy), Offset(size.width, gy), grid);
      final val = maxV - (maxV - minV) * i / 3;
      final tp = TextPainter(text: TextSpan(text: val.round().toString(), style: const TextStyle(fontSize: 9, color: Colors.white54)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(0, gy - tp.height / 2));
    }
    final path = Path()..moveTo(x(0), y(v[0]));
    for (var i = 1; i < v.length; i++) {
      path.lineTo(x(i), y(v[i]));
    }
    final fill = Path.from(path)..lineTo(x(v.length - 1), h)..lineTo(x(0), h)..close();
    canvas.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.cyan.withValues(alpha: 0.35), C.cyan.withValues(alpha: 0)]).createShader(Rect.fromLTWH(0, 0, size.width, h)));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round..color = C.cyan);
    canvas.drawCircle(Offset(x(v.length - 1), y(v.last)), 5, Paint()..color = C.gold);
  }

  @override
  bool shouldRepaint(covariant LineChartPainter old) => old.v != v;
}

class BarsPainter extends CustomPainter {
  final List<double> v;
  final List<String> labels;
  BarsPainter(this.v, this.labels);
  @override
  void paint(Canvas canvas, Size size) {
    final maxV = max(10.0, v.fold<double>(0, max));
    final n = v.length;
    final bw = size.width / n;
    const labelH = 14.0;
    final h = size.height - labelH;
    for (var i = 0; i < n; i++) {
      final bh = h * (v[i] / maxV);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(i * bw + bw * 0.18, h - max(v[i] > 0 ? 3 : 1, bh), bw * 0.64, max(v[i] > 0 ? 3 : 1, bh)), const Radius.circular(4));
      canvas.drawRRect(r, Paint()..color = v[i] > 0 ? (i == n - 1 ? C.gold : C.cyan) : Colors.white10);
      final tp = TextPainter(text: TextSpan(text: labels[i], style: const TextStyle(fontSize: 9, color: Colors.white54)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(i * bw + (bw - tp.width) / 2, h + 2));
    }
  }

  @override
  bool shouldRepaint(covariant BarsPainter old) => old.v != v;
}
