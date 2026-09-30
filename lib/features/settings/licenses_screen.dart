import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'legal_texts.dart';

/// Licences for fonts, audio (generated in code) and the open-source packages.
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  static const fonts = {
    'Tajawal': 'assets/fonts/OFL-tajawal.txt',
    'Fira Mono': 'assets/fonts/OFL-firamono.txt',
    'OpenDyslexic': 'assets/fonts/OFL-opendyslexic.txt',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('التراخيص والمصادر')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(child: Text(licensesAr, style: const TextStyle(height: 1.6))),
          const SizedBox(height: 12),
          const Text('تراخيص الخطوط (SIL OFL 1.1)', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          for (final e in fonts.entries)
            Panel(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                title: Text(e.key),
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  FutureBuilder<String>(
                    future: rootBundle.loadString(e.value),
                    builder: (_, snap) => Padding(
                      padding: const EdgeInsets.all(12),
                      child: Directionality(textDirection: TextDirection.ltr, child: Text(snap.data ?? '...', style: const TextStyle(fontSize: 11, color: C.textDim))),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showLicensePage(context: context, applicationName: 'Type Racer Legends'),
            icon: const Icon(Icons.description_outlined),
            label: const Text('تراخيص الحزم البرمجية'),
          ),
        ]),
      ),
    );
  }
}
