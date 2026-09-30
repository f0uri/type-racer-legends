import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../race/engine/race_models.dart';
import 'mode_flow.dart';

/// Ghost racing: beat your own best run on a text, plus fixed-speed AI ghosts.
class GhostScreen extends ConsumerWidget {
  const GhostScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final store = ref.watch(storeProvider);
    ref.watch(profileProvider); // rebuild after races
    final ghosts = store.allGhosts();
    return Scaffold(
      appBar: AppBar(title: const Text('سباق الأشباح')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Panel(child: Text('اركض ضد شبحك الشخصي (أفضل أداء لك على النص) إلى جانب أشباح ذكاء اصطناعي بسرعات ثابتة. كل أفضل نتيجة جديدة تُحفظ كشبح.', style: TextStyle(color: C.textDim, fontSize: 13))),
          const SizedBox(height: 12),
          NeonButton(label: 'نص جديد ضد أشباح AI', icon: Icons.shuffle_rounded, onPressed: () => _newText(context)),
          const SizedBox(height: 16),
          Text('أشباحك المحفوظة (${ghosts.length})', style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (ghosts.isEmpty) const Panel(child: Text('لا توجد أشباح بعد. أنهِ سباقاً (30 حرفاً أو أكثر) لحفظ أول شبح.', style: TextStyle(color: C.textDim))),
          for (final g in ghosts.take(40))
            Builder(builder: (_) {
              final tid = g.key.split('|').first;
              final t = db.textById(tid);
              if (t == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  onTap: () => _race(context, tid, g.value),
                  child: Row(children: [
                    const Text('👻', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.text, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13)),
                      Text('${t.len} حرف', style: const TextStyle(color: C.textDim, fontSize: 11)),
                    ])),
                    Text('${(g.value['wpm'] as num).round()}\nWPM', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, color: C.cyan, fontSize: 13)),
                  ]),
                ),
              );
            }),
        ]),
      ),
    );
  }

  void _newText(BuildContext context) {
    final c = ModeFlow.container(context);
    ModeFlow.race(context, config: () {
      final b = ModeFlow.builder(c);
      final t = b.pickText();
      return b.ghostRace(text: t, personal: b.personalGhost(c.read(storeProvider).ghost('${t.id}|${t.lang}')));
    });
  }

  void _race(BuildContext context, String textId, Map<String, dynamic> saved) {
    final c = ModeFlow.container(context);
    ModeFlow.race(context, config: () {
      final b = ModeFlow.builder(c);
      final t = c.read(contentProvider).textById(textId)!;
      final fresh = c.read(storeProvider).ghost('${t.id}|${t.lang}') ?? saved;
      return b.ghostRace(text: t, personal: b.personalGhost(fresh));
    });
  }
}

GhostSpec? ghostFromSaved(Map<String, dynamic>? saved) => saved == null ? null : GhostSpec(name: '👻 رقمك', wpm: (saved['wpm'] as num).toDouble(), personal: true);
