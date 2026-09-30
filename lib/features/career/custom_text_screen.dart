import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../race/engine/metrics.dart';
import 'mode_flow.dart';

/// Turns pasted text into something typeable: straight quotes, single spaces, no control characters.
String sanitizeCustomText(String raw, {String lang = 'en'}) {
  var t = raw
      .replaceAll(RegExp(r'[\u2018\u2019\u201B]'), "'")
      .replaceAll(RegExp(r'[\u201C\u201D\u201E]'), '"')
      .replaceAll(RegExp(r'[\u2013\u2014\u2212]'), '-')
      .replaceAll('\u2026', '...')
      .replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ')
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2060\uFEFF]'), '');
  if (lang != 'fr' && lang != 'es') {
    t = t.split('').map(foldChar).join();
    t = t.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }
  return t.replaceAll(RegExp(r' {2,}'), ' ').trim();
}

class CustomTextScreen extends ConsumerStatefulWidget {
  const CustomTextScreen({super.key});
  @override
  ConsumerState<CustomTextScreen> createState() => _CustomTextScreenState();
}

class _CustomTextScreenState extends ConsumerState<CustomTextScreen> {
  final _c = TextEditingController();
  String? _error;
  static const minLen = 20, maxLen = 700;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(settingsProvider).textLang;
    final clean = sanitizeCustomText(_c.text, lang: lang);
    return Scaffold(
      appBar: AppBar(title: const Text('نص مخصص')),
      body: GradientBg(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الصق أو اكتب أي نص تريد التدرّب عليه (من $minLen إلى $maxLen حرفاً). لا تُمنح عملات على النصوص المخصصة.', style: TextStyle(color: C.textDim, fontSize: 13)),
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  controller: _c,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    hintText: 'Paste your text here...',
                    filled: true,
                    fillColor: C.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text('${clean.length} حرف', style: TextStyle(color: clean.length < minLen || clean.length > maxLen ? C.red : C.green, fontSize: 12)),
              const SizedBox(height: 8),
              NeonButton(label: 'ابدأ التدرّب', icon: Icons.keyboard_rounded, onPressed: _start),
            ]),
          ),
        ),
      ),
    );
  }

  void _start() {
    final lang = ref.read(settingsProvider).textLang;
    final text = sanitizeCustomText(_c.text, lang: lang);
    if (text.length < minLen) {
      setState(() => _error = 'النص قصير جداً (الحد الأدنى $minLen حرفاً)');
      return;
    }
    if (text.length > maxLen) {
      setState(() => _error = 'النص طويل جداً (الحد الأقصى $maxLen حرف)');
      return;
    }
    final c = ModeFlow.container(context);
    ModeFlow.race(context, config: () => ModeFlow.builder(c).custom(text, lang: lang));
  }
}
