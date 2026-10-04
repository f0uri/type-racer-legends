import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/services/analytics_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class TutorialStep {
  final IconData icon;
  final String title, body;
  final String? target; // word(s) the player must type
  final int? seconds; // optional time pressure (power-up words); the step repeats instead of failing
  const TutorialStep(this.icon, this.title, this.body, {this.target, this.seconds});
}

const tutorialSteps = <TutorialStep>[
  TutorialStep(Icons.flag, 'أهلاً بك في الحلبة!', 'ستتعلم الأساسيات في دقيقة واحدة. سباقاتك كلها ضد منافسين بالذكاء الاصطناعي — لا لاعبين حقيقيين — لذلك تلعب بهدوء وبلا ضغط.'),
  TutorialStep(Icons.keyboard, 'اكتب لتتحرك', 'كل حرف صحيح يدفع سيارتك للأمام. اكتب الكلمة التالية بالضبط:', target: 'race'),
  TutorialStep(Icons.local_fire_department, 'الدقة = السرعة', 'الحرف الخاطئ يبطئك ويقطع الكومبو. كلمات متتالية بلا أخطاء تملأ عدّاد النيترو وتطلق دفعة سرعة. اكتب الجملة:', target: 'fast and clean'),
  TutorialStep(Icons.shield, 'كلمات القوة', 'أثناء السباق تظهر كلمة مثل SHIELD أو EMP أو TURBO. اكتبها قبل أن ينتهي الوقت لتحصل على الدرع أو التعطيل أو التوربو. جرّب الآن:', target: 'shield', seconds: 8),
  TutorialStep(Icons.build, 'نقطة الصيانة', 'عند نقطة الصيانة اكتب الكلمة بلا خطأ لتحصل على شحنة نيترو، وإن أخطأت تخسر ثواني. تدرّب:', target: 'pit stop'),
  TutorialStep(Icons.casino, 'مضاعف المخاطرة', 'قبل السباق يمكنك تفعيل مضاعف x2: مكافآت أكبر، لكن كل خطأ يكلّفك أكثر. اختياري دائماً.'),
  TutorialStep(Icons.emoji_events, 'أنت جاهز!', 'جرّب الحملة للبدء، أو افتح «التعلّم» لتتقن الأصابع. حظاً موفقاً يا بطل!'),
];

/// Interactive tutorial: short typing drills with live feedback. Replayable from settings.
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key, this.reward = 200});
  final int reward;
  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> with SingleTickerProviderStateMixin {
  final ctl = TextEditingController();
  final focus = FocusNode();
  late final AnimationController shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  int step = 0;
  int typed = 0;
  int left = 0;
  Timer? timer;
  bool advancing = false;

  TutorialStep get cur => tutorialSteps[step];

  @override
  void initState() {
    super.initState();
    _enter();
  }

  @override
  void dispose() {
    timer?.cancel();
    shake.dispose();
    ctl.dispose();
    focus.dispose();
    super.dispose();
  }

  void _enter() {
    timer?.cancel();
    typed = 0;
    advancing = false;
    ctl.clear();
    final s = cur.seconds;
    if (s != null) {
      left = s * 10;
      timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        if (!mounted) return;
        setState(() => left--);
        if (left <= 0) {
          // retry instead of failing: the tutorial never punishes
          typed = 0;
          ctl.clear();
          left = s * 10;
          toast(context, 'انتهى الوقت — حاول مرة أخرى بهدوء');
        }
      });
    }
    if (cur.target != null) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? focus.requestFocus() : null);
  }

  void _next() {
    if (step >= tutorialSteps.length - 1) {
      _finish();
      return;
    }
    setState(() {
      step++;
      _enter();
    });
  }

  void _finish() {
    final first = !ref.read(profileProvider).flag('tutorialDone');
    ref.read(profileProvider.notifier).update((p) {
      if (first) p.addCoins(widget.reward);
      p.setFlag('tutorialDone');
    });
    ref.read(analyticsProvider).log('tutorial_complete');
    if (first) toast(context, 'حصلت على ${widget.reward} عملة هدية');
    Navigator.of(context).pop();
  }

  void _onChanged(String v) {
    final t = cur.target;
    if (t == null || advancing) return;
    if (!t.startsWith(v)) {
      HapticFeedback.lightImpact();
      shake.forward(from: 0);
      ctl.value = TextEditingValue(text: t.substring(0, typed), selection: TextSelection.collapsed(offset: typed));
      return;
    }
    setState(() => typed = v.length);
    if (v.length == t.length) {
      advancing = true;
      timer?.cancel();
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _next();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = cur;
    final t = s.target;
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: const AppBarTitle('الشرح التفاعلي'),
          actions: [TextButton(onPressed: _finish, child: const Text('تخطّي'))],
        ),
        body: GradientBg(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                ProgressBar(value: (step + 1) / tutorialSteps.length, height: 8),
                const SizedBox(height: 4),
                Text('${step + 1} / ${tutorialSteps.length}', textDirection: TextDirection.ltr, style: const TextStyle(color: C.textDim, fontSize: 12)),
                const Spacer(),
                Icon(s.icon, size: 60, color: C.cyan),
                const SizedBox(height: 10),
                Text(s.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text(s.body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: C.textDim, height: 1.5)),
                const SizedBox(height: 22),
                if (t != null) ...[
                  AnimatedBuilder(
                    animation: shake,
                    builder: (_, child) => Transform.translate(offset: Offset(sin(shake.value * pi * 6) * 9 * (1 - shake.value), 0), child: child),
                    child: Panel(
                      border: C.cyan,
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Center(
                          child: RichText(
                            text: TextSpan(style: const TextStyle(fontFamily: 'FiraMono', fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 2), children: [
                              TextSpan(text: t.substring(0, typed), style: const TextStyle(color: C.green)),
                              TextSpan(text: t.substring(typed), style: const TextStyle(color: Colors.white)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (s.seconds != null) Padding(padding: const EdgeInsets.only(top: 10), child: ProgressBar(value: (left / (s.seconds! * 10)).clamp(0, 1), color: C.gold, height: 8)),
                  const SizedBox(height: 14),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: ctl,
                      focusNode: focus,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.visiblePassword,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'FiraMono', fontSize: 22),
                      decoration: const InputDecoration(hintText: 'اكتب هنا'),
                      onChanged: _onChanged,
                    ),
                  ),
                ],
                const Spacer(),
                if (t == null) NeonButton(label: step == tutorialSteps.length - 1 ? 'ابدأ اللعب' : 'التالي', icon: Icons.arrow_back_rounded, onPressed: _next),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
