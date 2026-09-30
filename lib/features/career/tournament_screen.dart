import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';
import '../race/engine/race_models.dart';
import '../race/ui/result_screen.dart';
import 'mode_flow.dart';
import 'tournament_logic.dart';

class TournamentListScreen extends ConsumerWidget {
  const TournamentListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('البطولات')),
      body: GradientBg(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Panel(
              child: Text(
                'بطولات إقصائية ضد منافسين بالذكاء الاصطناعي. التشكيلة ثابتة طوال اليوم أو الأسبوع، ولك محاولة واحدة لكل بطولة.',
                style: TextStyle(color: C.textDim, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            for (final d in db.tournaments) ...[
              _card(context, d, TournamentLogic.stateOf(p, d)),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, TournamentDef d, TournamentState? s) {
    final status = s == null
        ? 'لم تشارك بعد'
        : (s.won
              ? '🏆 أنت البطل!'
              : (s.alive
                    ? 'جولة ${s.round + 1} من ${d.rounds}'
                    : 'خرجت في الجولة ${s.round + 1}'));
    return Panel(
      onTap: () => ModeFlow.push<void>(context, TournamentScreen(def: d)),
      child: Row(
        children: [
          Text(
            d.period == 'weekly' ? '🏆' : '🥇',
            style: const TextStyle(fontSize: 34),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc(d.name),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${d.size} متسابقين • ${d.rounds} جولات • ${d.period == 'weekly' ? 'أسبوعية' : 'يومية'}',
                  style: const TextStyle(color: C.textDim, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: s?.won == true ? C.gold : C.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded),
        ],
      ),
    );
  }
}

class TournamentScreen extends ConsumerWidget {
  const TournamentScreen({super.key, required this.def});
  final TournamentDef def;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final st = TournamentLogic.stateOf(p, def);
    final bracket = st == null
        ? Bracket.generate(
            db,
            def,
            TournamentLogic.periodKey(def),
            playerName: p.name,
            playerCc: p.country,
            playerWpm: ModeFlow.builder(ModeFlow.container(context))
                .targetWpm(),
          )
        : TournamentLogic.bracketFor(db, p, def, st);
    if (st == null) bracket.resolveRound(0);
    final rewards = def.rewards;
    return Scaffold(
      appBar: AppBar(title: Text(loc(def.name))),
      body: GradientBg(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    height: max(
                      MediaQuery.of(context).size.height * 0.5,
                      def.size / 2 * 72.0 + 40,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var r = 0; r < def.rounds; r++)
                          _RoundColumn(
                            round: r,
                            bracket: bracket,
                            def: def,
                            current: st?.round == r && st!.alive,
                          ),
                        _Champion(bracket: bracket, st: st),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  Text(
                    'الجوائز: ${_rewardLine(rewards)}',
                    style: const TextStyle(color: C.textDim, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'جميع المتسابقين في البطولة ذكاء اصطناعي.',
                    style: TextStyle(color: C.textDim, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  _action(context, ref, db, p, st, bracket),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _rewardLine(Map<String, dynamic> r) {
    final w = r['win'];
    if (w is! Map) return '—';
    return '🪙 ${w['coins'] ?? 0}${w['gems'] != null ? '  💎 ${w['gems']}' : ''}${w['title'] != null ? '  🏷️ لقب' : ''}';
  }

  Widget _action(
    BuildContext context,
    WidgetRef ref,
    ContentDb db,
    PlayerProfile p,
    TournamentState? st,
    Bracket bracket,
  ) {
    if (!db.featureOn('tournament'))
      return const NeonButton(label: 'البطولات متوقفة مؤقتاً', onPressed: null);
    if (st != null && !st.alive) {
      return NeonButton(
        label: st.won
            ? 'فزت بالبطولة — عُد في الدورة القادمة'
            : 'انتهت مشاركتك — عُد في الدورة القادمة',
        onPressed: null,
      );
    }
    return NeonButton(
      label: st == null
          ? 'ادخل البطولة'
          : 'ابدأ المباراة (جولة ${st.round + 1})',
      icon: Icons.sports_score_rounded,
      onPressed: () => _play(context, ref, st, bracket),
    );
  }

  void _play(
    BuildContext context,
    WidgetRef ref,
    TournamentState? st,
    Bracket bracket,
  ) {
    final c = ModeFlow.container(context);
    final db = c.read(contentProvider);
    var state = st;
    if (state == null) {
      final base = ModeFlow.builder(c).targetWpm();
      c
          .read(profileProvider.notifier)
          .update((p) => state = TournamentLogic.enter(p, def, base));
    }
    final s = state!;
    final pr = c.read(profileProvider);
    final br = TournamentLogic.bracketFor(db, pr, def, s);
    final match = br.matchOf(s.round, br.player);
    if (match == null) return;
    final opp = match.a.isPlayer ? match.b : match.a;
    final title = '${loc(def.name)} — جولة ${s.round + 1}';
    ModeFlow.race(
      context,
      again: false,
      config: () => ModeFlow.builder(c).tournamentMatch(
        title: title,
        opponent: TournamentLogic.specFor(db, opp, Random()),
        def: def,
      ),
      finish: (ctx, result, outcome, _) {
        Map<String, dynamic> earned = {};
        c.read(profileProvider.notifier).update((p) {
          final cur = TournamentLogic.stateOf(p, def) ?? s;
          if (result.suspicious) return;
          earned = TournamentLogic.recordResult(p, def, cur, result.won);
        });
        final now = TournamentLogic.stateOf(c.read(profileProvider), def);
        return _MatchResult(
          result: result,
          outcome: outcome,
          earned: earned,
          state: now,
          def: def,
        );
      },
    );
  }
}

class _MatchResult extends StatelessWidget {
  const _MatchResult({
    required this.result,
    required this.outcome,
    required this.earned,
    required this.state,
    required this.def,
  });
  final RaceResult result;
  final dynamic outcome;
  final Map<String, dynamic> earned;
  final TournamentState? state;
  final TournamentDef def;
  @override
  Widget build(BuildContext context) {
    final won = result.won && !result.suspicious;
    final champion = state?.won == true;
    return ResultScreen(
      result: result,
      outcome: outcome,
      primaryLabel: 'عرض الشجرة',
      onPrimary: () => Navigator.of(context).pop(),
      extra: [
        Panel(
          border: won ? C.gold : C.red,
          child: Column(
            children: [
              Text(
                champion
                    ? '🏆 أنت بطل ${loc(def.name)}!'
                    : (won ? '✅ تأهلت للجولة التالية' : '❌ خرجت من البطولة'),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: won ? C.gold : C.red,
                ),
              ),
              if (result.suspicious)
                const Text(
                  'لم تُحتسب النتيجة بسبب إدخال غير طبيعي.',
                  style: TextStyle(color: C.red),
                ),
            ],
          ),
        ),
        if (earned.isNotEmpty) ...[
          const SizedBox(height: 10),
          ModeFlow.rewardPanel(
            'جوائز البطولة',
            coins: (earned['coins'] as num?)?.toInt() ?? 0,
            xp: (earned['xp'] as num?)?.toInt() ?? 0,
            gems: (earned['gems'] as num?)?.toInt() ?? 0,
            lines: [
              if (earned['title'] != null) '🏷️ لقب جديد',
              if (earned['skin'] != null) '🎨 عنصر تجميلي جديد',
            ],
          ),
        ],
      ],
    );
  }
}

class _RoundColumn extends StatelessWidget {
  const _RoundColumn({
    required this.round,
    required this.bracket,
    required this.def,
    required this.current,
  });
  final int round;
  final Bracket bracket;
  final TournamentDef def;
  final bool current;
  @override
  Widget build(BuildContext context) {
    final matches = round < bracket.rounds.length
        ? bracket.rounds[round]
        : <Match>[];
    final count = def.size >> (round + 1);
    final name = round == def.rounds - 1
        ? 'النهائي'
        : (round == def.rounds - 2 ? 'نصف النهائي' : 'الجولة ${round + 1}');
    return SizedBox(
      width: 168,
      child: Column(
        children: [
          Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: current ? C.cyan : C.textDim,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < count; i++)
                  i < matches.length
                      ? _MatchCard(m: matches[i])
                      : const _MatchCard(m: null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.m});
  final Match? m;
  @override
  Widget build(BuildContext context) {
    Widget line(BracketEntry? e) {
      if (e == null)
        return const Padding(
          padding: EdgeInsets.all(4),
          child: Text('—', style: TextStyle(color: C.textDim)),
        );
      final win = m?.winner?.id == e.id, lose = m?.winner != null && !win;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: e.isPlayer
              ? C.cyan.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(flagEmoji(e.cc)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                e.isPlayer ? '${e.name} ★' : e.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: win || e.isPlayer
                      ? FontWeight.w900
                      : FontWeight.w500,
                  color: lose ? Colors.white38 : Colors.white,
                ),
              ),
            ),
            if (win) const Icon(Icons.check_circle, size: 14, color: C.green),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          line(m?.a),
          const Divider(height: 1, color: Colors.white12),
          line(m?.b),
        ],
      ),
    );
  }
}

class _Champion extends StatelessWidget {
  const _Champion({required this.bracket, required this.st});
  final Bracket bracket;
  final TournamentState? st;
  @override
  Widget build(BuildContext context) {
    final last = bracket.rounds.isEmpty ? null : bracket.rounds.last;
    final champ =
        (last != null &&
            last.length == 1 &&
            bracket.rounds.length == bracket.def.rounds)
        ? last.first.winner
        : null;
    return SizedBox(
      width: 110,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏆', style: TextStyle(fontSize: 44)),
          Text(
            champ == null ? 'البطل' : champ.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
