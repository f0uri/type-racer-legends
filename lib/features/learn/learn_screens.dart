import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/models/content_models.dart';
import '../career/mode_flow.dart';
import '../content/content_db.dart';
import '../leaderboard/leaderboard_service.dart';
import '../race/engine/race_models.dart';
import '../race/ui/result_screen.dart';
import '../stats/stats_logic.dart';
import 'certificate.dart';
import 'keyboard_guide.dart';
import 'learn_logic.dart';

class LearnHubScreen extends ConsumerWidget {
  const LearnHubScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final pl = p.m('placement');
    final done = LessonsLogic.completed(p);
    Widget card(IconData icon, String title, String sub, VoidCallback onTap, {String? badge}) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Panel(
            onTap: onTap,
            child: Row(children: [
              Icon(icon, size: 32, color: C.cyan),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), Text(sub, style: const TextStyle(color: C.textDim, fontSize: 12))])),
              if (badge != null) Text(badge, style: const TextStyle(color: C.cyan, fontWeight: FontWeight.w900)),
              const Icon(Icons.chevron_left_rounded),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('التعلّم')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (pl['wpm'] != null)
            Panel(
              border: C.cyan,
              child: Row(children: [
                const Icon(Icons.bar_chart, size: 28, color: C.cyan),
                const SizedBox(width: 10),
                Expanded(child: Text('مستواك: ${pl['level'] ?? ''} — ${(pl['wpm'] as num).round()} WPM بدقة ${(pl['acc'] as num).round()}%', style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ),
          const SizedBox(height: 10),
          card(Icons.keyboard, 'دروس الكتابة بالأصابع العشرة', 'خريطة الأصابع + 30 درساً متدرجاً', () => ModeFlow.push<void>(context, const LessonsScreen()), badge: '$done/${db.lessons.length}'),
          card(Icons.timer, 'الاختبار الرسمي (60 ثانية)', 'يحدد مستواك ويمنحك شهادة PDF قابلة للمشاركة', () => ModeFlow.push<void>(context, const OfficialTestScreen())),
          card(Icons.menu_book, 'المفردات: من العربية إلى الإنجليزية', 'اكتب الكلمة الإنجليزية لمعناها العربي', () => ModeFlow.push<void>(context, const VocabScreen()), badge: '${VocabLogic.mastered(p)} متقنة'),
          card(Icons.track_changes, 'التدريب الذكي', 'خريطة حرارية لأضعف حروفك + نص مصمم لها', () => ModeFlow.push<void>(context, const TrainingScreen())),
          card(Icons.verified, 'شهاداتي', '${p.m('certs').length} شهادة', () => ModeFlow.push<void>(context, const CertificatesScreen())),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ lessons

class LessonsScreen extends ConsumerWidget {
  const LessonsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final learned = LessonsLogic.learnedKeys(db, p);
    return Scaffold(
      appBar: AppBar(title: const Text('دروس الكتابة')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(14), children: [
          const Panel(child: Text('ضع أصابعك على الصف الرئيسي (ASDF · JKL;) وانظر إلى الشاشة لا إلى المفاتيح. كل لون يمثل إصبعاً.', style: TextStyle(color: C.textDim, fontSize: 12))),
          const SizedBox(height: 8),
          KeyboardGuide(learned: learned),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 2, children: [for (var i = 0; i < Fingers.names.length; i++) if (i != 4) Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: Fingers.colors[i], shape: BoxShape.circle)), const SizedBox(width: 4), Text(Fingers.names[i], style: const TextStyle(fontSize: 10, color: C.textDim))])]),
          const SizedBox(height: 10),
          for (final l in db.lessons) _row(context, ref, db, p, l),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, ContentDb db, dynamic p, Lesson l) {
    final open = LessonsLogic.unlocked(p, db, l);
    final st = LessonsLogic.stars(p, l);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Panel(
        border: st > 0 ? C.green.withValues(alpha: 0.5) : (open ? C.cyan.withValues(alpha: 0.5) : Colors.white10),
        onTap: open ? () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => LessonSheet(lesson: l)) : () => toast(context, 'أكمل الدرس السابق أولاً'),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(shape: BoxShape.circle, color: C.surface2, border: Border.all(color: open ? C.cyan : Colors.white24)), alignment: Alignment.center, child: open ? Text('${l.n}', style: const TextStyle(fontWeight: FontWeight.w900)) : const Icon(Icons.lock_rounded, size: 18, color: Colors.white38)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(loc(l.title), style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('الهدف: ${l.targetWpm} WPM بدقة ${l.minAcc}%', style: const TextStyle(color: C.textDim, fontSize: 11)),
          ])),
          starRow(st, size: 18),
        ]),
      ),
    );
  }
}

class LessonSheet extends ConsumerWidget {
  const LessonSheet({super.key, required this.lesson});
  final Lesson lesson;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final l = lesson;
    final learned = LessonsLogic.learnedKeys(db, p)..addAll(l.allowed.split('').where((c) => c != ' '));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الدرس ${l.n}: ${loc(l.title)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          KeyboardGuide(next: l.focus.isEmpty ? null : l.focus[0], learned: learned, compact: true),
          const SizedBox(height: 6),
          Text(l.hint, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 8),
          Text('لنجاح الدرس: ${l.targetWpm} WPM بدقة ${l.minAcc}% أو أكثر. ${l.len} حرفاً.', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 12),
          NeonButton(
            label: 'ابدأ الدرس',
            icon: Icons.keyboard_rounded,
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              LearnFlow.lesson(nav.context, l);
            },
          ),
        ]),
      ),
    );
  }
}

extension on Lesson {
  int get len => text.length;
}

class LearnFlow {
  static void lesson(BuildContext context, Lesson l) {
    final c = ModeFlow.container(context);
    final db = c.read(contentProvider);
    ModeFlow.race(
      context,
      config: () => LessonsLogic.config(l),
      finish: (ctx, result, outcome, rebuild) {
        late LessonOutcome lo;
        c.read(profileProvider.notifier).update((p) => lo = LessonsLogic.apply(p, db, l, result));
        final next = db.lessons.where((x) => x.n == l.n + 1).firstOrNull;
        return ResultScreen(
          result: result,
          outcome: outcome,
          rebuild: rebuild,
          primaryLabel: lo.passed && next != null ? 'الدرس التالي' : null,
          onPrimary: lo.passed && next != null
              ? () {
                  final nav = Navigator.of(ctx);
                  nav.pop();
                  LearnFlow.lesson(nav.context, next);
                }
              : null,
          extra: [
            Panel(
              border: lo.passed ? C.green : C.red,
              child: Column(children: [
                Text(lo.passed ? 'نجحت في الدرس ${l.n}' : 'لم تصل للهدف: ${l.targetWpm} WPM بدقة ${l.minAcc}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: lo.passed ? C.green : C.red)),
                const SizedBox(height: 6),
                starRow(lo.stars, size: 32),
                if (lo.rewardLines.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(lo.rewardLines.join('   '), style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800))),
              ]),
            ),
          ],
        );
      },
    );
  }

  static void official(BuildContext context) {
    final c = ModeFlow.container(context);
    final db = c.read(contentProvider);
    ModeFlow.race(
      context,
      config: () => OfficialTest.config(db, Random(), lang: 'en'),
      finish: (ctx, result, outcome, rebuild) {
        CertificateData? cert;
        c.read(profileProvider.notifier).update((p) {
          cert = OfficialTest.apply(p, db, result);
          if (cert != null && Goal.current(p) == null) Goal.set(p, Goal.suggest(p));
        });
        maybeSubmitScore(c, result);
        final rec = LessonsLogic.recommended(result.wpm);
        return ResultScreen(
          result: result,
          outcome: outcome,
          rebuild: rebuild,
          extra: [
            Panel(
              border: C.cyan,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('مستواك: ${OfficialTest.levelFor(result.wpm).label}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: C.cyan)),
                const SizedBox(height: 4),
                Text('ننصحك بالبدء من الدرس $rec في دروس الكتابة.', style: const TextStyle(color: C.textDim)),
                if (cert == null) const Padding(padding: EdgeInsets.only(top: 6), child: Text('للحصول على شهادة: دقة 90% على الأقل وأكثر من 60 حرفاً بدون إدخال مشبوه.', style: TextStyle(color: C.gold, fontSize: 12))),
              ]),
            ),
            if (cert != null) ...[
              const SizedBox(height: 10),
              NeonButton(label: 'مشاركة الشهادة (PDF)', icon: Icons.picture_as_pdf_rounded, color: C.gold, onPressed: () => CertificateRenderer.share(cert!)),
            ],
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------------------------------------ official test

class OfficialTestScreen extends ConsumerWidget {
  const OfficialTestScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final pl = p.m('placement');
    return Scaffold(
      appBar: AppBar(title: const Text('الاختبار الرسمي')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Panel(child: Text('اختبار كتابة لمدة 60 ثانية على نص إنجليزي ثابت، بدون نيترو أو مكافآت أو عقوبات: سرعتك الحقيقية فقط. تُستخدم النتيجة لتحديد مستواك، ويُصدر لك شهادة PDF عند دقة 90% أو أكثر. كما تُرسل للوحة المتصدرين بعد تحقق الخادم.', style: TextStyle(height: 1.6))),
          const SizedBox(height: 12),
          if (pl['wpm'] != null) Panel(child: Text('آخر نتيجة: ${(pl['wpm'] as num).round()} WPM • دقة ${(pl['acc'] as num).round()}% • ${pl['level']}', style: const TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(height: 14),
          NeonButton(label: 'ابدأ الاختبار', icon: Icons.timer_rounded, onPressed: () => LearnFlow.official(context)),
        ]),
      ),
    );
  }
}

class CertificatesScreen extends ConsumerWidget {
  const CertificatesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final pl = p.m('placement');
    final certs = p.m('certs');
    final latest = certs.entries.isEmpty ? '' : (certs.entries.toList()..sort((a, b) => (b.value as num).compareTo(a.value as num))).first.key;
    return Scaffold(
      appBar: AppBar(title: const Text('شهاداتي')),
      body: GradientBg(
        child: certs.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد شهادات بعد. أنهِ الاختبار الرسمي بدقة 90% أو أكثر.', textAlign: TextAlign.center, style: TextStyle(color: C.textDim))))
            : ListView(padding: const EdgeInsets.all(16), children: [
                for (final e in (certs.entries.toList()..sort((a, b) => (b.value as num).compareTo(a.value as num))))
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      child: Row(children: [
                        const Icon(Icons.verified, size: 30, color: C.gold),
                        const SizedBox(width: 10),
                        Expanded(child: Text('${e.key}\n${DateTime.fromMillisecondsSinceEpoch((e.value as num).toInt()).toString().substring(0, 10)}', style: const TextStyle(fontFamily: 'FiraMono', fontSize: 13))),
                        if (e.key == latest && pl['wpm'] != null)
                          IconButton(
                            icon: const Icon(Icons.share_rounded, color: C.gold),
                            onPressed: () {
                              final when = DateTime.fromMillisecondsSinceEpoch((e.value as num).toInt());
                              CertificateRenderer.share(CertificateData(name: p.name, wpm: (pl['wpm'] as num?)?.toDouble() ?? 0, accuracy: (pl['acc'] as num?)?.toDouble() ?? 0, level: (pl['level'] as String?) ?? '', date: when, code: e.key, chars: 0, seconds: 60));
                            },
                          ),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ vocabulary

class VocabScreen extends ConsumerWidget {
  const VocabScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final mastered = VocabLogic.mastered(p), seen = VocabLogic.seen(p);
    return Scaffold(
      appBar: AppBar(title: const Text('المفردات')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat('$seen', 'كلمة شاهدتها'),
                _stat('$mastered', 'كلمة أتقنتها'),
                _stat('${db.vocab.length}', 'المجموع'),
              ]),
              const SizedBox(height: 8),
              ProgressBar(value: db.vocab.isEmpty ? 0 : mastered / db.vocab.length, color: C.gold),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('يظهر معنى الكلمة بالعربية فوق النص، واكتب الكلمة الإنجليزية. الكلمات التي تكتبها بلا خطأ ترتقي في نظام المراجعة المتباعدة، وتظهر الضعيفة أكثر.', style: TextStyle(color: C.textDim, fontSize: 12, height: 1.5)),
          const SizedBox(height: 14),
          NeonButton(label: 'ابدأ جولة (12 كلمة)', icon: Icons.translate_rounded, onPressed: () => _start(context, 12)),
          const SizedBox(height: 8),
          NeonButton(label: 'جولة سريعة (6 كلمات)', filled: false, onPressed: () => _start(context, 6)),
        ]),
      ),
    );
  }

  Widget _stat(String v, String l) => Column(children: [Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: C.cyan)), Text(l, style: const TextStyle(color: C.textDim, fontSize: 11))]);

  void _start(BuildContext context, int n) {
    final c = ModeFlow.container(context);
    final db = c.read(contentProvider);
    if (db.vocab.isEmpty) {
      toast(context, 'لا توجد مفردات متاحة');
      return;
    }
    late List<VocabWord> words;
    RaceConfig mk() {
      words = VocabLogic.pick(db, c.read(profileProvider), n, Random());
      return VocabLogic.config(words);
    }

    ModeFlow.race(
      context,
      config: mk,
      finish: (ctx, result, outcome, rebuild) {
        var clean = 0;
        final used = List<VocabWord>.from(words);
        c.read(profileProvider.notifier).update((p) => clean = VocabLogic.record(p, used, result));
        return ResultScreen(
          result: result,
          outcome: outcome,
          rebuild: rebuild,
          extra: [
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$clean من ${used.length} كلمة بلا أخطاء', style: const TextStyle(fontWeight: FontWeight.w900, color: C.green)),
                const SizedBox(height: 6),
                for (final w in used)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Icon(((result.wordStats[w.en] as num?) ?? 0) == 0 ? Icons.check_circle : Icons.error_outline, size: 16, color: ((result.wordStats[w.en] as num?) ?? 0) == 0 ? C.green : C.gold),
                      const SizedBox(width: 6),
                      Text(w.en, textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'FiraMono', fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(w.ar, style: const TextStyle(color: C.textDim)),
                    ]),
                  ),
              ]),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------------------------------------ smart training

class TrainingScreen extends ConsumerWidget {
  const TrainingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final lang = ref.watch(settingsProvider).textLang;
    final heat = TrainingLogic.heat(p, lang);
    final weak = TrainingLogic.weakKeys(p, lang);
    final stats = TrainingLogic.stats(p, lang).where((s) => s.attempts >= TrainingLogic.minAttempts && s.ch.trim().isNotEmpty).toList()..sort((a, b) => b.errorRate.compareTo(a.errorRate));
    return Scaffold(
      appBar: AppBar(title: const Text('التدريب الذكي')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Panel(child: Text('الخريطة الحرارية تُبنى من أدائك الفعلي في كل السباقات: الأحمر = حروف تخطئ فيها أو تتأخر عليها. نصوص التدريب تُولَّد من كلمات حقيقية تحتوي هذه الحروف.', style: TextStyle(color: C.textDim, fontSize: 12, height: 1.5))),
          const SizedBox(height: 10),
          KeyboardGuide(heat: heat, showFingers: false),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 60, height: 8, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1F6F4A), Color(0xFFE5383B)]), borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 8),
            const Text('جيد ضعيف', style: TextStyle(fontSize: 11, color: C.textDim)),
          ]),
          const SizedBox(height: 12),
          if (heat.isEmpty)
            const Panel(child: Text('لا توجد بيانات كافية بعد. تسابق بضع مرات (30 حرفاً على الأقل في كل سباق) وسنحدد لك أضعف حروفك. يمكنك مع ذلك بدء تدريب متوازن.', style: TextStyle(color: C.textDim)))
          else ...[
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('أضعف الحروف', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final k in weak) Chip(label: Text(k.toUpperCase(), style: const TextStyle(fontFamily: 'FiraMono', fontWeight: FontWeight.w900)), backgroundColor: C.red.withValues(alpha: 0.2), side: const BorderSide(color: C.red)),
                  if (weak.isEmpty) const Text('لا توجد نقاط ضعف واضحة — أداء ممتاز!', style: TextStyle(color: C.green)),
                ]),
                const SizedBox(height: 8),
                for (final s in stats.take(5)) Text('${s.ch.toUpperCase()}: ${(s.errorRate * 100).toStringAsFixed(1)}% أخطاء • ${s.avgMs.round()}ms', style: const TextStyle(color: C.textDim, fontSize: 12, fontFamily: 'FiraMono')),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          NeonButton(label: weak.isEmpty ? 'تدريب متوازن' : 'ابدأ تدريباً على حروفك الضعيفة', icon: Icons.gps_fixed_rounded, onPressed: () => start(context, weak, lang)),
        ]),
      ),
    );
  }

  static void start(BuildContext context, List<String> weak, String lang) {
    final c = ModeFlow.container(context);
    ModeFlow.race(context, config: () => TrainingLogic.config(TrainingLogic.drill(c.read(contentProvider), weak, Random(), lang: lang == 'en' || lang == 'fr' ? lang : 'en'), weak), finish: (ctx, result, outcome, rebuild) {
      return ResultScreen(result: result, outcome: outcome, rebuild: rebuild, extra: [
        Panel(child: Text(weak.isEmpty ? 'أحسنت! كرر التدريب يومياً لتثبيت السرعة.' : 'تدربت على: ${weak.map((e) => e.toUpperCase()).join(' ')} — الأخطاء الجديدة تُحدّث خريطتك الحرارية تلقائياً.', style: const TextStyle(color: C.textDim))),
      ]);
    });
  }
}
