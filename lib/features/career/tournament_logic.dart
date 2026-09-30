import 'dart:math';
import '../../core/util/dates.dart';
import '../../core/util/misc.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../ai/ai_driver.dart';
import '../content/content_db.dart';
import 'progress.dart';

class BracketEntry {
  final String id, name, cc;
  final double wpm;
  final bool isPlayer;
  const BracketEntry(this.id, this.name, this.cc, this.wpm, {this.isPlayer = false});
}

class Match {
  final BracketEntry a, b;
  BracketEntry? winner;
  Match(this.a, this.b);
  bool involves(BracketEntry e) => a.id == e.id || b.id == e.id;
}

/// Single-elimination bracket against AI opponents. Everything except the player's own matches is simulated,
/// and the whole draw is deterministic for a given (tournament, period, player) so it never changes mid-period.
class Bracket {
  Bracket(this.def, this.entries, this.seed);
  final TournamentDef def;
  final List<BracketEntry> entries; // slot order, size = def.size
  final int seed;
  final List<List<Match>> rounds = [];

  BracketEntry get player => entries.firstWhere((e) => e.isPlayer);

  static Bracket generate(ContentDb db, TournamentDef def, String periodKey, {required String playerName, required String playerCc, required double playerWpm}) {
    final seed = stableHash('${def.id}|$periodKey|$playerName');
    final rnd = Random(seed);
    final seen = <String>{playerName.toLowerCase()};
    final names = <Map<String, dynamic>>[
      for (final e in (db.ai['names'] as List?) ?? const [])
        if (seen.add(((e as Map)['n'] as String).toLowerCase())) Map<String, dynamic>.from(e),
    ];
    if (names.isEmpty) {
      names.addAll([for (var i = 0; i < 40; i++) {'n': 'Racer${i + 1}', 'cc': 'US'}]);
    }
    names.shuffle(rnd);
    final base = max(12.0, playerWpm);
    final entries = <BracketEntry>[];
    for (var i = 0; i < def.size - 1; i++) {
      final n = names[i % names.length];
      final f = 0.62 + 0.62 * (i / max(1, def.size - 2)) + (rnd.nextDouble() - 0.5) * 0.05;
      entries.add(BracketEntry('t$i', n['n'] as String, n['cc'] as String, base * f));
    }
    final slot = rnd.nextInt(def.size);
    entries.shuffle(rnd);
    entries.insert(slot, BracketEntry('player', playerName, playerCc, base, isPlayer: true));
    final b = Bracket(def, entries, seed);
    b.rounds.add([for (var i = 0; i < def.size; i += 2) Match(entries[i], entries[i + 1])]);
    return b;
  }

  /// Simulates AI-vs-AI matches of round [r] (the player's match is decided by [playerWon]).
  void resolveRound(int r, {bool? playerWon}) {
    final rnd = Random(seed + r * 977);
    for (final m in rounds[r]) {
      if (m.winner != null) continue;
      if (m.involves(player)) {
        if (playerWon == null) continue;
        m.winner = playerWon ? player : (m.a.isPlayer ? m.b : m.a);
      } else {
        final d = (m.a.wpm - m.b.wpm) / max(10.0, (m.a.wpm + m.b.wpm) / 2 * 0.12);
        final pa = 1 / (1 + exp(-d));
        m.winner = rnd.nextDouble() < pa ? m.a : m.b;
      }
    }
  }

  void buildNext(int r) {
    if (rounds.length > r + 1) return;
    final w = [for (final m in rounds[r]) m.winner!];
    if (w.length < 2) return;
    rounds.add([for (var i = 0; i < w.length; i += 2) Match(w[i], w[i + 1])]);
  }

  /// Replays the player's saved history onto a fresh bracket: [results] = list of bool (won round i).
  static Bracket replay(Bracket b, List<bool> results) {
    for (var r = 0; r < b.def.rounds; r++) {
      if (r < results.length) {
        b.resolveRound(r, playerWon: results[r]);
        if (r < b.def.rounds - 1) b.buildNext(r);
      } else {
        // resolve the AI-only matches ahead of the player's next fight
        b.resolveRound(r);
        break;
      }
    }
    return b;
  }

  Match? matchOf(int round, BracketEntry e) {
    if (round >= rounds.length) return null;
    for (final m in rounds[round]) {
      if (m.involves(e)) return m;
    }
    return null;
  }
}

class TournamentState {
  final String key;
  int round;
  bool alive;
  double base;
  final List<bool> results;
  final List<int> claimed;
  bool won;
  TournamentState({required this.key, this.round = 0, this.alive = true, this.base = 20, List<bool>? results, List<int>? claimed, this.won = false})
      : results = results ?? [],
        claimed = claimed ?? [];

  factory TournamentState.fromMap(Map m) => TournamentState(
        key: m['key'] as String? ?? '',
        round: (m['round'] as num?)?.toInt() ?? 0,
        alive: m['alive'] as bool? ?? true,
        base: (m['w0'] as num?)?.toDouble() ?? 20,
        results: ((m['res'] as List?) ?? []).map((e) => e == true).toList(),
        claimed: m['claimed'] is Map ? (m['claimed'] as Map).keys.map((e) => int.tryParse(e.toString()) ?? 0).toList() : <int>[],
        won: m['won'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {'key': key, 'round': round, 'alive': alive, 'w0': base, 'res': results, 'claimed': {for (final c in claimed) '$c': true}, 'won': won};
}

class TournamentLogic {
  static String periodKey(TournamentDef d, [DateTime? now]) => d.period == 'weekly' ? weekKey(now) : dayKey(now);

  static TournamentState? stateOf(PlayerProfile p, TournamentDef d, [DateTime? now]) {
    final raw = p.m('tourn')[d.id];
    if (raw is! Map) return null;
    final s = TournamentState.fromMap(raw);
    return s.key == periodKey(d, now) ? s : null;
  }

  static TournamentState enter(PlayerProfile p, TournamentDef d, double baseWpm, [DateTime? now]) {
    final s = TournamentState(key: periodKey(d, now), base: baseWpm);
    p.m('tourn')[d.id] = s.toMap();
    p.addCounter('tournaments_played', 1);
    return s;
  }

  static Bracket bracketFor(ContentDb db, PlayerProfile p, TournamentDef d, TournamentState s) {
    final b = Bracket.generate(db, d, s.key, playerName: p.name, playerCc: p.country, playerWpm: s.base);
    return Bracket.replay(b, s.results);
  }

  /// Records the player's match result; returns rewards {coins,gems,xp,title,skin} earned now.
  static Map<String, dynamic> recordResult(PlayerProfile p, TournamentDef d, TournamentState s, bool won, {ContentDb? db}) {
    final earned = <String, dynamic>{};
    s.results.add(won);
    if (db != null && won) Season.addPoints(p, db, s.round + 1 >= d.rounds ? 100 : 25);
    if (!won) {
      s.alive = false;
    } else {
      final rk = 'r${s.round + 1}';
      final r = d.rewards[rk];
      if (r is Map && !s.claimed.contains(s.round + 1)) {
        s.claimed.add(s.round + 1);
        _merge(earned, r);
      }
      s.round++;
      if (s.round >= d.rounds) {
        s.won = true;
        s.alive = false;
        final w = d.rewards['win'];
        if (w is Map) _merge(earned, w);
        p.addCounter('tournaments_won', 1);
      }
    }
    for (final k in ['coins', 'gems', 'xp']) {
      final v = (earned[k] as num?)?.toInt() ?? 0;
      if (v <= 0) continue;
      if (k == 'coins') p.addCoins(v);
      if (k == 'gems') p.addGems(v);
      if (k == 'xp') p.addXp(v);
    }
    if (earned['title'] is String) p.grantTitle(earned['title'] as String);
    if (earned['skin'] is String) p.grantSkin(earned['skin'] as String);
    p.m('tourn')[d.id] = s.toMap();
    return earned;
  }

  static void _merge(Map<String, dynamic> into, Map from) {
    from.forEach((k, v) {
      if (v is num && into[k] is num) {
        into[k] = (into[k] as num) + v;
      } else {
        into[k as String] = v;
      }
    });
  }

  static AiSpec specFor(ContentDb db, BracketEntry e, Random rnd) {
    final spec = Matchmaker.roster(db, rnd, [e.wpm]).first;
    return AiSpec(id: 'opp', name: e.name, cc: e.cc, persona: spec.persona, baseWpm: e.wpm, vehicleId: spec.vehicleId, paintId: spec.paintId);
  }
}
