import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

/// Small explanatory bottom sheet shown before survival / combat etc.
Future<void> showModeIntro(BuildContext context, {required IconData icon, required String title, required List<String> bullets, String? bestLine, required VoidCallback onStart, String startLabel = 'ابدأ'}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: C.cyan, size: 24), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 10),
          for (final b in bullets) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('• ', style: TextStyle(color: C.cyan)), Expanded(child: Text(b))])),
          if (bestLine != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(bestLine, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800))),
          const SizedBox(height: 14),
          NeonButton(
            label: startLabel,
            icon: Icons.flag_rounded,
            onPressed: () {
              Navigator.of(context).pop();
              onStart();
            },
          ),
        ]),
      ),
    ),
  );
}
