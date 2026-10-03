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
import '../content/content_db.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../learn/learn_screens.dart';
import '../race/quick_race_sheet.dart';
import '../race/race_builder.dart';
import '../settings/settings_screen.dart';
import 'lobby_scene.dart';

class _Mode {
  final IconData icon;
  final String title, sub;
  final String? feature;
  final void Function(BuildContext) open;
  const _Mode(this.icon, this.title, this.sub, this.open, {this.feature});
}

/// The lobby.
///
/// Layout follows how top mobile games are built instead of how a website is built:
/// top HUD (level / wallet) then the live event carousel, then mission pods, then one giant start
/// always under the thumb. Nothing scrolls the call-to-action away.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// The four modes that must be reachable in one tap: they are the game's main loops.
  /// Everything else lives behind «المزيد» so the lobby stays a game lobby, not a grid of links.
  static const List<String> _heroTitles = ['الحملة', 'البطولات', 'التحديات', 'التعلّم'];

  List<_Mode> _modes(WidgetRef ref) => [
        _Mode(Icons.map, 'الحملة', '50 مرحلة • 6 بيئات • زعماء', (c) => ModeFlow.push<void>(c, const CampaignScreen())),
        _Mode(Icons.visibility, 'الأشباح', 'تحدَّ رقمك الشخصي', (c) => ModeFlow.push<void>(c, const GhostScreen())),
        _Mode(Icons.emoji_events, 'البطولات', 'يومية 8 • أسبوعية 16', (c) => ModeFlow.push<void>(c, const TournamentListScreen()), feature: 'tournament'),
        _Mode(Icons.link, 'تحدٍّ بالرابط', 'شارك سرعتك', (c) => ModeFlow.push<void>(c, const ChallengeHubScreen()), feature: 'link_challenge'),
        _Mode(Icons.local_fire_department, 'البقاء', 'لا تدع المطارد يلحق بك', _survival, feature: 'survival'),
        _Mode(Icons.rocket_launch, 'قتال الطريق', 'أطلق الصواريخ بكلماتك', _combat, feature: 'combat'),
        _Mode(Icons.calendar_month, 'التحديات', 'يومي وأسبوعي', (c) => ModeFlow.push<void>(c, const DailyScreen()), feature: 'daily'),
        _Mode(Icons.public, 'جولة العالم', '12 مدينة وختم', (c) => ModeFlow.push<void>(c, const WorldTourScreen()), feature: 'world_tour'),
        _Mode(Icons.military_tech, 'المتصدرون', 'عالمي • بلدي • أسبوعي', (c) => ModeFlow.push<void>(c, const LeaderboardScreen()), feature: 'leaderboard'),
        _Mode(Icons.school, 'التعلّم', 'دروس • مفردات • شهادة', (c) => ModeFlow.push<void>(c, const LearnHubScreen())),
        _Mode(Icons.track_changes, 'التدريب الذكي', 'خريطة حروفك الضعيفة', (c) => ModeFlow.push<void>(c, const TrainingScreen())),
        _Mode(Icons.edit_note, 'نص مخصص', 'تدرّب على نصك', (c) => ModeFlow.push<void>(c, const CustomTextScreen())),
      ];

  static void _survival(BuildContext context) {
    final c = ModeFlow.container(context);
    final best = c.read(profileProvider).best('survival_best');
    showModeIntro(
      context,
      icon: Icons.local_fire_department,
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
      icon: Icons.rocket_launch,
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
    final rig = PlayerRig.from(db, p);
    final modes = _modes(ref);
    final hero = [for (final m in modes) if (_heroTitles.contains(m.title)) m];
    final rest = [for (final m in modes) if (!_heroTitles.contains(m.title)) m];
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
                // the middle scrolls; the call-to-action never does
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 10),
                  children: [
                    Stack(children: [
                      LobbyScene(look: rig.look, height: 178),
                      Positioned(left: 10, bottom: 8, child: _sceneChip(Icons.directions_car_filled, loc(rig.vehicle.name))),
                      Positioned(right: 10, bottom: 8, child: _sceneChip(Icons.swipe, 'اسحب لتدوير مركبتك')),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      // exactly two rows: the four hero pods always fit without scrolling
                      height: 234,
                      child: GridView(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 112),
                        children: [for (final m in hero) _pod(context, ref, m, m.feature == null || db.featureOn(m.feature!))],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _moreTile(context, ref, rest.length, () => _more(context, ref, rest, db)),
                  ],
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

  /// Small overlay chip drawn on top of the lobby scene (car name / drag hint).
  Widget _sceneChip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: C.cyan.withValues(alpha: 0.32)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: C.cyan),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ]),
      );

  /// «المزيد»: one tap opens every secondary mode, so the lobby stays four big pods.
  Widget _moreTile(BuildContext context, WidgetRef ref, int count, VoidCallback onTap) => Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () {
          ref.read(hapticsProvider).light();
          onTap();
        },
        child: Row(children: [
          const Icon(Icons.grid_view_rounded, color: C.magenta, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('المزيد من الأوضاع', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              Text('$count أوضاع إضافية: أشباح، بقاء، قتال الطريق، جولة العالم، التدريب الذكي، نص مخصص', style: const TextStyle(color: C.textDim, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const Icon(Icons.chevron_left, color: C.textDim),
        ]),
      );

  void _more(BuildContext context, WidgetRef ref, List<_Mode> rest, ContentDb db) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('أوضاع إضافية', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 12),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 96),
              children: [
                for (final m in rest)
                  _pod(
                    context,
                    ref,
                    m,
                    m.feature == null || db.featureOn(m.feature!),
                    compact: true,
                    // close the sheet first, otherwise the pushed page sits on top of it forever
                    onOpen: () {
                      Navigator.of(context).pop();
                      m.open(context);
                    },
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pod(BuildContext context, WidgetRef ref, _Mode m, bool on, {bool compact = false, VoidCallback? onOpen}) => Opacity(
        opacity: on ? 1 : 0.45,
        child: Panel(
          padding: EdgeInsets.all(compact ? 10 : 12),
          onTap: on
              ? () {
                  ref.read(hapticsProvider).light();
                  if (onOpen != null) {
                    onOpen();
                  } else {
                    m.open(context);
                  }
                }
              : () => toast(context, 'هذا الوضع متوقف مؤقتاً'),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(m.icon, size: compact ? 22 : 26, color: C.cyan),
              const SizedBox(height: 2),
              Text(m.title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 13.5 : 15)),
              Text(m.sub, style: const TextStyle(color: C.textDim, fontSize: 11)),
            ]),
          ),
        ),
      );
}

/// Top HUD: identity on the right, wallet on the left — always visible, never scrolls away.
class _TopHud extends StatelessWidget {
  const _TopHud({required this.name, required this.avatar, required this.level, required this.progress, required this.coins, required this.gems});
  final String name;
  final IconData avatar;
  final int level, coins, gems;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Stack(alignment: Alignment.bottomCenter, children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.cyan, width: 1.5), boxShadow: [BoxShadow(color: C.cyan.withValues(alpha: 0.35), blurRadius: 10)]),
          child: CircleAvatar(backgroundColor: C.surface2, child: Icon(avatar, size: 20, color: C.cyan)),
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
    final questName = nextQuest == null ? 'أكملت مهام اليوم' : loc(nextQuest.q.name);
    final questProgress = nextQuest == null ? '—' : '${nextQuest.progress}/${nextQuest.q.target}';

    final cards = <Widget>[
      _EventCard(
        icon: Icons.local_fire_department,
        title: 'سلسلة الدخول',
        value: '$streak يوم',
        color: C.gold,
        onTap: () {
          ref.read(hapticsProvider).light();
          ModeFlow.push<void>(context, const DailyScreen());
        },
      ),
      _EventCard(
        icon: Icons.track_changes,
        title: 'مهمة اليوم',
        value: '$questName • $questProgress',
        color: C.green,
        onTap: () {
          ref.read(hapticsProvider).light();
          ModeFlow.push<void>(context, const DailyScreen());
        },
      ),
      _EventCard(
        icon: tier.icon,
        title: 'تصنيفك',
        value: '${tier.label} • ${p.rankPoints}',
        color: C.cyan,
        onTap: () {
          ref.read(hapticsProvider).light();
          ModeFlow.push<void>(context, const LeaderboardScreen());
        },
      ),
      _EventCard(
        icon: Icons.bar_chart,
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
  final IconData icon;
  final String title, value;
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
          Icon(icon, size: 20, color: color),
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
                    Icon(Icons.bolt, size: 30, color: Colors.white),
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
