import 'dart:math';
import '../../core/util/dates.dart';
import '../../core/util/misc.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';
import '../shop/economy.dart';
import '../race/engine/race_models.dart';
import 'rank.dart';
import 'rewards.dart';

/// Reads any progress metric used by achievements, quests and events.
class Metrics {
  static const bests = {'best_wpm', 'best_acc', 'combo_max', 'survival_best'};

  static double value(ContentDb db, PlayerProfile p, String metric) {
    switch (metric) {
      case 'best_wpm':
      case 'best_acc':
      case 'combo_max':
      case 'survival_best':
        return p.best(metric);
      case 'streak_best':
        return ((p.m('streak')['best'] as num?) ?? 0).toDouble();
      case 'stages_cleared':
        return p.stagesCleared.toDouble();
      case 'campaign_stars':
        return p.totalStars.toDouble();
      case 'boss_defeated':
        return p.bossesDefeated.toDouble();
      case 'vehicles_owned':
        return db.vehicles.where((v) => Economy.ownsVehicle(p, v)).length.toDouble();
      case 'skins_owned':
        // only skins the player acquired count (the free defaults do not)
        return db.skins.where((s) => p.ownsSkin(s.id) && !(s.price.free && s.unlock.isEmpty)).length.toDouble();
      case 'level':
        return Economy.levelOf(db, p).toDouble();
      case 'rank_tier':
        return Ranks.tierIndex(db, p.rankPoints).toDouble();
      case 'world_stops':
        return p.worldStops.toDouble();
      default:
        return p.counter(metric).toDouble();
    }
  }
}

class AchievementUnlock {
  final Achievement a;
  AchievementUnlock(this.a);
}

class Achievements {
  static bool unlocked(PlayerProfile p, String id) => p.m('ach').containsKey(id);
  static bool claimed(PlayerProfile p, String id) => p.m('achClaimed').containsKey(id);

  static double progress(ContentDb db, PlayerProfile p, Achievement a) => (Metrics.value(db, p, a.metric) / a.target).clamp(0.0, 1.0);

  static bool hasPending(ContentDb db, PlayerProfile p) {
    for (final a in db.achievements) {
      if (!a.enabled || unlocked(p, a.id)) continue;
      if (Metrics.value(db, p, a.metric) >= a.target) return true;
    }
    return false;
  }

  /// Unlocks every achievement whose target is reached and hands out items tied to it (vehicles, skins, outfits).
  static List<Achievement> evaluate(ContentDb db, PlayerProfile p) {
    final out = <Achievement>[];
    final ach = p.m('ach');
    for (final a in db.achievements) {
      if (!a.enabled || ach.containsKey(a.id)) continue;
      if (Metrics.value(db, p, a.metric) < a.target) continue;
      ach[a.id] = nowMs();
      out.add(a);
      for (final v in db.vehicles) {
        if (v.achievementId == a.id) p.grantVehicle(v.id);
      }
      for (final s in db.skins) {
        if (s.achievementId == a.id) p.grantSkin(s.id);
      }
      for (final o in db.outfits) {
        if (o.achievementId == a.id) p.grantOutfit(o.id);
      }
    }
    return out;
  }

  /// Claims the reward of an unlocked achievement. Returns the description lines or null when not claimable.
  static List<String>? claim(ContentDb db, PlayerProfile p, String id) {
    final a = db.achievement(id);
    if (a == null || !unlocked(p, id) || claimed(p, id)) return null;
    p.m('achClaimed')[id] = nowMs();
    final reward = Map<String, dynamic>.from(a.reward);
    if (a.title != null) reward['title'] = a.title;
    return Rewards.grant(p, db, reward);
  }

  static int claimableCount(ContentDb db, PlayerProfile p) => db.achievements.where((a) => unlocked(p, a.id) && !claimed(p, a.id)).length;
  static int unlockedCount(PlayerProfile p) => p.m('ach').length;
}

// ---------------------------------------------------------------------------------------------------- quests

class QuestView {
  final Quest q;
  final int progress;
  final bool done, claimed;
  QuestView(this.q, this.progress, this.done, this.claimed);
  double get fraction => (progress / q.target).clamp(0.0, 1.0);
}

class Quests {
  static String keyFor(String period, [DateTime? now]) => period == 'weekly' ? weekKey(now) : dayKey(now);

  /// Deterministic selection for a period: different metrics, same for everybody.
  static List<Quest> selection(ContentDb db, String period, [DateTime? now]) {
    final pool = db.quests.where((q) => q.enabled && q.period == period).toList()..sort((a, b) => a.id.compareTo(b.id));
    final count = ((db.catalog['questCounts'] as Map?)?[period] as num?)?.toInt() ?? (period == 'weekly' ? 3 : 3);
    final n = (period == 'weekly' ? (db.econ('quests')['weeklyCount'] as num?) : (db.econ('quests')['dailyCount'] as num?))?.toInt() ?? count;
    final key = keyFor(period, now);
    var seed = stableHash('quests|$period|$key');
    final out = <Quest>[];
    final metrics = <String>{};
    var guard = 0;
    while (out.length < n && guard++ < 200 && pool.isNotEmpty) {
      final q = pool[seed % pool.length];
      seed = stableHash('$seed|$guard');
      if (metrics.add(q.metric) && !out.contains(q)) out.add(q);
    }
    return out;
  }

  /// Makes sure the stored record belongs to the current period; snapshots metric baselines on a new period.
  static Map<String, dynamic> ensure(ContentDb db, PlayerProfile p, String period, [DateTime? now]) {
    final root = p.m('quests');
    var rec = (root[period] as Map?)?.cast<String, dynamic>();
    final key = keyFor(period, now);
    if (rec == null || rec['key'] != key) {
      rec = {'key': key, 'base': <String, dynamic>{}, 'claimed': <String, dynamic>{}, 'best': <String, dynamic>{}};
      for (final q in selection(db, period, now)) {
        (rec['base'] as Map)[q.metric] = Metrics.value(db, p, q.metric);
      }
      root[period] = rec;
    } else {
      // metrics of newly selected quests (after a content update) also need a baseline
      for (final q in selection(db, period, now)) {
        final base = (rec['base'] ??= <String, dynamic>{}) as Map;
        base.putIfAbsent(q.metric, () => Metrics.value(db, p, q.metric));
      }
    }
    return rec;
  }

  static bool needsSetup(ContentDb db, PlayerProfile p, String period, [DateTime? now]) {
    final rec = p.m('quests')[period] as Map?;
    if (rec == null || rec['key'] != keyFor(period, now)) return true;
    final base = rec['base'] as Map?;
    return selection(db, period, now).any((q) => base == null || !base.containsKey(q.metric));
  }

  static int progressOf(ContentDb db, PlayerProfile p, Map<String, dynamic> rec, String metric) {
    if (Metrics.bests.contains(metric)) return ((rec['best'] as Map?)?[metric] as num?)?.round() ?? 0;
    final base = ((rec['base'] as Map?)?[metric] as num?)?.toDouble() ?? 0;
    return max(0, (Metrics.value(db, p, metric) - base).round());
  }

  static List<QuestView> views(ContentDb db, PlayerProfile p, String period, [DateTime? now]) {
    final rec = (p.m('quests')[period] as Map?)?.cast<String, dynamic>();
    if (rec == null || rec['key'] != keyFor(period, now)) return [for (final q in selection(db, period, now)) QuestView(q, 0, false, false)];
    return [
      for (final q in selection(db, period, now))
        () {
          final pr = progressOf(db, p, rec, q.metric);
          return QuestView(q, min(pr, q.target), pr >= q.target, (rec['claimed'] as Map?)?.containsKey(q.id) == true);
        }()
    ];
  }

  static List<String>? claim(ContentDb db, PlayerProfile p, String period, String questId, {DateTime? now}) {
    final rec = ensure(db, p, period, now);
    final q = selection(db, period, now).where((e) => e.id == questId).firstOrNull;
    if (q == null) return null;
    final claimedMap = (rec['claimed'] ??= <String, dynamic>{}) as Map;
    if (claimedMap.containsKey(q.id) || progressOf(db, p, rec, q.metric) < q.target) return null;
    claimedMap[q.id] = true;
    p.addCounter('quests_done', 1);
    Season.addPoints(p, db, q.sp, now: now);
    return Rewards.grant(p, db, Map<String, dynamic>.from(q.reward));
  }

  static int claimable(ContentDb db, PlayerProfile p, [DateTime? now]) => ['daily', 'weekly'].fold<int>(0, (a, per) => a + views(db, p, per, now).where((v) => v.done && !v.claimed).length);

  /// After a race: keeps the per-period best of "best" style metrics (combo, wpm...).
  static void recordBests(ContentDb db, PlayerProfile p, Map<String, double> raceBests, {DateTime? now}) {
    for (final period in ['daily', 'weekly']) {
      final rec = ensure(db, p, period, now);
      final best = (rec['best'] ??= <String, dynamic>{}) as Map;
      raceBests.forEach((m, v) {
        if (v > ((best[m] as num?) ?? 0)) best[m] = v;
      });
    }
    for (final e in db.activeEvents) {
      final rec = Events.ensure(db, p, e, now: now);
      final best = (rec['best'] ??= <String, dynamic>{}) as Map;
      raceBests.forEach((m, v) {
        if (v > ((best[m] as num?) ?? 0)) best[m] = v;
      });
    }
  }

  static Map<String, double> bestsFromRace(RaceResult r) => {
        if (!r.suspicious) 'best_wpm': r.wpm,
        if (!r.suspicious && r.chars >= 60) 'best_acc': r.accuracy,
        if (!r.suspicious) 'combo_max': r.maxCombo.toDouble(),
        if (!r.suspicious && r.extra['survived'] != null) 'survival_best': (r.extra['survived'] as num).toDouble(),
      };
}

// ---------------------------------------------------------------------------------------------------- events

class Events {
  static Map<String, dynamic> ensure(ContentDb db, PlayerProfile p, GameEvent e, {DateTime? now}) {
    final root = p.m('events');
    final rec = ((root[e.id] ??= <String, dynamic>{'claimed': <String, dynamic>{}, 'base': <String, dynamic>{}, 'best': <String, dynamic>{}}) as Map).cast<String, dynamic>();
    final base = (rec['base'] ??= <String, dynamic>{}) as Map;
    for (final t in e.tasks) {
      final m = t['metric'] as String;
      base.putIfAbsent(m, () => Metrics.value(db, p, m));
    }
    root[e.id] = rec;
    return rec;
  }

  static int taskProgress(ContentDb db, PlayerProfile p, GameEvent e, Map<String, dynamic> t) {
    final rec = (p.m('events')[e.id] as Map?)?.cast<String, dynamic>();
    if (rec == null) return 0;
    final m = t['metric'] as String;
    if (Metrics.bests.contains(m)) return ((rec['best'] as Map?)?[m] as num?)?.round() ?? 0;
    final base = ((rec['base'] as Map?)?[m] as num?)?.toDouble() ?? 0;
    return max(0, (Metrics.value(db, p, m) - base).round());
  }

  static bool taskClaimed(PlayerProfile p, GameEvent e, String id) => ((p.m('events')[e.id] as Map?)?['claimed'] as Map?)?.containsKey(id) == true;

  static List<String>? claimTask(ContentDb db, PlayerProfile p, GameEvent e, String taskId, {DateTime? now}) {
    if (!e.isActive(now)) return null;
    final rec = ensure(db, p, e, now: now);
    final t = e.tasks.where((x) => x['id'] == taskId).firstOrNull;
    if (t == null) return null;
    final claimed = (rec['claimed'] ??= <String, dynamic>{}) as Map;
    if (claimed.containsKey(taskId) || taskProgress(db, p, e, t) < (t['target'] as num).toInt()) return null;
    claimed[taskId] = true;
    return Rewards.grant(p, db, (t['reward'] as Map?)?.cast<String, dynamic>());
  }

  static bool allDone(PlayerProfile p, GameEvent e) => e.tasks.every((t) => taskClaimed(p, e, t['id'] as String));

  static List<String>? claimFinal(ContentDb db, PlayerProfile p, GameEvent e, {DateTime? now}) {
    if (!e.isActive(now) || !allDone(p, e) || taskClaimed(p, e, '_final')) return null;
    final rec = ensure(db, p, e, now: now);
    ((rec['claimed'] ??= <String, dynamic>{}) as Map)['_final'] = true;
    return Rewards.grant(p, db, e.finalReward);
  }
}

// ---------------------------------------------------------------------------------------------------- season

class SeasonInfo {
  final int id, level, points, pointsInLevel, perLevel, maxLevel;
  final DateTime start, end;
  final Map<String, dynamic> theme;
  SeasonInfo(this.id, this.level, this.points, this.pointsInLevel, this.perLevel, this.maxLevel, this.start, this.end, this.theme);
  Duration get left => end.difference(DateTime.now());
  double get levelProgress => level >= maxLevel ? 1 : pointsInLevel / perLevel;
}

class Season {
  static int idAt(ContentDb db, [DateTime? now]) {
    final anchor = parseIso(db.season['anchor'] as String?) ?? DateTime(2026, 9, 29);
    final len = (db.season['lengthDays'] as num?)?.toInt() ?? 28;
    final n = (now ?? DateTime.now());
    final days = DateTime(n.year, n.month, n.day).difference(DateTime(anchor.year, anchor.month, anchor.day)).inDays;
    return days < 0 ? 0 : days ~/ len + 1;
  }

  static bool enabled(ContentDb db) => db.season['track'] is List && (db.season['track'] as List).isNotEmpty;

  static List<Map<String, dynamic>> track(ContentDb db) => ((db.season['track'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  static Map<String, dynamic> record(ContentDb db, PlayerProfile p, [DateTime? now]) {
    final id = idAt(db, now);
    final s = p.m('season');
    if (((s['id'] as num?)?.toInt() ?? 0) != id) {
      s
        ..['id'] = id
        ..['premium'] = false
        ..['free'] = <dynamic>[]
        ..['prem'] = <dynamic>[];
    }
    return s;
  }

  static SeasonInfo info(ContentDb db, PlayerProfile p, [DateTime? now]) {
    final id = idAt(db, now);
    final per = (db.season['pointsPerLevel'] as num?)?.toInt() ?? 100;
    final maxL = (db.season['maxLevel'] as num?)?.toInt() ?? 40;
    final pts = p.counter('sp_$id');
    final level = min(maxL, pts ~/ per);
    final anchor = parseIso(db.season['anchor'] as String?) ?? DateTime(2026, 9, 29);
    final len = (db.season['lengthDays'] as num?)?.toInt() ?? 28;
    final a = DateTime(anchor.year, anchor.month, anchor.day);
    final start = a.add(Duration(days: (id - 1) * len));
    final themes = ((db.season['themes'] as List?) ?? const []).cast<Map>();
    final theme = themes.isEmpty ? <String, dynamic>{} : themes[(id - 1) % themes.length].cast<String, dynamic>();
    return SeasonInfo(id, level, pts, pts - level * per, per, maxL, start, start.add(Duration(days: len)), theme);
  }

  static void addPoints(PlayerProfile p, ContentDb db, int n, {DateTime? now}) {
    if (n <= 0 || !enabled(db)) return;
    final id = idAt(db, now);
    if (id <= 0) return;
    p.addCounter('sp_$id', n);
  }

  static bool claimedFree(PlayerProfile p, int level) => ((p.m('season')['free'] as List?) ?? const []).contains(level);
  static bool claimedPrem(PlayerProfile p, int level) => ((p.m('season')['prem'] as List?) ?? const []).contains(level);
  static bool premium(PlayerProfile p) => p.m('season')['premium'] == true;

  /// Premium flag of the *current* season (read-only, never mutates the profile).
  static bool isPremium(ContentDb db, PlayerProfile p, [DateTime? now]) => ((p.m('season')['id'] as num?)?.toInt() ?? 0) == idAt(db, now) && premium(p);

  static void grantPremium(PlayerProfile p, ContentDb db, [DateTime? now]) {
    record(db, p, now)['premium'] = true;
  }

  /// Claims one side of a track level; returns description lines, or null when not claimable.
  static List<String>? claim(ContentDb db, PlayerProfile p, int level, {required bool premiumSide, DateTime? now}) {
    final rec = record(db, p, now);
    final si = info(db, p, now);
    if (level > si.level) return null;
    final row = track(db).where((r) => r['level'] == level).firstOrNull;
    if (row == null) return null;
    final list = ((rec[premiumSide ? 'prem' : 'free'] ??= <dynamic>[]) as List);
    if (list.contains(level)) return null;
    if (premiumSide && rec['premium'] != true) return null;
    list.add(level);
    return Rewards.grant(p, db, (row[premiumSide ? 'premium' : 'free'] as Map?)?.cast<String, dynamic>());
  }

  static int claimableCount(ContentDb db, PlayerProfile p, [DateTime? now]) {
    if (!enabled(db)) return 0;
    final si = info(db, p, now);
    final rec = p.m('season');
    final same = ((rec['id'] as num?)?.toInt() ?? 0) == si.id;
    var n = 0;
    for (final r in track(db)) {
      final l = (r['level'] as num).toInt();
      if (l > si.level) break;
      if (!(same && claimedFree(p, l)) && r['free'] != null) n++;
      if (same && premium(p) && !claimedPrem(p, l) && r['premium'] != null) n++;
    }
    return n;
  }

  /// Claims everything currently available. Returns all description lines.
  static List<String> claimAll(ContentDb db, PlayerProfile p, {DateTime? now}) {
    final out = <String>[];
    record(db, p, now);
    final si = info(db, p, now);
    for (var l = 1; l <= si.level; l++) {
      out.addAll(claim(db, p, l, premiumSide: false, now: now) ?? const []);
      out.addAll(claim(db, p, l, premiumSide: true, now: now) ?? const []);
    }
    return out;
  }
}

// ---------------------------------------------------------------------------------------------------- daily login streak

class LoginStreak {
  static bool claimable(PlayerProfile p, [DateTime? now]) => p.streak > 0 && ((p.m('streak')['claimed'] as String?) ?? '') != dayKey(now) && p.streakLast == dayKey(now);

  /// Opening the app counts as a login for the streak (new day -> +1, missed day -> back to 1).
  static int register(PlayerProfile p, [DateTime? now]) => p.registerActivity(now);

  static Map<String, dynamic> rewardFor(ContentDb db, int streakCount) {
    final list = ((db.econ('streak')['rewards'] as List?) ?? const []).cast<Map>();
    if (list.isEmpty) return {'coins': 100};
    return list[(max(1, streakCount) - 1) % list.length].cast<String, dynamic>();
  }

  static List<String>? claim(ContentDb db, PlayerProfile p, [DateTime? now]) {
    if (!claimable(p, now)) return null;
    p.m('streak')['claimed'] = dayKey(now);
    return Rewards.grant(p, db, rewardFor(db, p.streak));
  }
}

// ---------------------------------------------------------------------------------------------------- orchestration

class ProgressReport {
  final List<Achievement> achievements;
  ProgressReport(this.achievements);
  bool get isEmpty => achievements.isEmpty;
}

class Progression {
  /// Cheap check used by the watcher before it mutates the profile.
  static bool needsWork(ContentDb db, PlayerProfile p, [DateTime? now]) =>
      Achievements.hasPending(db, p) || Quests.needsSetup(db, p, 'daily', now) || Quests.needsSetup(db, p, 'weekly', now) || (Season.enabled(db) && ((p.m('season')['id'] as num?)?.toInt() ?? 0) != Season.idAt(db, now));

  static ProgressReport evaluate(ContentDb db, PlayerProfile p, [DateTime? now]) {
    Quests.ensure(db, p, 'daily', now);
    Quests.ensure(db, p, 'weekly', now);
    if (Season.enabled(db)) Season.record(db, p, now);
    return ProgressReport(Achievements.evaluate(db, p));
  }

  /// Season points for a finished race.
  static int racePoints(RaceResult r) => r.suspicious || r.chars < 10 ? 0 : 8 + (r.won && r.opponents > 0 ? 6 : 0) + (r.accuracy >= 97 ? 2 : 0);
}
