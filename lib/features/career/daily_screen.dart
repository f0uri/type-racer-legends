import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/common.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';
import '../race/engine/race_models.dart';
import 'progress.dart';
import '../race/ui/result_screen.dart';
import '../leaderboard/leaderboard_service.dart';
import 'mode_flow.dart';

class DailyLogic {
  /// Period record for today's daily challenge: {key, best, done, claimed}
  static Map<String, dynamic> dailyRec(PlayerProfile p, [DateTime? now]) {
    final d = p.m('daily');
    if (d['key'] != dayKey(now)) {
      d
        ..clear()
        ..['key'] = dayKey(now);
    }
    return d;
  }

  static Map<String, dynamic> weeklyRec(PlayerProfile p, [DateTime? now]) {
    final d = p.m('weeklyCh');
    if (d['key'] != weekKey(now)) {
      d
        ..clear()
        ..['key'] = weekKey(now);
    }
    return d;
  }

  static bool dailyDone(PlayerProfile p, [DateTime? now]) => (p.m('daily')['key'] == dayKey(now)) && p.m('daily')['done'] == true;
  static bool weeklyDone(PlayerProfile p, [DateTime? now]) => (p.m('weeklyCh')['key'] == weekKey(now)) && p.m('weeklyCh')['done'] == true;

  static bool qualifies(RaceResult r) => !r.suspicious && !r.timeUp && r.accuracy >= 90 && r.chars >= 30;

  /// Records the attempt. Returns the bonus granted (first qualifying completion of the period only).
  static Map<String, int> apply(PlayerProfile p, RaceResult r, {bool weekly = false, DateTime? now, ContentDb? db}) {
    final rec = weekly ? weeklyRec(p, now) : dailyRec(p, now);
    final out = {'coins': 0, 'xp': 0, 'gems': 0, 'first': 0};
    if (!qualifies(r)) return out;
    final best = (rec['best'] as num?)?.toDouble() ?? 0;
    if (r.wpm > best) rec['best'] = double.parse(r.wpm.toStringAsFixed(1));
    if (rec['done'] == true) return out;
    rec['done'] = true;
    out['first'] = 1;
    if (weekly) {
      out['coins'] = 500;
      out['gems'] = 15;
      out['xp'] = 150;
      p.addCounter('weekly_done', 1);
    } else {
      final streak = p.activeStreak(now);
      out['coins'] = 120 + (streak > 7 ? 7 : streak) * 15;
      out['xp'] = 40;
      p.addCounter('daily_done', 1);
    }
    p.addCoins(out['coins']!);
    p.addXp(out['xp']!);
    if (out['gems']! > 0) p.addGems(out['gems']!);
    if (db != null) Season.addPoints(p, db, weekly ? 100 : 30, now: now);
    return out;
  }
}

class DailyScreen extends ConsumerWidget {
  const DailyScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final db = ref.watch(contentProvider);
    final b = ModeFlow.builder(ModeFlow.container(context));
    final dText = db.dailyText(dayKey());
    final wText = b.weeklyText();
    final dRec = p.m('daily')['key'] == dayKey() ? p.m('daily') : const <String, dynamic>{};
    final wRec = p.m('weeklyCh')['key'] == weekKey() ? p.m('weeklyCh') : const <String, dynamic>{};
    return Scaffold(
      appBar: AppBar(title: const Text('التحديات')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Panel(child: Text('نص واحد لكل اللاعبين في اليوم (أو الأسبوع) بدون مكافآت السباق: لعب نقي، ويُقارن أداؤك بأشباح ذكاء اصطناعي. أعلى نتيجة تُرسل للوحات المتصدرين بعد التحقق من الخادم.', style: TextStyle(color: C.textDim, fontSize: 13))),
          const SizedBox(height: 12),
          _card(context, icon: '📅', title: 'تحدي اليوم', len: dText.len, done: dRec['done'] == true, best: (dRec['best'] as num?)?.toDouble(), reward: '🪙 120+ و ⚡ 40', onPlay: () => _play(context, false)),
          const SizedBox(height: 12),
          _card(context, icon: '🗓️', title: 'تحدي الأسبوع', len: wText.len, done: wRec['done'] == true, best: (wRec['best'] as num?)?.toDouble(), reward: '🪙 500  💎 15  ⚡ 150', onPlay: () => _play(context, true)),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, {required String icon, required String title, required int len, required bool done, double? best, required String reward, required VoidCallback onPlay}) => Panel(
        border: done ? C.green : C.cyan.withValues(alpha: 0.5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
            if (done) const Text('✅ مكتمل', style: TextStyle(color: C.green, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          Text('$len حرف • أفضل نتيجة: ${best == null ? '—' : '${best.round()} WPM'}', style: const TextStyle(color: C.textDim)),
          Text(done ? 'يمكنك اللعب مجدداً لتحسين نتيجتك (بدون مكافأة إضافية).' : 'جائزة أول إنجاز: $reward (بدقة 90%+)', style: const TextStyle(color: C.gold, fontSize: 12)),
          const SizedBox(height: 10),
          NeonButton(label: done ? 'العب مجدداً' : 'ابدأ التحدي', icon: Icons.play_arrow_rounded, onPressed: onPlay),
        ]),
      );

  void _play(BuildContext context, bool weekly) {
    final c = ModeFlow.container(context);
    if (!c.read(contentProvider).featureOn('daily')) {
      toast(context, 'التحديات متوقفة مؤقتاً');
      return;
    }
    ModeFlow.race(
      context,
      config: () {
        final b = ModeFlow.builder(c);
        return weekly ? b.weeklyChallenge() : b.dailyChallenge();
      },
      finish: (ctx, result, outcome, rebuild) {
        late Map<String, int> got;
        c.read(profileProvider.notifier).update((p) => got = DailyLogic.apply(p, result, weekly: weekly, db: c.read(contentProvider)));
        maybeSubmitScore(c, result);
        return ResultScreen(
          result: result,
          outcome: outcome,
          rebuild: rebuild,
          extra: [
            if (got['first'] == 1) ModeFlow.rewardPanel(weekly ? 'أنجزت تحدي الأسبوع!' : 'أنجزت تحدي اليوم!', coins: got['coins']!, xp: got['xp']!, gems: got['gems']!),
            if (got['first'] != 1 && !DailyLogic.qualifies(result)) const Panel(child: Text('لكي يُحتسب التحدي: دقة 90% أو أكثر على الأقل 30 حرفاً.', style: TextStyle(color: C.textDim))),
          ],
        );
      },
    );
  }
}
