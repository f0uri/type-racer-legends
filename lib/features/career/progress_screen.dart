import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/models/content_models.dart';
import '../content/content_db.dart';
import '../garage/look.dart';
import '../shop/iap_service.dart';
import 'progress.dart';
import 'rewards.dart';

/// Achievement glyphs as vector icons (never emoji: they must look identical on every device).
const achievementIcons = <String, IconData>{
  'races': Icons.flag,
  'trophy': Icons.emoji_events,
  'legend': Icons.workspace_premium,
  'speed': Icons.bolt,
  'target': Icons.track_changes,
  'combo': Icons.local_fire_department,
  'level': Icons.star,
  'nitro': Icons.rocket_launch,
  'chars': Icons.keyboard,
  'streak': Icons.calendar_month,
  'campaign': Icons.map,
  'stars': Icons.stars,
  'boss': Icons.sports_mma,
  'car': Icons.directions_car,
  'skin': Icons.palette,
  'rank': Icons.military_tech,
  'tournament': Icons.workspace_premium,
  'daily': Icons.calendar_today,
  'lesson': Icons.school,
  'vocab': Icons.menu_book,
  'power': Icons.shield,
  'pit': Icons.build,
  'survival': Icons.timer,
  'world': Icons.public,
  'upgrade': Icons.hardware,
  'combat': Icons.rocket_launch,
  'share': Icons.link,
  'camera': Icons.photo_camera,
  'quest': Icons.check_circle,
  'certificate': Icons.verified,
};

IconData achievementIcon(String key) => achievementIcons[key] ?? Icons.emoji_events;

void showRewardToast(BuildContext context, String title, List<String> lines) {
  toast(context, '$title  ${lines.join('  ')}');
}

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key, this.initialTab = 0, this.embedded = true});
  final int initialTab;
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !embedded,
          title: const Text('التقدم'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'المهام'), Tab(text: 'الموسم'), Tab(text: 'الإنجازات'), Tab(text: 'الأحداث')]),
        ),
        body: GradientBg(child: const TabBarView(children: [QuestsTab(), SeasonTab(), AchievementsTab(), EventsTab()])),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ quests

class QuestsTab extends ConsumerWidget {
  const QuestsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    return ListView(padding: const EdgeInsets.all(14), children: [
      const LoginStreakCard(),
      const SizedBox(height: 12),
      _section('مهام اليوم', _resetText('daily')),
      for (final v in Quests.views(db, p, 'daily')) _QuestRow(view: v, period: 'daily'),
      const SizedBox(height: 14),
      _section('مهام الأسبوع', _resetText('weekly')),
      for (final v in Quests.views(db, p, 'weekly')) _QuestRow(view: v, period: 'weekly'),
    ]);
  }

  static String _resetText(String period) {
    final now = DateTime.now();
    final end = period == 'weekly' ? DateTime(now.year, now.month, now.day).add(Duration(days: 8 - now.weekday)) : DateTime(now.year, now.month, now.day + 1);
    final d = end.difference(now);
    return d.inDays > 0 ? 'تتجدد بعد ${d.inDays} يوم' : 'تتجدد بعد ${d.inHours} ساعة';
  }

  Widget _section(String t, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const Spacer(), Text(sub, style: const TextStyle(color: C.textDim, fontSize: 12))]),
      );
}

class _QuestRow extends ConsumerWidget {
  const _QuestRow({required this.view, required this.period});
  final QuestView view;
  final String period;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final q = view.q;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Panel(
        border: view.claimed ? C.green.withValues(alpha: 0.4) : (view.done ? C.gold : Colors.white10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(loc(q.name), style: const TextStyle(fontWeight: FontWeight.w800))),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Rewards.preview(db, q.reward), style: const TextStyle(fontSize: 13)),
              Text('+${q.sp} نقطة موسم', style: const TextStyle(color: C.cyan, fontSize: 10)),
            ]),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: ProgressBar(value: view.fraction, color: view.done ? C.green : C.cyan, height: 9)),
            const SizedBox(width: 10),
            Text('${fmtInt(view.progress)}/${fmtInt(q.target)}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            if (view.claimed)
              const Icon(Icons.check_circle_rounded, color: C.green)
            else
              SizedBox(
                height: 32,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: view.done ? C.gold : Colors.white12, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12)),
                  onPressed: view.done
                      ? () {
                          List<String>? lines;
                          ref.read(profileProvider.notifier).update((p) => lines = Quests.claim(db, p, period, q.id));
                          if (lines != null) {
                            ref.read(audioProvider).play(Sfx.coin);
                            showRewardToast(context, 'مكافأة المهمة', lines!);
                          }
                        }
                      : null,
                  child: Text('استلام', style: TextStyle(fontWeight: FontWeight.w900, color: view.done ? Colors.black : Colors.white38)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

class LoginStreakCard extends ConsumerWidget {
  const LoginStreakCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final streak = p.activeStreak();
    final rewards = ((db.econ('streak')['rewards'] as List?) ?? const []).cast<Map>();
    final canClaim = LoginStreak.claimable(p);
    return Panel(
      border: canClaim ? C.gold : Colors.white10,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_fire_department, size: 26, color: C.gold),
          const SizedBox(width: 8),
          Expanded(child: Text('سلسلة الحضور: $streak ${streak == 1 ? 'يوم' : 'أيام'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          Text('الأفضل: ${p.m('streak')['best'] ?? 0}', style: const TextStyle(color: C.textDim, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < rewards.length; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: i < (streak % rewards.length == 0 && streak > 0 ? rewards.length : streak % rewards.length) ? C.green.withValues(alpha: 0.25) : C.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: i == (streak - (canClaim ? 1 : 0)).clamp(0, 999) % rewards.length && canClaim ? C.gold : Colors.white10),
                ),
                child: Column(children: [
                  Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  Text(Rewards.preview(db, rewards[i]), textAlign: TextAlign.center, style: const TextStyle(fontSize: 9)),
                ]),
              ),
            ),
        ]),
        if (canClaim) ...[
          const SizedBox(height: 10),
          NeonButton(label: 'استلم مكافأة اليوم', icon: Icons.card_giftcard_rounded, color: C.gold, height: 44, onPressed: () => claimLoginReward(context, ref)),
        ],
      ]),
    );
  }
}

void claimLoginReward(BuildContext context, WidgetRef ref) {
  final db = ref.read(contentProvider);
  List<String>? lines;
  ref.read(profileProvider.notifier).update((p) => lines = LoginStreak.claim(db, p));
  if (lines != null) {
    ref.read(audioProvider).play(Sfx.chest);
    showRewardToast(context, 'مكافأة الحضور', lines!);
  }
}

// ------------------------------------------------------------------------------------------------ season

class SeasonTab extends ConsumerWidget {
  const SeasonTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    if (!Season.enabled(db)) return const Center(child: Text('لا يوجد موسم حالياً', style: TextStyle(color: C.textDim)));
    final si = Season.info(db, p);
    if (si.id == 0) {
      return Center(child: Text('الموسم الأول يبدأ قريباً', style: const TextStyle(color: C.textDim)));
    }
    final premium = Season.isPremium(db, p);
    final color = hexColor(si.theme['color'] as String?, C.gold);
    final track = Season.track(db);
    final claimable = Season.claimableCount(db, p);
    final left = si.left;
    final iap = ref.watch(iapProvider);
    return ListView(padding: const EdgeInsets.all(14), children: [
      Panel(
        border: color,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('الموسم ${si.id} — ${loc(si.theme['name'])}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color))),
            Text(left.inDays > 0 ? 'ينتهي بعد ${left.inDays} يوم' : 'ينتهي بعد ${left.inHours} ساعة', style: const TextStyle(color: C.textDim, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.2), border: Border.all(color: color, width: 2)), alignment: Alignment.center, child: Text('${si.level}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ProgressBar(value: si.levelProgress, color: color, height: 10),
              const SizedBox(height: 4),
              Text(si.level >= si.maxLevel ? 'وصلت إلى القمة' : '${si.pointsInLevel}/${si.perLevel} نقطة للمستوى ${si.level + 1}', style: const TextStyle(color: C.textDim, fontSize: 12)),
            ])),
          ]),
          const SizedBox(height: 6),
          const Text('تكسب نقاط الموسم من السباقات والمهام والتحديات والبطولات.', style: TextStyle(color: C.textDim, fontSize: 11)),
        ]),
      ),
      const SizedBox(height: 10),
      if (!premium)
        Panel(
          border: C.gold,
          child: Row(children: [
            const Icon(Icons.workspace_premium, size: 30, color: C.gold),
            const SizedBox(width: 10),
            const Expanded(child: Text('Battle Pass المميز: مكافآت إضافية في كل مستوى، صناديق، ومظهر حصري.', style: TextStyle(fontSize: 13))),
            SizedBox(width: 120, child: NeonButton(label: iap.priceOf(db.season['premiumProduct'] as String? ?? 'battle_pass_premium') ?? 'اشترك', color: C.gold, height: 40, onPressed: iap.canBuy(db.season['premiumProduct'] as String? ?? 'battle_pass_premium') ? () => ref.read(iapProvider.notifier).buy(db.season['premiumProduct'] as String? ?? 'battle_pass_premium') : null)),
          ]),
        ),
      if (premium) const Panel(child: Text('Battle Pass المميز مفعّل', style: TextStyle(color: C.gold, fontWeight: FontWeight.w900))),
      const SizedBox(height: 10),
      if (claimable > 0)
        NeonButton(
          label: 'استلم كل المكافآت ($claimable)',
          icon: Icons.card_giftcard_rounded,
          color: C.gold,
          onPressed: () {
            var lines = <String>[];
            ref.read(profileProvider.notifier).update((pp) => lines = Season.claimAll(db, pp));
            ref.read(audioProvider).play(Sfx.chest);
            if (lines.isNotEmpty) showRewardToast(context, 'مكافآت الموسم', lines);
          },
        ),
      const SizedBox(height: 10),
      SizedBox(
        height: 184,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: track.length,
          itemBuilder: (_, i) => _TrackCell(row: track[i], level: (track[i]['level'] as num).toInt(), reached: si.level, premium: premium, color: color),
        ),
      ),
    ]);
  }
}

class _TrackCell extends ConsumerWidget {
  const _TrackCell({required this.row, required this.level, required this.reached, required this.premium, required this.color});
  final Map<String, dynamic> row;
  final int level, reached;
  final bool premium;
  final Color color;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final ok = level <= reached;
    final rec = p.m('season');
    final same = ((rec['id'] as num?)?.toInt() ?? 0) == Season.idAt(db);
    final freeDone = same && Season.claimedFree(p, level);
    final premDone = same && Season.claimedPrem(p, level);
    Widget cell(String side, bool done, bool locked) {
      final r = (row[side] as Map?)?.cast<String, dynamic>();
      final canClaim = ok && !done && !locked && r != null;
      return Expanded(
        child: PressFx(
          scale: 0.94,
          onTap: canClaim
              ? () {
                  List<String>? lines;
                  ref.read(profileProvider.notifier).update((pp) => lines = Season.claim(db, pp, level, premiumSide: side == 'premium'));
                  if (lines != null) {
                    ref.read(audioProvider).play(Sfx.coin);
                    showRewardToast(context, 'مستوى $level', lines!);
                  }
                }
              : null,
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: done ? C.green.withValues(alpha: 0.18) : (canClaim ? C.gold.withValues(alpha: 0.2) : C.surface2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: canClaim ? C.gold : (side == 'premium' ? C.gold.withValues(alpha: 0.35) : Colors.white10)),
            ),
            alignment: Alignment.center,
            child: r == null
                ? const Text('—')
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(Rewards.preview(db, r), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    if (done) const Icon(Icons.check_circle_rounded, size: 16, color: C.green) else if (locked) const Icon(Icons.lock_rounded, size: 14, color: Colors.white38),
                  ]),
          ),
        ),
      );
    }

    return Container(
      width: 86,
      margin: const EdgeInsets.only(left: 6),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 10),
          decoration: BoxDecoration(color: ok ? color : C.surface2, borderRadius: BorderRadius.circular(10)),
          child: Text('$level', style: TextStyle(fontWeight: FontWeight.w900, color: ok ? Colors.black : Colors.white54)),
        ),
        cell('premium', premDone, !premium),
        cell('free', freeDone, false),
      ]),
    );
  }
}

// ------------------------------------------------------------------------------------------------ achievements

class AchievementsTab extends ConsumerWidget {
  const AchievementsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    // group tiers of the same metric
    final groups = <String, List<Achievement>>{};
    for (final a in db.achievements.where((a) => a.enabled)) {
      groups.putIfAbsent(a.metric, () => []).add(a);
    }
    for (final l in groups.values) {
      l.sort((a, b) => a.tier.compareTo(b.tier));
    }
    final claimable = Achievements.claimableCount(db, p);
    final titles = p.m('titles').keys.cast<String>().toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      Panel(
        child: Row(children: [
          const Icon(Icons.emoji_events, size: 30, color: C.gold),
          const SizedBox(width: 10),
          Expanded(child: Text('${Achievements.unlockedCount(p)} / ${db.achievements.length} إنجاز', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          if (claimable > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(12)), child: Text('$claimable جاهزة', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12))),
        ]),
      ),
      const SizedBox(height: 10),
      const Text('الألقاب', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in titles)
          ChoiceChip(
            label: Text(loc(db.titles[t] ?? (t == 't_rookie' ? 'مبتدئ' : t))),
            selected: p.title == t,
            onSelected: (_) => ref.read(profileProvider.notifier).update((pp) => pp.setIdentity(title: t)),
          ),
      ]),
      const SizedBox(height: 14),
      for (final e in groups.entries) _family(context, ref, db, p, e.value),
    ]);
  }

  Widget _family(BuildContext context, WidgetRef ref, ContentDb db, dynamic p, List<Achievement> tiers) {
    // show the first tier that is not claimed yet (or the last one when everything is done)
    final next = tiers.firstWhere((a) => !Achievements.claimed(p, a.id), orElse: () => tiers.last);
    final unlocked = Achievements.unlocked(p, next.id);
    final claimed = Achievements.claimed(p, next.id);
    final value = Metrics.value(db, p, next.metric);
    final frac = (value / next.target).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Panel(
        border: unlocked && !claimed ? C.gold : (claimed ? C.green.withValues(alpha: 0.4) : Colors.white10),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: unlocked ? C.gold.withValues(alpha: 0.2) : C.surface2, border: Border.all(color: unlocked ? C.gold : Colors.white12)), alignment: Alignment.center, child: Opacity(opacity: unlocked ? 1 : 0.4, child: Icon(achievementIcon(next.icon), size: 24, color: unlocked ? C.gold : C.textDim))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(loc(next.name), style: const TextStyle(fontWeight: FontWeight.w900))),
                Text('${next.tier}/${next.of}', style: const TextStyle(color: C.textDim, fontSize: 11)),
              ]),
              Text(loc(next.desc), style: const TextStyle(color: C.textDim, fontSize: 12)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: ProgressBar(value: frac, color: unlocked ? C.gold : C.cyan, height: 7)),
                const SizedBox(width: 8),
                Text('${fmtCompact(value.floor())}/${fmtCompact(next.target)}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
              ]),
              Text(Rewards.preview(db, {...next.reward, if (next.title != null) 'title': next.title}), style: const TextStyle(fontSize: 11)),
            ]),
          ),
          if (unlocked && !claimed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: C.gold, foregroundColor: Colors.black),
                onPressed: () {
                  List<String>? lines;
                  ref.read(profileProvider.notifier).update((pp) => lines = Achievements.claim(db, pp, next.id));
                  if (lines != null) {
                    ref.read(audioProvider).play(Sfx.levelUp);
                    showRewardToast(context, 'إنجاز', lines!);
                  }
                },
                child: const Text('استلم', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            )
          else if (claimed)
            const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.check_circle_rounded, color: C.green)),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ events

class EventsTab extends ConsumerWidget {
  const EventsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final now = DateTime.now();
    final events = db.events.where((e) => e.enabled && (e.isActive(now) || e.isUpcoming(now))).toList();
    if (events.isEmpty) return const Center(child: Text('لا توجد أحداث حالياً. ترقّب الأحداث الموسمية!', style: TextStyle(color: C.textDim)));
    return ListView(padding: const EdgeInsets.all(14), children: [for (final e in events) _EventCard(event: e)]);
  }
}

class _EventCard extends ConsumerStatefulWidget {
  const _EventCard({required this.event});
  final GameEvent event;
  @override
  ConsumerState<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<_EventCard> {
  @override
  void initState() {
    super.initState();
    final e = widget.event;
    if (e.isActive()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final db = ref.read(contentProvider);
        final p = ref.read(profileProvider);
        if (p.m('events')[e.id] == null) ref.read(profileProvider.notifier).update((pp) => Events.ensure(db, pp, e), syncSoon: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final color = hexColor(e.color, C.cyan);
    final active = e.isActive();
    final done = active && Events.allDone(p, e);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Panel(
        border: color,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(loc(e.name), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color))),
            if (e.xpMultiplier > 1) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(10)), child: Text('خبرة ×${e.xpMultiplier}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12))),
          ]),
          Text(loc(e.desc), style: const TextStyle(color: C.textDim, fontSize: 13)),
          const SizedBox(height: 4),
          Text(active ? 'ينتهي: ${_fmt(e.endsAt)}' : 'يبدأ: ${_fmt(e.startsAt)}', style: const TextStyle(color: C.cyan, fontSize: 12)),
          if (e.featured.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final id in e.featured)
                Builder(builder: (_) {
                  final it = db.item(id);
                  return it == null ? const SizedBox.shrink() : Chip(visualDensity: VisualDensity.compact, label: Text(loc(it.name), style: const TextStyle(fontSize: 11)), side: BorderSide(color: C.rarity(it.rarity)));
                }),
            ]),
          ],
          const SizedBox(height: 8),
          for (final t in e.tasks) _task(db, p, e, t, active),
          if (active && e.finalReward.isNotEmpty) ...[
            const SizedBox(height: 6),
            NeonButton(
              label: 'المكافأة الكبرى ${Rewards.preview(db, e.finalReward)}',
              color: C.gold,
              height: 42,
              onPressed: done && !Events.taskClaimed(p, e, '_final')
                  ? () {
                      List<String>? lines;
                      ref.read(profileProvider.notifier).update((pp) => lines = Events.claimFinal(db, pp, e));
                      if (lines != null) showRewardToast(context, e.id, lines!);
                    }
                  : null,
            ),
          ],
        ]),
      ),
    );
  }

  String _fmt(DateTime? d) => d == null ? '—' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _task(ContentDb db, dynamic p, GameEvent e, Map<String, dynamic> t, bool active) {
    final target = (t['target'] as num).toInt();
    final prog = active ? Events.taskProgress(db, p, e, t) : 0;
    final claimed = Events.taskClaimed(p, e, t['id'] as String);
    final done = prog >= target;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(flex: 3, child: Text(_taskName(t), style: const TextStyle(fontSize: 12))),
        Expanded(flex: 3, child: ProgressBar(value: (prog / target).clamp(0.0, 1.0), height: 7, color: done ? C.green : C.cyan)),
        const SizedBox(width: 6),
        Text('${fmtCompact(prog.clamp(0, target))}/${fmtCompact(target)}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 6),
        if (claimed)
          const Icon(Icons.check_circle_rounded, color: C.green, size: 22)
        else
          SizedBox(
            height: 28,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: done && active ? C.gold : Colors.white12, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: done && active
                  ? () {
                      List<String>? lines;
                      ref.read(profileProvider.notifier).update((pp) => lines = Events.claimTask(db, pp, e, t['id'] as String));
                      if (lines != null) showRewardToast(context, 'مهمة الحدث', lines!);
                    }
                  : null,
              child: Text(Rewards.preview(db, (t['reward'] as Map?) ?? {}), style: const TextStyle(fontSize: 10, color: Colors.black)),
            ),
          ),
      ]),
    );
  }

  static const _metricNames = {'races': 'أكمل سباقات', 'wins': 'افز بسباقات', 'chars': 'اكتب أحرفاً', 'perfect_races': 'سباقات بدقة 100%', 'combo_max': 'أعلى كومبو'};
  String _taskName(Map<String, dynamic> t) => '${_metricNames[t['metric']] ?? t['metric']} (${t['target']})';
}

/// Small helper used by the home screen badges.
int progressBadgeCount(ContentDb db, dynamic p) => Quests.claimable(db, p) + Achievements.claimableCount(db, p) + Season.claimableCount(db, p) + (LoginStreak.claimable(p) ? 1 : 0);
