import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/countries.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/remote/firebase_boot.dart';
import '../career/rank.dart';
import 'leaderboard_service.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  Board board = Board.global;
  Future<List<LbEntry>>? _f;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final p = ref.read(profileProvider);
    if (!FirebaseBoot.available) {
      _f = Future.value(const []);
      return;
    }
    if (board == Board.country && p.country.isEmpty) {
      _f = Future.value(const []);
      return;
    }
    _f = ref.read(leaderboardProvider).top(LeaderboardService.boardId(board, cc: p.country));
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(profileProvider);
    final db = ref.watch(contentProvider);
    const names = {Board.global: 'عالمي', Board.country: 'بلدي', Board.weekly: 'أسبوعي', Board.monthly: 'شهري'};
    return Scaffold(
      appBar: AppBar(title: const Text('المتصدرون')),
      body: GradientBg(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<Board>(
              showSelectedIcon: false,
              segments: [for (final b in Board.values) ButtonSegment(value: b, label: Text(names[b]!))],
              selected: {board},
              onSelectionChanged: (s) => setState(() {
                board = s.first;
                _load();
              }),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('تُحتسب فقط نتائج اللعب النقي (تحدي اليوم/الأسبوع والاختبار الرسمي) بعد التحقق من الخادم. النتائج المشبوهة تُستبعد.', style: TextStyle(color: C.textDim, fontSize: 11))),
          if (!FirebaseBoot.available)
            const Expanded(child: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('المتصدرون يحتاجون اتصالاً بحساب (Firebase). سجّل الدخول بجوجل وتأكد من الإنترنت.', textAlign: TextAlign.center, style: TextStyle(color: C.textDim)))))
          else
            Expanded(
              child: FutureBuilder<List<LbEntry>>(
                future: _f,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (snap.hasError) return const Center(child: Text('تعذّر تحميل اللوحة. تحقق من الاتصال.', style: TextStyle(color: C.textDim)));
                  final list = snap.data ?? const [];
                  if (list.isEmpty) return Center(child: Text(board == Board.country && p.country.isEmpty ? 'اختر بلدك من الإعدادات لعرض لوحة بلدك' : 'لا توجد نتائج بعد — كن الأول! 🏁', style: const TextStyle(color: C.textDim)));
                  final uid = ref.read(cloudSyncProvider).uid;
                  return RefreshIndicator(
                    onRefresh: () async => setState(_load),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final me = e.uid == uid;
                        final tier = Ranks.tiers(db).isEmpty ? null : Ranks.tiers(db)[e.tier.clamp(0, Ranks.tiers(db).length - 1)];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: me ? C.cyan.withValues(alpha: 0.15) : C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: me ? C.cyan : Colors.white10)),
                          child: Row(children: [
                            SizedBox(width: 34, child: Text(e.rank <= 3 ? const ['🥇', '🥈', '🥉'][e.rank - 1] : '${e.rank}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: e.rank <= 3 ? 20 : 14))),
                            Text(avatars[e.avatar % avatars.length], style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${e.cc.isEmpty ? '' : '${flagEmoji(e.cc)} '}${e.name}', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: me ? FontWeight.w900 : FontWeight.w700)),
                              if (e.title.isNotEmpty || tier != null) Text('${tier?.icon ?? ''} ${loc(db.titles[e.title] ?? '')}', style: const TextStyle(color: C.textDim, fontSize: 11)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('${e.wpm}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: C.cyan, fontFamily: 'FiraMono')),
                              Text('WPM • ${e.acc}%', style: const TextStyle(color: C.textDim, fontSize: 10)),
                            ]),
                          ]),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}
