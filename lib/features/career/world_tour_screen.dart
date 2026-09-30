import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';
import '../garage/look.dart';
import '../race/engine/race_models.dart';
import '../race/ui/result_screen.dart';
import 'mode_flow.dart';

class WorldTourLogic {
  static bool unlocked(PlayerProfile p, ContentDb db, City c) {
    if (c.idx == 0) return true;
    final prev = db.cities.where((x) => x.idx == c.idx - 1).firstOrNull;
    return prev == null || (p.m('world')[prev.id] as num? ?? 0) > 0;
  }

  static bool cleared(PlayerProfile p, City c) => ((p.m('world')[c.id] as num?) ?? 0) > 0;

  /// A stop is cleared with at least [City.minWpm] and 90% accuracy (finishing position does not matter).
  static bool passes(RaceResult r, City c) => !r.suspicious && !r.timeUp && r.wpm >= c.minWpm && r.accuracy >= 90;

  static Map<String, int> apply(PlayerProfile p, City c, RaceResult r) {
    final out = {'coins': 0, 'xp': 0, 'gems': 0};
    if (!passes(r, c)) return out;
    final first = !cleared(p, c);
    p.m('world')[c.id] = 1;
    if (first) {
      out['coins'] = (c.reward['coins'] as num?)?.toInt() ?? 0;
      out['xp'] = (c.reward['xp'] as num?)?.toInt() ?? 0;
      out['gems'] = (c.reward['gems'] as num?)?.toInt() ?? 0;
      p.addCoins(out['coins']!);
      p.addXp(out['xp']!);
      p.addGems(out['gems']!);
    }
    return out;
  }
}

class WorldTourScreen extends ConsumerWidget {
  const WorldTourScreen({super.key});
  static const _icons = {'lighthouse': '🗼', 'eiffel': '🗼', 'bigben': '🕰️', 'colosseum': '🏛️', 'pyramids': '🔺', 'burj': '🏙️', 'gateway': '⛩️', 'pagoda': '🏯', 'tokyotower': '🗼', 'opera': '🎭', 'christ': '⛪', 'liberty': '🗽'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final cities = [...db.cities]..sort((a, b) => a.idx.compareTo(b.idx));
    final done = cities.where((c) => WorldTourLogic.cleared(p, c)).length;
    final km = cities.where((c) => WorldTourLogic.cleared(p, c)).fold<int>(0, (a, c) => a + c.km);
    return Scaffold(
      appBar: AppBar(title: const Text('جولة حول العالم')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Column(children: [Text('$done/${cities.length}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.cyan)), const Text('محطات', style: TextStyle(color: C.textDim, fontSize: 12))]),
              Column(children: [Text(fmtInt(km), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.gold)), const Text('كم قطعت', style: TextStyle(color: C.textDim, fontSize: 12))]),
            ]),
          ),
          const SizedBox(height: 6),
          const Text('في كل مدينة نص خاص ومنافسون بالذكاء الاصطناعي. اجتز المحطة بالوصول إلى السرعة المطلوبة ودقة 90%.', style: TextStyle(color: C.textDim, fontSize: 12)),
          const SizedBox(height: 10),
          for (final c in cities) _stop(context, ref, db, p, c),
        ]),
      ),
    );
  }

  Widget _stop(BuildContext context, WidgetRef ref, ContentDb db, PlayerProfile p, City c) {
    final open = WorldTourLogic.unlocked(p, db, c);
    final cleared = WorldTourLogic.cleared(p, c);
    final accent = c.colors.length > 1 ? hexColor(c.colors[1]) : C.cyan;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Panel(
        border: cleared ? C.green : (open ? accent : Colors.white10),
        onTap: open
            ? () => showModalBottomSheet<void>(context: context, builder: (_) => _StopSheet(city: c))
            : () => toast(context, 'اجتز المحطة السابقة أولاً'),
        child: Row(children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.2), border: Border.all(color: accent)),
            alignment: Alignment.center,
            child: Text(open ? (_icons[c.landmark] ?? '📍') : '🔒', style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${flagEmoji(c.cc)} ${loc(c.name)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text('المطلوب: ${c.minWpm} WPM  •  ${fmtInt(c.km)} كم', style: const TextStyle(color: C.textDim, fontSize: 12)),
          ])),
          if (cleared) const Text('✅ ختم', style: TextStyle(color: C.green, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }
}

class _StopSheet extends ConsumerWidget {
  const _StopSheet({required this.city});
  final City city;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cleared = WorldTourLogic.cleared(ref.watch(profileProvider), city);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${flagEmoji(city.cc)} ${loc(city.name)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('• السرعة المطلوبة: ${city.minWpm} WPM بدقة 90% أو أكثر\n• ${city.opp} منافسين (ذكاء اصطناعي)\n• ${cleared ? 'سبق أن اجتزت هذه المحطة (لا مكافأة إضافية)' : 'مكافأة أول ختم: 🪙 ${city.reward['coins'] ?? 0}  ⚡ ${city.reward['xp'] ?? 0}${((city.reward['gems'] as num?) ?? 0) > 0 ? '  💎 ${city.reward['gems']}' : ''}'}', style: const TextStyle(height: 1.6)),
          const SizedBox(height: 14),
          NeonButton(
            label: 'سافر إلى ${loc(city.name)}',
            icon: Icons.flight_takeoff_rounded,
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              _go(nav.context, city);
            },
          ),
        ]),
      ),
    );
  }

  void _go(BuildContext context, City c) {
    final cont = ModeFlow.container(context);
    ModeFlow.race(
      context,
      config: () => ModeFlow.builder(cont).worldStop(c),
      finish: (ctx, result, outcome, rebuild) {
        late Map<String, int> got;
        cont.read(profileProvider.notifier).update((p) => got = WorldTourLogic.apply(p, c, result));
        final ok = WorldTourLogic.passes(result, c);
        return ResultScreen(
          result: result,
          outcome: outcome,
          rebuild: rebuild,
          extra: [
            Panel(
              border: ok ? C.green : C.red,
              child: Column(children: [
                Text(ok ? '✅ ختم ${loc(c.name)}' : 'لم تصل إلى ${c.minWpm} WPM بدقة 90%', style: TextStyle(fontWeight: FontWeight.w900, color: ok ? C.green : C.red, fontSize: 16)),
                Text('سرعتك ${result.wpm.round()} WPM • دقتك ${result.accuracy.toStringAsFixed(0)}%', style: const TextStyle(color: C.textDim)),
              ]),
            ),
            if (got['coins']! + got['xp']! + got['gems']! > 0) ...[const SizedBox(height: 10), ModeFlow.rewardPanel('مكافأة ختم جديد', coins: got['coins']!, xp: got['xp']!, gems: got['gems']!)],
          ],
        );
      },
    );
  }
}
