import 'dart:math';
import '../../core/util/dates.dart';
import '../../data/models/profile.dart';
import '../race/engine/race_models.dart';

class DayStat {
  final String day;
  final int races, chars, playMs;
  final double best, avg;
  const DayStat(this.day, this.races, this.chars, this.playMs, this.best, this.avg);
}

/// Per-day activity, weekly WPM goal and other player statistics.
class StatsLogic {
  static const maxDays = 120;

  /// Records a finished race in the per-day table: [races, chars, playMs, bestWpmX10, wpmSumX10].
  static void recordRace(PlayerProfile p, RaceResult r, {DateTime? now}) {
    if (r.suspicious || r.chars < 30) return;
    final days = p.m('sdays');
    final k = dayKey(now);
    final cur = ((days[k] as List?) ?? const [0, 0, 0, 0, 0]).map((e) => (e as num).toInt()).toList();
    while (cur.length < 5) {
      cur.add(0);
    }
    cur[0] += 1;
    cur[1] += r.chars;
    cur[2] += (r.time * 1000).round();
    cur[3] = max(cur[3], (r.wpm * 10).round());
    cur[4] += (r.wpm * 10).round();
    days[k] = cur;
    if (days.length > maxDays) {
      final keys = days.keys.toList()..sort();
      for (final old in keys.take(days.length - maxDays)) {
        days.remove(old);
      }
    }
    p.addCounter('acc_sum', (r.accuracy * 10).round());
    p.addCounter('acc_n', 1);
    p.addCounter('play_ms', (r.time * 1000).round());
  }

  static DayStat? day(PlayerProfile p, String key) {
    final v = p.m('sdays')[key];
    if (v is! List || v.length < 5) return null;
    final races = (v[0] as num).toInt();
    return DayStat(key, races, (v[1] as num).toInt(), (v[2] as num).toInt(), (v[3] as num) / 10, races == 0 ? 0 : (v[4] as num) / 10 / races);
  }

  /// Last [n] days (oldest first), empty days included.
  static List<DayStat> lastDays(PlayerProfile p, int n, {DateTime? now}) {
    final base = now ?? DateTime.now();
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final k = dayKey(DateTime(base.year, base.month, base.day).subtract(Duration(days: i)));
          return day(p, k) ?? DayStat(k, 0, 0, 0, 0, 0);
        }()
    ];
  }

  static double avgAccuracy(PlayerProfile p) {
    final n = p.counter('acc_n');
    return n == 0 ? 0 : p.counter('acc_sum') / 10 / n;
  }

  static Duration playTime(PlayerProfile p) => Duration(milliseconds: p.counter('play_ms'));

  /// WPM trend: average of the last 10 vs the 10 before.
  static double trend(PlayerProfile p) {
    final h = p.history;
    if (h.length < 6) return 0;
    final k = min(10, h.length ~/ 2);
    final last = h.sublist(h.length - k), prev = h.sublist(h.length - 2 * k, h.length - k);
    double avg(List<double> l) => l.reduce((a, b) => a + b) / l.length;
    return avg(last) - avg(prev);
  }
}

/// Personal weekly WPM goal.
class Goal {
  static Map<String, dynamic>? current(PlayerProfile p, [DateTime? now]) {
    final g = p.m('goal');
    return g['key'] == weekKey(now) && g['target'] is num ? g : null;
  }

  /// A realistic goal: slightly above the recent average.
  static int suggest(PlayerProfile p) {
    final base = p.history.isEmpty ? (p.m('placement')['wpm'] as num?)?.toDouble() ?? 20 : max(p.avgWpm, p.best('best_wpm') * 0.85);
    return max(10, (base * 1.08 + 1).round());
  }

  static void set(PlayerProfile p, int target, [DateTime? now]) {
    final g = p.m('goal');
    final k = weekKey(now);
    final old = g['key'] == k ? (g['claimed'] ?? <String, dynamic>{}) : <String, dynamic>{};
    g
      ..clear()
      ..['key'] = k
      ..['target'] = target.clamp(5, 240)
      ..['claimed'] = old
      ..['best'] = 0.0;
  }

  /// Best WPM reached in the current week (from the per-day table).
  static double weekBest(PlayerProfile p, [DateTime? now]) {
    final base = now ?? DateTime.now();
    final monday = DateTime(base.year, base.month, base.day).subtract(Duration(days: base.weekday - 1));
    var best = 0.0;
    for (var i = 0; i < 7; i++) {
      final d = StatsLogic.day(p, dayKey(monday.add(Duration(days: i))));
      if (d != null && d.best > best) best = d.best;
    }
    return best;
  }

  static double progress(PlayerProfile p, [DateTime? now]) {
    final g = current(p, now);
    if (g == null) return 0;
    return (weekBest(p, now) / (g['target'] as num)).clamp(0.0, 1.0);
  }

  static bool achieved(PlayerProfile p, [DateTime? now]) => progress(p, now) >= 1;

  static bool claimed(PlayerProfile p, [DateTime? now]) => ((current(p, now)?['claimed'] as Map?)?['done']) == true;

  /// One reward per week when the goal is reached. Returns true when granted.
  static bool claim(PlayerProfile p, [DateTime? now]) {
    final g = current(p, now);
    if (g == null || !achieved(p, now) || claimed(p, now)) return false;
    ((g['claimed'] ??= <String, dynamic>{}) as Map)['done'] = true;
    p.addCoins(300);
    p.addGems(5);
    return true;
  }
}
