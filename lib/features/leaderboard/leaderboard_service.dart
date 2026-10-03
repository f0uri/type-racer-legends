import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/util/dates.dart';
import '../../data/remote/firebase_boot.dart';
import '../race/engine/race_models.dart';

class LbEntry {
  final String uid, name, cc, title;
  final int wpm, acc, avatar, tier;
  final int rank;
  const LbEntry({required this.uid, required this.name, required this.cc, required this.title, required this.wpm, required this.acc, required this.avatar, required this.tier, required this.rank});
}

enum Board { global, country, weekly, monthly }

/// Score submission payload (validated again by the `submitScore` Cloud Function).
class ScorePayload {
  final double wpm, acc;
  final int chars, timeMs;
  /// Active typing span (first key last key). The server validates WPM against this value:
  /// [timeMs] is the whole race from GO and contains reaction/reading time, so it can be much longer.
  final int typingMs;
  final String textId, mode;
  final List<int> intervals;
  const ScorePayload({required this.wpm, required this.acc, required this.chars, required this.timeMs, required this.textId, required this.mode, required this.intervals, this.typingMs = 0});

  Map<String, dynamic> toJson() => {'wpm': double.parse(wpm.toStringAsFixed(1)), 'acc': double.parse(acc.toStringAsFixed(1)), 'chars': chars, 'timeMs': timeMs, 'typingMs': typingMs > 0 ? typingMs : timeMs, 'textId': textId, 'mode': mode, 'intervals': intervals, 'v': AppConfig.profileSchema};

  /// Which results may go to the leaderboards: pure-play modes only (no bonuses), never flagged as suspicious.
  static ScorePayload? fromResult(RaceResult r) {
    if (r.suspicious || !r.config.rules.pure || r.timeUp && r.config.timeLimitMs == null) return null;
    if (!const {'daily', 'weekly', 'official'}.contains(r.config.modeId)) return null;
    if (r.chars < 30 || r.accuracy < 80 || r.intervals.length < 20) return null;
    final iv = r.intervals.length > 400 ? r.intervals.sublist(0, 400) : r.intervals;
    return ScorePayload(wpm: r.wpm, acc: r.accuracy, chars: r.chars, timeMs: (r.time * 1000).round(), typingMs: r.typingMs, textId: r.config.text.id, mode: r.config.modeId, intervals: iv);
  }
}

class LeaderboardService {
  LeaderboardService(this.ref);
  final Ref ref;
  static const pendingKey = 'pendingScores';

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static String boardId(Board b, {String cc = '', DateTime? now}) {
    final n = now ?? DateTime.now();
    switch (b) {
      case Board.global:
        return 'global';
      case Board.country:
        return 'country_${cc.toUpperCase()}';
      case Board.weekly:
        return 'weekly_${weekKey(n)}';
      case Board.monthly:
        return 'monthly_${n.year}${n.month.toString().padLeft(2, '0')}';
    }
  }

  List<Map<String, dynamic>> get _pending {
    final raw = ref.read(storeProvider).meta.get(pendingKey) as String?;
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePending(List<Map<String, dynamic>> l) => ref.read(storeProvider).meta.put(pendingKey, jsonEncode(l.length > 20 ? l.sublist(l.length - 20) : l));

  int get pendingCount => _pending.length;

  /// Queues the score (works offline) and tries to send everything.
  Future<bool> submit(ScorePayload p) async {
    final q = _pending..add(p.toJson());
    await _savePending(q);
    return flush();
  }

  /// Sends queued scores; returns true when the queue is empty afterwards.
  Future<bool> flush() async {
    if (!FirebaseBoot.available || ref.read(cloudSyncProvider).uid == null) return _pending.isEmpty;
    final q = _pending;
    final left = <Map<String, dynamic>>[];
    for (final item in q) {
      try {
        final r = await ref.read(cloudSyncProvider).callFn<Map<dynamic, dynamic>>('submitScore', item);
        if (r != null && r['ok'] == false) debugPrint('score rejected: ${r['reason']}');
      } catch (e) {
        debugPrint('submitScore failed (kept for retry): $e');
        left.add(item);
      }
    }
    await _savePending(left);
    return left.isEmpty;
  }

  /// Top 50 of a board plus the player's own entry when outside the top.
  Future<List<LbEntry>> top(String board) async {
    final q = await _fs.collection('leaderboards').doc(board).collection('entries').orderBy('wpm', descending: true).limit(50).get();
    var rank = 0;
    return [
      for (final d in q.docs)
        LbEntry(
          uid: d.id,
          name: (d.data()['name'] as String?) ?? '—',
          cc: (d.data()['cc'] as String?) ?? '',
          title: (d.data()['title'] as String?) ?? '',
          wpm: (d.data()['wpm'] as num?)?.round() ?? 0,
          acc: (d.data()['acc'] as num?)?.round() ?? 0,
          avatar: (d.data()['avatar'] as num?)?.toInt() ?? 0,
          tier: (d.data()['tier'] as num?)?.toInt() ?? 0,
          rank: ++rank,
        ),
    ];
  }
}

final leaderboardProvider = Provider<LeaderboardService>((ref) => LeaderboardService(ref));

/// Submits a finished race when it qualifies (called from the result hook).
Future<void> maybeSubmitScore(ProviderContainer c, RaceResult r) async {
  final payload = ScorePayload.fromResult(r);
  if (payload == null) return;
  if (!c.read(contentProvider).featureOn('leaderboard')) return;
  try {
    await c.read(leaderboardProvider).submit(payload);
  } catch (e) {
    debugPrint('score queue failed: $e');
  }
}
