import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/countries.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../career/campaign_screen.dart';
import '../career/challenge_link.dart';
import '../career/custom_text_screen.dart';
import '../career/daily_screen.dart';
import '../career/ghost_screen.dart';
import '../career/mode_flow.dart';
import '../career/modes_support.dart';
import '../career/tournament_screen.dart';
import '../career/world_tour_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../race/quick_race_sheet.dart';
import '../settings/settings_screen.dart';

class _Mode {
  final String icon, title, sub;
  final String? feature;
  final void Function(BuildContext) open;
  const _Mode(this.icon, this.title, this.sub, this.open, {this.feature});
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  List<_Mode> _modes(WidgetRef ref) => [
        _Mode('🗺️', 'الحملة', '50 مرحلة • 6 بيئات • زعماء', (c) => ModeFlow.push<void>(c, const CampaignScreen())),
        _Mode('👻', 'الأشباح', 'تحدَّ رقمك الشخصي', (c) => ModeFlow.push<void>(c, const GhostScreen())),
        _Mode('🏆', 'البطولات', 'يومية 8 • أسبوعية 16', (c) => ModeFlow.push<void>(c, const TournamentListScreen()), feature: 'tournament'),
        _Mode('🔗', 'تحدٍّ بالرابط', 'شارك سرعتك', (c) => ModeFlow.push<void>(c, const ChallengeHubScreen()), feature: 'link_challenge'),
        _Mode('🔥', 'البقاء', 'لا تدع المطارد يلحق بك', _survival, feature: 'survival'),
        _Mode('💥', 'قتال الطريق', 'أطلق الصواريخ بكلماتك', _combat, feature: 'combat'),
        _Mode('📅', 'التحديات', 'يومي وأسبوعي', (c) => ModeFlow.push<void>(c, const DailyScreen()), feature: 'daily'),
        _Mode('🌍', 'جولة العالم', '12 مدينة وختم', (c) => ModeFlow.push<void>(c, const WorldTourScreen()), feature: 'world_tour'),
        _Mode('🥇', 'المتصدرون', 'عالمي • بلدي • أسبوعي', (c) => ModeFlow.push<void>(c, const LeaderboardScreen()), feature: 'leaderboard'),
        _Mode('✍️', 'نص مخصص', 'تدرّب على نصك', (c) => ModeFlow.push<void>(c, const CustomTextScreen())),
      ];

  static void _survival(BuildContext context) {
    final c = ModeFlow.container(context);
    final best = c.read(profileProvider).best('survival_best');
    showModeIntro(
      context,
      icon: '🔥',
      title: 'البقاء',
      bullets: const ['يطاردك مركبة ذكاء اصطناعي تتسارع باستمرار.', 'اكتب بسرعة لتبقى أمامها؛ كل خطأ يبطئك.', 'نص طويل متواصل — النتيجة هي مدة صمودك.'],
      bestLine: best > 0 ? 'أفضل صمود: ${best.round()} ثانية' : null,
      onStart: () => ModeFlow.race(context, config: () => ModeFlow.builder(c).survival()),
    );
  }

  static void _combat(BuildContext context) {
    final c = ModeFlow.container(context);
    final kills = c.read(profileProvider).counter('combat_kills');
    showModeIntro(
      context,
      icon: '💥',
      title: 'قتال الطريق',
      bullets: const ['كل كلمة تكتبها بلا خطأ تطلق صاروخاً على أقرب منافس.', 'لكل منافس 3 نقاط صحة (الزعماء 6).', 'عندما يهاجمك منافس تظهر كلمة تحذير: اكتبها بسرعة لتتفادى الضربة.', 'اربح بتدمير الجميع أو بالوصول أولاً.'],
      bestLine: kills > 0 ? 'إجمالي ما دمّرته: $kills' : null,
      onStart: () => ModeFlow.race(context, config: () => ModeFlow.builder(c).combat()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final li = ref.watch(levelInfoProvider);
    final db = ref.watch(contentProvider);
    final modes = _modes(ref);
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(children: [
              Row(children: [
                CircleAvatar(backgroundColor: C.surface2, child: Text(avatars[p.avatar % avatars.length], style: const TextStyle(fontSize: 22))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('المستوى ${li.level}', style: const TextStyle(color: C.textDim, fontSize: 12)),
                  ProgressBar(value: li.progress, height: 6),
                ])),
                const SizedBox(width: 6),
                CurrencyChip(icon: Icons.monetization_on, color: C.gold, value: fmtCompact(p.coins)),
                const SizedBox(width: 4),
                CurrencyChip(icon: Icons.diamond, color: C.cyan, value: fmtCompact(p.gems)),
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
              ]),
              const SizedBox(height: 14),
              _hero(context),
              const SizedBox(height: 14),
              Expanded(
                child: GridView(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 112),
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [for (final m in modes) _card(context, m, m.feature == null || db.featureOn(m.feature!))],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) => GestureDetector(
        onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const QuickRaceSheet()),
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF00B4D8), Color(0xFF7B2FF7), Color(0xFFFF2BD6)]),
            boxShadow: [BoxShadow(color: C.magenta.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: const Row(children: [
            Text('⚡', style: TextStyle(fontSize: 42)),
            SizedBox(width: 14),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('سباق سريع', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  Text('3–7 منافسين بالذكاء الاصطناعي', style: TextStyle(color: Colors.white70)),
                ]),
              ),
            ),
            Icon(Icons.play_circle_fill_rounded, size: 40),
          ]),
        ),
      );

  Widget _card(BuildContext context, _Mode m, bool on) => Opacity(
        opacity: on ? 1 : 0.45,
        child: Panel(
          padding: const EdgeInsets.all(12),
          onTap: on ? () => m.open(context) : () => toast(context, 'هذا الوضع متوقف مؤقتاً'),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.icon, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 2),
              Text(m.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              Text(m.sub, style: const TextStyle(color: C.textDim, fontSize: 11)),
            ]),
          ),
        ),
      );
}
