import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'race_builder.dart';
import 'ui/race_screen.dart';

/// Bottom sheet that configures and launches a quick race against 3–7 AI opponents.
class QuickRaceSheet extends ConsumerStatefulWidget {
  const QuickRaceSheet({super.key});
  @override
  ConsumerState<QuickRaceSheet> createState() => _QuickRaceSheetState();
}

class _QuickRaceSheetState extends ConsumerState<QuickRaceSheet> {
  double count = 4;
  LengthPref len = LengthPref.medium;
  bool ranked = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 14),
        const Text('سباق سريع', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const Text('تتسابق ضد منافسين بالذكاء الاصطناعي بحسب مستواك.', style: TextStyle(color: C.textDim, fontSize: 12)),
        const SizedBox(height: 14),
        Text('عدد المنافسين: ${count.round()}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Slider(value: count, min: 3, max: 7, divisions: 4, label: '${count.round()}', onChanged: (v) => setState(() => count = v)),
        const Text('طول النص', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SegmentedButton<LengthPref>(
          segments: const [
            ButtonSegment(value: LengthPref.short, label: Text('قصير')),
            ButtonSegment(value: LengthPref.medium, label: Text('متوسط')),
            ButtonSegment(value: LengthPref.long, label: Text('طويل')),
          ],
          selected: {len},
          onSelectionChanged: (s) => setState(() => len = s.first),
        ),
        const SizedBox(height: 6),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: ranked, onChanged: (v) => setState(() => ranked = v), title: const Text('سباق تصنيفي'), subtitle: const Text('يؤثر على نقاط التصنيف (من برونزي إلى أسطورة)', style: TextStyle(fontSize: 12))),
        const SizedBox(height: 8),
        NeonButton(label: 'ابدأ', icon: Icons.flag_rounded, onPressed: _go),
      ]),
    );
  }

  void _go() {
    final nav = Navigator.of(context);
    RaceBuilder mk() => RaceBuilder(ref.read(contentProvider), ref.read(profileProvider), ref.read(settingsProvider));
    final n = count.round();
    final l = len;
    final r = ranked;
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => RaceScreen(config: mk().quick(opponentsCount: n, len: l, ranked: r), rebuild: () => mk().quick(opponentsCount: n, len: l, ranked: r))));
  }
}
