import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/countries.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final li = ref.watch(levelInfoProvider);
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                CircleAvatar(backgroundColor: C.surface2, child: Text(avatars[p.avatar % avatars.length], style: const TextStyle(fontSize: 22))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('المستوى ${li.level}', style: const TextStyle(color: C.textDim, fontSize: 12)),
                  ProgressBar(value: li.progress, height: 6),
                ])),
                const SizedBox(width: 10),
                CurrencyChip(icon: Icons.monetization_on, color: C.gold, value: fmtInt(p.coins)),
                const SizedBox(width: 6),
                CurrencyChip(icon: Icons.diamond, color: C.cyan, value: fmtInt(p.gems)),
                IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
              ]),
              const Spacer(),
              const Text('جاهز للانطلاق', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const Spacer(),
            ]),
          ),
        ),
      ),
    );
  }
}
