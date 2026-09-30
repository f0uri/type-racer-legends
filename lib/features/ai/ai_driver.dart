import 'dart:math';
import '../../core/util/misc.dart';
import '../../data/models/content_models.dart';
import '../content/content_db.dart';

class PersonaParams {
  final double variance, err, start, fade, rubberBoost, rubberSlow;
  const PersonaParams(this.variance, this.err, this.start, this.fade, this.rubberBoost, this.rubberSlow);
}

class Persona {
  static const aggressive = 'aggressive', balanced = 'balanced', cautious = 'cautious', fatigue = 'fatigue';
  static const all = [aggressive, balanced, cautious, fatigue];
  static final Map<String, PersonaParams> params = {
    aggressive: const PersonaParams(0.16, 0.050, 1.06, 0.0, 0.10, 0.10),
    balanced: const PersonaParams(0.10, 0.030, 1.0, 0.0, 0.10, 0.12),
    cautious: const PersonaParams(0.06, 0.012, 0.95, 0.0, 0.09, 0.14),
    fatigue: const PersonaParams(0.10, 0.028, 1.08, 0.22, 0.12, 0.08),
  };

  /// Overrides the defaults with values from content/ai.json (live-updatable).
  static void applyContent(Map<String, dynamic> personalities) {
    for (final e in personalities.entries) {
      final old = params[e.key];
      final v = e.value;
      if (old == null || v is! Map) continue;
      double n(String k, double d) => (v[k] is num) ? (v[k] as num).toDouble() : d;
      params[e.key] = PersonaParams(n('var', old.variance).clamp(0.0, 0.4), n('err', old.err).clamp(0.0, 0.2), n('start', old.start).clamp(0.8, 1.3), n('fade', old.fade).clamp(0.0, 0.5), n('boost', old.rubberBoost).clamp(0.0, 0.25), n('slow', old.rubberSlow).clamp(0.0, 0.25));
    }
  }

  static String label(String p) => const {aggressive: 'عدواني', balanced: 'متوازن', cautious: 'حذر', fatigue: 'يتعب في النهاية'}[p] ?? 'متوازن';
}

class AiSpec {
  final String id, name, cc, persona, vehicleId, paintId;
  final double baseWpm;
  final String? bossId;
  final double rubberScale; // bosses get less help
  const AiSpec({required this.id, required this.name, required this.cc, required this.persona, required this.baseWpm, required this.vehicleId, required this.paintId, this.bossId, this.rubberScale = 1});
  bool get isBoss => bossId != null;
  AiSpec withWpm(double w) => AiSpec(id: id, name: name, cc: cc, persona: persona, baseWpm: w, vehicleId: vehicleId, paintId: paintId, bossId: bossId, rubberScale: rubberScale);
}

double _gauss(Random r) {
  final u1 = max(1e-9, r.nextDouble()), u2 = r.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}

/// Simulates an AI typist character by character: natural speed variation, bursts, slumps,
/// mistakes (with correction pause), fatigue, and subtle hidden rubber-banding.
class AiDriver {
  AiDriver(this.spec, this.totalChars, this.rnd) {
    _p = Persona.params[spec.persona] ?? Persona.params[Persona.balanced]!;
  }
  final AiSpec spec;
  final int totalChars;
  final Random rnd;
  late final PersonaParams _p;

  double pos = 0;
  /// Multiplier on the spec's speed (used by survival hunters that keep accelerating).
  double wpmScale = 1;
  double stunLeft = 0;
  double _stall = 0, _noise = 0, _burst = 0, _burstLeft = 0, _acc = 0;
  int errors = 0;
  double currentWpm = 0;
  bool get finished => pos >= totalChars;
  double get fraction => totalChars == 0 ? 1 : pos / totalChars;
  bool get isStalled => _stall > 0 || stunLeft > 0;

  /// [playerFrac] player progress 0..1, [playerWpm] player's rolling speed.
  void update(double dt, {required double playerFrac, required double playerWpm, bool rubberEnabled = true}) {
    if (finished) return;
    if (stunLeft > 0) {
      stunLeft -= dt;
      return;
    }
    if (_stall > 0) {
      _stall -= dt;
      return;
    }
    final progress = fraction;
    var mult = 1.0;
    // start vs. settle
    final s = (1 - (progress / 0.25)).clamp(0.0, 1.0);
    mult *= 1 + (_p.start - 1) * s;
    // fatigue in the last part of the race
    if (_p.fade > 0) {
      final t = ((progress - 0.5) / 0.5).clamp(0.0, 1.0);
      mult *= 1 - _p.fade * t * t * (3 - 2 * t);
    }
    // smooth natural variation (Ornstein-Uhlenbeck)
    _noise += -_noise * 0.9 * dt + _p.variance * sqrt(dt) * _gauss(rnd) * 1.4;
    _noise = _noise.clamp(-0.35, 0.35);
    mult *= 1 + _noise;
    // bursts and slumps
    if (_burstLeft > 0) {
      _burstLeft -= dt;
      mult *= 1 + _burst;
    } else if (rnd.nextDouble() < dt * 0.10) {
      _burst = rnd.nextBool() ? 0.12 + rnd.nextDouble() * 0.08 : -(0.10 + rnd.nextDouble() * 0.08);
      _burstLeft = 2.5 + rnd.nextDouble() * 3;
    }
    // hidden rubber band: keeps it close, but only helps if the player actually races
    if (rubberEnabled) {
      final d = playerFrac - progress; // >0: AI is behind
      if (d > 0 && playerWpm >= spec.baseWpm * 0.55) {
        mult *= 1 + min(_p.rubberBoost * spec.rubberScale, d * 2.5);
      } else if (d < 0) {
        mult *= 1 - min(_p.rubberSlow * spec.rubberScale, -d * 2.5);
      }
    }
    final wpm = max(3.0, spec.baseWpm * wpmScale * mult);
    currentWpm = wpm;
    final cps = wpm * 5 / 60;
    _acc += cps * dt * (1 + 0.25 * _gauss(rnd)).clamp(0.4, 1.8);
    while (_acc >= 1 && !finished) {
      _acc -= 1;
      if (rnd.nextDouble() < _p.err) {
        errors++;
        _stall = 0.35 + rnd.nextDouble() * 0.6; // notices and corrects
        break;
      }
      pos += 1;
    }
  }

  void stun(double seconds) => stunLeft = max(stunLeft, seconds);
}

/// Replays a stored run of the player (personal ghost) or a fixed-speed ghost.
class GhostDriver {
  GhostDriver.fromSamples(this.name, this.samples, this.totalChars) : constWpm = null;
  GhostDriver.constant(this.name, double wpm, this.totalChars)
      : samples = const [],
        constWpm = wpm;
  final String name;
  final List<List<num>> samples; // [tSec, pos]
  final double? constWpm;
  final int totalChars;
  double time = 0;
  double pos = 0;
  bool get finished => pos >= totalChars;

  void update(double dt) {
    time += dt;
    if (constWpm != null) {
      pos = min(totalChars.toDouble(), time * constWpm! * 5 / 60);
      return;
    }
    if (samples.isEmpty) return;
    if (time >= samples.last[0]) {
      // continue at the last observed speed
      final a = samples.length > 1 ? samples[samples.length - 2] : [0, 0];
      final b = samples.last;
      final v = (b[1] - a[1]) / max(0.1, (b[0] - a[0]));
      pos = min(totalChars.toDouble(), b[1] + v * (time - b[0]));
      return;
    }
    var i = 0;
    while (i < samples.length - 1 && samples[i + 1][0] < time) {
      i++;
    }
    final a = samples[i], b = samples[min(i + 1, samples.length - 1)];
    final span = (b[0] - a[0]).toDouble();
    final f = span <= 0 ? 0.0 : ((time - a[0]) / span).clamp(0.0, 1.0);
    pos = (a[1] + (b[1] - a[1]) * f).toDouble().clamp(0, totalChars.toDouble());
  }
}

class Matchmaker {
  /// Average WPM of the last 10 races; falls back to [fallback] for new players.
  static double targetWpm(List<double> history, {double fallback = 24}) {
    if (history.isEmpty) return fallback;
    final h = history.length > 10 ? history.sublist(history.length - 10) : history;
    return h.reduce((a, b) => a + b) / h.length;
  }

  /// Opponent speeds spread around the player's level: a few slightly slower, one or two slightly faster.
  static List<double> opponentWpms(double target, int count, Random rnd, {double difficulty = 1.0}) {
    final out = <double>[];
    for (var i = 0; i < count; i++) {
      final f = count == 1 ? 0.5 : i / (count - 1);
      final m = 0.80 + 0.36 * f + (rnd.nextDouble() - 0.5) * 0.06;
      out.add(max(8.0, target * m * difficulty));
    }
    out.shuffle(rnd);
    return out;
  }

  static const _personaWeights = {Persona.aggressive: 25, Persona.balanced: 40, Persona.cautious: 20, Persona.fatigue: 15};

  static String randomPersona(Random rnd) {
    var r = rnd.nextInt(100);
    for (final e in _personaWeights.entries) {
      if (r < e.value) return e.key;
      r -= e.value;
    }
    return Persona.balanced;
  }

  /// Creates a roster of AI racers with unique names, flags, vehicles and personalities.
  static List<AiSpec> roster(ContentDb db, Random rnd, List<double> wpms, {String? playerName}) {
    final seen = <String>{(playerName ?? '').toLowerCase()};
    final names = <Map<String, dynamic>>[
      for (final e in (db.ai['names'] as List?) ?? const [])
        if (seen.add(((e as Map)['n'] as String).toLowerCase())) Map<String, dynamic>.from(e),
    ];
    if (names.isEmpty) names.addAll([{'n': 'Alex', 'cc': 'US'}, {'n': 'Lina', 'cc': 'MA'}, {'n': 'Yuki', 'cc': 'JP'}, {'n': 'Omar', 'cc': 'SA'}, {'n': 'Emma', 'cc': 'SE'}, {'n': 'Hugo', 'cc': 'FR'}, {'n': 'Noor', 'cc': 'AE'}]);
    names.shuffle(rnd);
    final vehicles = db.vehicles.where((v) => v.eventId == null && v.achievementId == null && db.itemAvailable(v)).toList();
    final paints = db.skins.where((s) => s.slot == 'paint' && !s.isExclusive && s.rarity != 'legendary').toList();
    final out = <AiSpec>[];
    for (var i = 0; i < wpms.length; i++) {
      final n = names[i % names.length];
      // faster opponents get rarer vehicles (cosmetic only)
      final tier = wpms[i] > 70 ? 'legendary' : (wpms[i] > 38 ? 'rare' : 'common');
      var pool = vehicles.where((v) => v.rarity == tier).toList();
      if (pool.isEmpty) pool = vehicles;
      final v = pool.isEmpty ? null : pool[rnd.nextInt(pool.length)];
      out.add(AiSpec(
        id: 'ai$i',
        name: n['n'] as String,
        cc: n['cc'] as String,
        persona: randomPersona(rnd),
        baseWpm: wpms[i],
        vehicleId: v?.id ?? 'c_sprout',
        paintId: paints.isEmpty ? 'p_red' : paints[rnd.nextInt(paints.length)].id,
      ));
    }
    return out;
  }

  static AiSpec bossSpec(Boss b, double wpm) => AiSpec(id: b.id, name: loc(b.name), cc: b.cc, persona: b.persona, baseWpm: wpm, vehicleId: b.vehicle, paintId: b.paint, bossId: b.id, rubberScale: 0.45);
}
