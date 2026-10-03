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
import '../career/progress.dart';
import '../career/progress_screen.dart';
import '../career/rank.dart';
import '../career/tournament_screen.dart';
import '../career/world_tour_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../learn/learn_screens.dart';
import '../race/quick_race_sheet.dart';
import '../settings/settings_screen.dart';

class _Mode {
  final String icon, title, sub;
  final String? feature;
  final void Function(BuildContext) open;
  const _Mode(this.icon, this.title, this.sub, this.open, {this.feature});
}

/// The lobby.
///
/// Layout follows how top mobile games are built instead of how a website is built:
/// top HUD (level / wallet) → live event carousel → mission pods → one giant start button that is
/// always under the thumb. Nothing scrolls the call-to-action away.
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
        _Mode('📚', 'التعلّم', 'دروس • مفردات • شهادة', (c) => ModeFlow.push<void>(c, const LearnHubScreen())),
        _Mode('🎯', 'التدريب الذكي', 'خريطة حروفك الضعيفة', (c) => ModeFlow.push<void>(c, const TrainingScreen())),
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

  void _startRace(BuildContext context, WidgetRef ref) {
    ref.read(hapticsProvider).light();
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const QuickRaceSheet());
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(children: [
              _TopHud(name: p.name, avatar: avatars[p.avatar % avatars.length], level: li.level, progress: li.progress, coins: p.coins, gems: p.gems),
              const SizedBox(height: 10),
              const _EventStrip(),
              const SizedBox(height: 10),
              Expanded(
                child: GridView(
                  // keeping every pod built: no pop-in while scrolling, and instant to hit
                  cacheExtent: 900,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 112),
                  padding: const EdgeInsets.only(bottom: 10),
                  children: [for (final m in modes) _pod(context, ref, m, m.feature == null || db.featureOn(m.feature!))],
                ),
              ),
              _StartCta(onTap: () => _startRace(context, ref)),
              const SizedBox(height: 10),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _pod(BuildContext context, WidgetRef ref, _Mode m, bool on) => Opacity(
        opacity: on ? 1 : 0.45,
        child: Panel(
          padding: const EdgeInsets.all(12),
          onTap: on
              ? () {
                  ref.read(hapticsProvider).light();
                  m.open(context);
                }
              : () => toast(context, 'هذا الوضع متوقف مؤقتاً'),
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

/// Top HUD: identity on the right, wallet on the left — always visible, never scrolls away.
class _TopHud extends StatelessWidget {
  const _TopHud({required this.name, required this.avatar, required this.level, required this.progress, required this.coins, required this.gems});
  final String name, avatar;
  final int level, coins, gems;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Stack(alignment: Alignment.bottomCenter, children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.cyan, width: 1.5), boxShadow: [BoxShadow(color: C.cyan.withValues(alpha: 0.35), blurRadius: 10)]),
          child: CircleAvatar(backgroundColor: C.surface2, child: Text(avatar, style: const TextStyle(fontSize: 20))),
        ),
      ]),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: C.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.cyan.withValues(alpha: 0.5))),
              child: Text('المستوى $level', style: const TextStyle(color: C.cyan, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 6),
            Expanded(child: ProgressBar(value: progress, height: 6)),
          ]),
        ]),
      ),
      const SizedBox(width: 6),
      CurrencyChip(icon: Icons.monetization_on, color: C.gold, value: fmtCompact(coins)),
      const SizedBox(width: 4),
      CurrencyChip(icon: Icons.diamond, color: C.cyan, value: fmtCompact(gems)),
      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
    ]);
  }
}

/// Live, horizontally scrolling events — the "there is always something happening" layer.
/// Every card shows real progress pulled from the profile, and every tap jumps straight into it.
class _EventStrip extends ConsumerWidget {
  const _EventStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final streak = p.activeStreak();
    final tier = Ranks.tierOf(db, p.rankPoints);
    final daily = Quests.views(db, p, 'daily');
    final doneToday = daily.where((v) => v.done).length;
    final nextQuest = daily.where((v) => !v.done).firstOrNull;
    final questName = nextQuest == null ? 'أكملت مهام اليوم 🎉' : loc(nextQuest.q.name);
    final questProgress = nextQuest == null ? '—' : '${nextQuest.progress}/${nextQuest.q.target}';

    final cards = <Widget>[
      _EventCard(
        icon: '🔥',
        title: 'سلسلة الدخول',
        value: '$streak يوم',
        color: C.gold,
        onTap: () {
          ref.read(hapticsProvider).light();
          ModeFlow.push<void>(context, const DailyScreen());
        },
      ),
      _EventCard(
        icon: '🎯',
        title: 'مهمة اليوم',
        value: '$questName • $questProgress',
        color: C.green,
        onTap: () {
          ref.read(hapticsProvider).light();
          ModeFlow.push<void>(context, const DailyScreen());
        },
      ),
      _EventCard(
        icon: tier.icon.isNotEmpty ? tier.icon : '🥇',
        title: 'تصنيفك',
        value: '${tier.label} • ${p.rankPoints}',
        color: C.cyan,
        onTap: () {
          ref.read(hapticsProvider).light();
          ModeFlow.push<void>(context, const LeaderboardScreen());
        },
      ),
      _EventCard(
        icon: '📊',
        title: 'التقدّم اليومي',
        value: '$doneToday/${daily.length} مهام • الموسم ${db.season['id'] ?? '-'}',
        color: C.magenta,
        onTap: () {
          ref.read(hapticsProvider).light();
          ModeFlow.push<void>(context, const ProgressScreen());
        },
      ),
    ];

    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.icon, required this.title, required this.value, required this.color, required this.onTap});
  final String icon, title, value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 190,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 10)],
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
              Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The one button that matters: big, breathing, always under the thumb.
class _StartCta extends StatefulWidget {
  const _StartCta({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_StartCta> createState() => _StartCtaState();
}

class _StartCtaState extends State<_StartCta> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.scale(
          scale: 1 + 0.015 * t,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [Color(0xFF00B4D8), Color(0xFF7B2FF7), Color(0xFFFF2BD6)]),
              boxShadow: [BoxShadow(color: C.magenta.withValues(alpha: 0.30 + 0.25 * t), blurRadius: 16 + 12 * t, offset: const Offset(0, 5))],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onTap,
                child: const SizedBox(
                  height: 68,
                  child: Row(children: [
                    SizedBox(width: 16),
                    Text('⚡', style: TextStyle(fontSize: 30)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('سباق سريع', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        Text('3–7 منافسين • اضغط للانطلاق', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                      ]),
                    ),
                    Icon(Icons.play_circle_fill_rounded, size: 38),
                    SizedBox(width: 14),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
