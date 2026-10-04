import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../race/engine/race_models.dart';
import 'mode_flow.dart';

/// A shareable challenge: "beat this score on this text". The opponent is an AI ghost that replays the recorded WPM.
class ChallengeLink {
  final String textId, name, cc, lang;
  final int wpm, acc;
  const ChallengeLink({required this.textId, required this.wpm, required this.name, this.cc = '', this.lang = 'en', this.acc = 0});

  static int _check(String t, int w, String n) => stableHash('$t|$w|$n|trl1') % 100000;

  Map<String, String> get params => {
        't': textId,
        'w': '$wpm',
        'a': '$acc',
        'n': name.length > 14 ? name.substring(0, 14) : name,
        'c': cc,
        'l': lang,
        'k': '${_check(textId, wpm, name.length > 14 ? name.substring(0, 14) : name)}',
      };

  Uri get webUri => Uri.parse(AppConfig.challengeLandingUrl).replace(queryParameters: params);
  Uri get appUri => Uri(scheme: AppConfig.deepLinkScheme, host: 'challenge', queryParameters: params);

  static ChallengeLink? parse(Uri uri) {
    final q = uri.queryParameters;
    final t = q['t'], w = int.tryParse(q['w'] ?? ''), n = q['n'] ?? '';
    if (t == null || t.isEmpty || w == null) return null;
    if (w < 5 || w > AppConfig.maxHumanWpm) return null;
    final k = int.tryParse(q['k'] ?? '');
    if (k == null || k != _check(t, w, n)) return null;
    final cleanName = n.replaceAll(RegExp(r'[<>\n\r]'), '').trim();
    return ChallengeLink(textId: t, wpm: w, name: cleanName.isEmpty ? 'صديق' : cleanName, cc: (q['c'] ?? '').toUpperCase(), lang: q['l'] ?? 'en', acc: int.tryParse(q['a'] ?? '') ?? 0);
  }

  static Future<void> share(BuildContext context, RaceResult r, String playerName, String country) async {
    final link = ChallengeLink(textId: r.config.text.id, wpm: r.wpm.round(), name: playerName, cc: country, lang: r.config.text.lang, acc: r.accuracy.round());
    final text = 'تحدّيتك في Type Racer Legends! سرعتي ${link.wpm} WPM — هل تتفوق عليّ؟\n${link.webUri}';
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: 'تحدٍّ في Type Racer Legends'));
      ProviderScope.containerOf(context, listen: false).read(profileProvider.notifier).update((p) => p.addCounter('challenges_sent', 1));
    } catch (e) {
      debugPrint('share failed: $e');
      if (context.mounted) toast(context, 'تعذّرت المشاركة');
    }
  }
}

/// Listens for incoming deep links (cold start + running app) and opens the challenge sheet.
class ChallengeLinkListener {
  ChallengeLinkListener(this.container);
  final ProviderContainer container;
  StreamSubscription<Uri>? _sub;
  String? _last;

  Future<void> start() async {
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) _handle(initial);
      _sub = links.uriLinkStream.listen(_handle, onError: (Object e) => debugPrint('link error: $e'));
    } catch (e) {
      debugPrint('app_links unavailable: $e');
    }
  }

  void _handle(Uri uri) {
    if (uri.toString() == _last) return;
    _last = uri.toString();
    final link = ChallengeLink.parse(uri);
    if (link == null) return;
    if (!container.read(contentProvider).featureOn('link_challenge')) return;
    // wait for the navigator to exist (cold start)
    Timer.periodic(const Duration(milliseconds: 400), (t) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        t.cancel();
        showChallengeSheet(ctx, link);
      } else if (t.tick > 30) {
        t.cancel();
      }
    });
  }

  void dispose() => _sub?.cancel();
}

void showChallengeSheet(BuildContext context, ChallengeLink link) {
  showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _ChallengeSheet(link: link));
}

class _ChallengeSheet extends ConsumerWidget {
  const _ChallengeSheet({required this.link});
  final ChallengeLink link;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(contentProvider);
    final text = db.textById(link.textId);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('تحدٍّ وصلك', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Panel(
            child: Column(children: [
              Text('${flagEmoji(link.cc)} ${link.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text('${link.wpm} WPM', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: C.gold)),
              const Text('سرعة مسجَّلة. ستتسابق ضد شبح ذكاء اصطناعي يعيد هذه السرعة.', textAlign: TextAlign.center, style: TextStyle(color: C.textDim, fontSize: 12)),
              if (text == null) const Padding(padding: EdgeInsets.only(top: 6), child: Text('النص غير متوفر لديك — سيُستخدم نص مشابه.', style: TextStyle(fontSize: 12, color: C.gold))),
            ]),
          ),
          const SizedBox(height: 14),
          NeonButton(
            label: 'اقبل التحدي',
            icon: Icons.flag_rounded,
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              ChallengeFlow.accept(nav.context, link);
            },
          ),
        ]),
      ),
    );
  }
}

class ChallengeFlow {
  static void accept(BuildContext context, ChallengeLink link) {
    final c = ModeFlow.container(context);
    ModeFlow.race(
      context,
      config: () {
        final b = ModeFlow.builder(c);
        final t = c.read(contentProvider).textById(link.textId) ?? b.pickText();
        final ghost = GhostSpec(name: link.name, wpm: link.wpm.toDouble());
        return RaceConfig(modeId: 'challenge', title: 'تحدٍّ من ${link.name}', text: t, biomeId: b.randomBiome().id, ghosts: [ghost], rules: RaceRules.solo, meta: {'challenge': link.textId});
      },
    );
  }
}

/// Lets the player share a challenge from any saved best run, or paste a received link.
class ChallengeHubScreen extends ConsumerStatefulWidget {
  const ChallengeHubScreen({super.key});
  @override
  ConsumerState<ChallengeHubScreen> createState() => _ChallengeHubState();
}

class _ChallengeHubState extends ConsumerState<ChallengeHubScreen> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final ghosts = ref.watch(storeProvider).allGhosts();
    return Scaffold(
      appBar: AppBar(title: const Text('تحدٍّ بالرابط')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Panel(child: Text('شارك رابطاً يحمل نصاً وسرعتك. من يفتحه يتسابق ضد شبح ذكاء اصطناعي يعيد سرعتك المسجّلة — لا سباقات مباشرة مع لاعبين.', style: TextStyle(color: C.textDim, fontSize: 13))),
          const SizedBox(height: 14),
          const Text('شارك إحدى نتائجك', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (ghosts.isEmpty) const Panel(child: Text('أنهِ سباقاً أولاً ثم عُد هنا لمشاركة نتيجتك.', style: TextStyle(color: C.textDim))),
          for (final g in ghosts.take(12))
            Builder(builder: (_) {
              final t = db.textById(g.key.split('|').first);
              if (t == null) return const SizedBox.shrink();
              final w = (g.value['wpm'] as num).round();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  child: Row(children: [
                    Expanded(child: Text(t.text, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13))),
                    const SizedBox(width: 8),
                    Text('$w WPM', style: const TextStyle(fontWeight: FontWeight.w900, color: C.cyan)),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: C.magenta),
                      onPressed: () async {
                        final link = ChallengeLink(textId: t.id, wpm: w, name: p.name, cc: p.country, lang: t.lang);
                        try {
                          await SharePlus.instance.share(ShareParams(text: 'تحدّيتك في Type Racer Legends! سرعتي $w WPM — هل تتفوق عليّ؟\n${link.webUri}'));
                          ref.read(profileProvider.notifier).update((pp) => pp.addCounter('challenges_sent', 1));
                        } catch (_) {
                          if (context.mounted) toast(context, 'تعذّرت المشاركة');
                        }
                      },
                    ),
                  ]),
                ),
              );
            }),
          const SizedBox(height: 16),
          const Text('لديك رابط تحدٍّ؟', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(controller: _c, textDirection: TextDirection.ltr, decoration: InputDecoration(hintText: 'https://...', filled: true, fillColor: C.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
          const SizedBox(height: 8),
          NeonButton(
            label: 'افتح التحدي',
            icon: Icons.link_rounded,
            filled: false,
            onPressed: () {
              final uri = Uri.tryParse(_c.text.trim());
              final link = uri == null ? null : ChallengeLink.parse(uri);
              if (link == null) {
                toast(context, 'الرابط غير صالح');
                return;
              }
              showChallengeSheet(context, link);
            },
          ),
        ]),
      ),
    );
  }
}
