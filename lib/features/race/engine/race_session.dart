import 'dart:math';
import '../../ai/ai_driver.dart';
import '../../ai/taunts.dart';
import 'metrics.dart';
import 'race_models.dart';
import 'typing_engine.dart';

enum RaceEventType { keyCorrect, keyWrong, comboTier, nitroStart, nitroEnd, perfectWord, pitPrompt, pitSuccess, pitFail, powerPrompt, powerSuccess, powerFail, slipstreamOn, slipstreamOff, taunt, overtake, overtaken, bump, finish, photoFinish, shieldBlocked, stunned, go }

class RaceEvent {
  final RaceEventType type;
  final String? text;
  final String? who;
  final double value;
  const RaceEvent(this.type, {this.text, this.who, this.value = 0});
}

enum ChallengeKind { shield, emp, turbo, pit }

class Challenge {
  final ChallengeKind kind;
  final String word;
  final double timeLimit;
  double left;
  int typed = 0;
  bool failed = false;
  Challenge(this.kind, this.word, this.timeLimit) : left = timeLimit;
  bool get isPit => kind == ChallengeKind.pit;
}

class RacerState {
  final String id, name, cc;
  final bool isPlayer, isGhost;
  final AiSpec? spec;
  double eff = 0; // effective progress in characters
  double speedCps = 0;
  bool finished = false;
  double finishTime = 0;
  int rank = 0;
  double stunLeft = 0;
  bool shielded = false;
  RacerState({required this.id, required this.name, required this.cc, this.isPlayer = false, this.isGhost = false, this.spec});
}

/// Player vehicle modifiers derived from base stats and upgrades (each 1..10 + upgrade levels).
class VehicleMods {
  final double accelBonus; // extra progress per correct char (max ~+10%)
  final double stability; // reduces error braking (0..0.5)
  final double nitroFill; // nitro meter % per correct char
  final double earnings; // coin multiplier
  const VehicleMods({this.accelBonus = 0, this.stability = 0, this.nitroFill = 2.4, this.earnings = 1});
  factory VehicleMods.from({required int accel, required int stab, required int nitro, required int earn, int upAccel = 0, int upStab = 0, int upNitro = 0, int upEarn = 0, double perLevel = 0.03}) => VehicleMods(
        accelBonus: min(0.12, (accel - 3) * 0.006 + upAccel * perLevel * 0.8),
        stability: min(0.5, (stab - 3) * 0.03 + upStab * perLevel * 1.5),
        nitroFill: 2.2 + nitro * 0.12 + upNitro * 0.25,
        earnings: 1 + (earn - 3) * 0.02 + upEarn * perLevel * 1.5,
      );
}

/// Pure race simulation: one player typing + AI racers + ghosts. Drive with [update]; feed keys via [onChar]/[onBackspace].
class RaceSession {
  RaceSession(this.config, this.engine, {Random? rnd, this.mods = const VehicleMods(), this.playerName = 'You', this.playerCc = '', this.playerVehicleId = 'c_sprout', this.taunts})
      : rnd = rnd ?? Random() {
    final total = config.text.len;
    player = RacerState(id: 'player', name: playerName, cc: playerCc, isPlayer: true);
    racers.add(player);
    for (final spec in config.opponents) {
      final r = RacerState(id: spec.id, name: spec.name, cc: spec.cc, spec: spec);
      racers.add(r);
      drivers[spec.id] = AiDriver(spec, total, this.rnd);
    }
    for (var i = 0; i < config.ghosts.length; i++) {
      final g = config.ghosts[i];
      final r = RacerState(id: 'ghost$i', name: g.name, cc: '', isGhost: true);
      racers.add(r);
      ghostDrivers[r.id] = g.samples != null && g.samples!.isNotEmpty ? GhostDriver.fromSamples(g.name, g.samples!, total) : GhostDriver.constant(g.name, g.wpm, total);
    }
    _scheduleChallenges();
    for (final r in racers) {
      _lastSign[r.id] = 0;
    }
  }

  final RaceConfig config;
  final TypingEngine engine;
  final Random rnd;
  final VehicleMods mods;
  final String playerName, playerCc, playerVehicleId;
  final TauntBook? taunts;
  late final RacerState player;
  final List<RacerState> racers = [];
  final Map<String, AiDriver> drivers = {};
  final Map<String, GhostDriver> ghostDrivers = {};
  final List<RaceEvent> _events = [];

  double time = 0; // seconds since GO
  bool started = false;
  bool over = false;
  bool timeUp = false;
  bool photoFinish = false;
  int get timeMs => (time * 1000).round();

  // --- player mechanics state
  double brake = 0; // seconds of reduced gain after an error
  double nitroMeter = 0; // 0..100
  double nitroLeft = 0;
  bool get nitroActive => nitroLeft > 0;
  int nitroUses = 0;
  bool slipstream = false;
  double turboLeft = 0;
  double bonusChars = 0;
  int perfectWords = 0;
  int powerupsUsed = 0;
  int challengeChars = 0; // chars typed on power-up/pit words (count towards WPM)
  bool pitPerfect = false, pitDone = false;
  int comboTierShown = 1;
  Challenge? challenge;
  final List<_Sched> _sched = [];
  double _wordStartT = 0;
  int _wordChars = 0;
  final List<List<num>> samples = [];
  double _sampleAcc = 0;
  final Map<String, int> wordErrorMap = {};
  int finishedCount = 0;
  final List<RacerState> finishOrder = [];
  final Map<String, int> _lastSign = {};
  double _tauntCd = 4;

  // replay buffer (30 Hz samples of fractions for each racer)
  final Map<String, List<double>> history = {};
  double _histAcc = 0;

  int get total => config.text.len;
  double fractionOf(RacerState r) => total == 0 ? 1 : (r.eff / total).clamp(0.0, 1.0);

  List<RaceEvent> drainEvents() {
    final e = List<RaceEvent>.from(_events);
    _events.clear();
    return e;
  }

  void _emit(RaceEventType t, {String? text, String? who, double value = 0}) => _events.add(RaceEvent(t, text: text, who: who, value: value));

  void start() {
    started = true;
    time = 0;
    _emit(RaceEventType.go);
  }

  static const _powerWords = {
    ChallengeKind.shield: ['SHIELD', 'ARMOR', 'GUARD', 'BARRIER'],
    ChallengeKind.emp: ['EMP', 'PULSE', 'SHOCK', 'ZAP'],
    ChallengeKind.turbo: ['TURBO', 'BOOST', 'BLAST', 'ROCKET'],
    ChallengeKind.pit: ['SERVICE', 'REPAIR', 'REFUEL', 'TUNEUP', 'MECHANIC'],
  };

  void _scheduleChallenges() {
    final r = config.rules;
    if (r.pit && total >= 90) _sched.add(_Sched(0.5, ChallengeKind.pit));
    if (r.powerups && total >= 60) {
      final kinds = [ChallengeKind.shield, ChallengeKind.emp, ChallengeKind.turbo]..shuffle(rnd);
      final marks = total >= 160 ? [0.2, 0.36, 0.72] : [0.3, 0.7];
      for (var i = 0; i < marks.length; i++) {
        _sched.add(_Sched(marks[i] + (rnd.nextDouble() - 0.5) * 0.04, kinds[i % kinds.length]));
      }
    }
    _sched.sort((a, b) => a.at.compareTo(b.at));
  }

  // ------------------------------------------------------------------ input
  /// Returns the key result; while a challenge is active keys go to the challenge word.
  KeyResult onChar(String ch) {
    if (!started || over || player.finished) return KeyResult.ignored;
    final c = challenge;
    if (c != null) return _challengeKey(c, ch);
    final pos0 = engine.pos;
    final res = engine.type(ch, timeMs);
    if (res == KeyResult.correct) {
      _onCorrect(pos0);
    } else if (res == KeyResult.wrong) {
      _onWrong();
    }
    return res;
  }

  void onBackspace() {
    if (!started || over || player.finished || challenge != null) return;
    engine.backspace();
  }

  void _onCorrect(int pos0) {
    final pureRules = config.rules.pure;
    var gain = 1.0;
    if (!pureRules) {
      if (brake > 0) gain *= 0.4;
      if (nitroActive) gain += 0.25;
      if (slipstream) gain += 0.15;
      gain *= 1 + (config.rules.vehicleStats ? mods.accelBonus : 0);
    }
    player.eff += gain;
    if (!pureRules && config.rules.nitro && !nitroActive) {
      nitroMeter = min(100, nitroMeter + mods.nitroFill * (1 + (comboMultiplier(engine.combo) - 1) * 0.12));
      if (nitroMeter >= 100) {
        nitroLeft = 4.0;
        nitroUses++;
        _emit(RaceEventType.nitroStart);
      }
    }
    final tier = comboMultiplier(engine.combo);
    if (tier > comboTierShown) {
      comboTierShown = tier;
      _emit(RaceEventType.comboTier, value: tier.toDouble());
    }
    _emit(RaceEventType.keyCorrect, value: engine.combo.toDouble());
    // word completion -> Perfect Word
    final done = engine.text[pos0];
    if (done == ' ' || engine.finished) {
      final len = _wordChars + 1;
      final secs = time - _wordStartT;
      final avgWordSecs = len / max(1.0, engine.rollingWpm(timeMs, windowMs: 6000) * 5 / 60);
      final clean = engine.lastWordClean || engine.finished && engine.wordErrors == 0;
      if (!pureRules && clean && len >= 5 && secs < avgWordSecs * 0.9 && secs > 0.15) {
        perfectWords++;
        bonusChars += 0.8;
        player.eff += 0.8;
        _emit(RaceEventType.perfectWord);
      }
      _wordStartT = time;
      _wordChars = 0;
      _maybeStartChallenge();
    } else {
      _wordChars++;
    }
  }

  void _onWrong() {
    final w = engine.text.substring(engine.wordStart, engine.wordEnd);
    wordErrorMap[w] = (wordErrorMap[w] ?? 0) + 1;
    _emit(RaceEventType.keyWrong);
    nitroMeter *= 0.5;
    comboTierShown = 1;
    if (config.rules.pure || !config.rules.penalties) return;
    if (player.shielded) {
      player.shielded = false;
      _emit(RaceEventType.shieldBlocked);
      return;
    }
    brake = 0.6 * (1 - (config.rules.vehicleStats ? mods.stability : 0));
  }

  // ------------------------------------------------------------ challenges
  void _maybeStartChallenge() {
    if (challenge != null || _sched.isEmpty || player.finished) return;
    if (fractionOf(player) < _sched.first.at) return;
    if (total - engine.pos < 12) {
      _sched.clear();
      return;
    }
    final s = _sched.removeAt(0);
    final words = _powerWords[s.kind]!;
    final w = words[rnd.nextInt(words.length)];
    challenge = Challenge(s.kind, w, s.kind == ChallengeKind.pit ? 7.0 : 4.5);
    _emit(s.kind == ChallengeKind.pit ? RaceEventType.pitPrompt : RaceEventType.powerPrompt, text: w, value: s.kind.index.toDouble());
  }

  KeyResult _challengeKey(Challenge c, String ch) {
    if (ch.toLowerCase() == c.word[c.typed].toLowerCase()) {
      c.typed++;
      challengeChars++;
      _emit(RaceEventType.keyCorrect, value: c.typed.toDouble());
      if (c.typed >= c.word.length) _challengeDone(c, true);
      return KeyResult.correct;
    }
    _emit(RaceEventType.keyWrong);
    if (c.isPit) {
      _challengeDone(c, false); // pit stop needs 100% accuracy
    }
    return KeyResult.wrong;
  }

  void _challengeDone(Challenge c, bool ok) {
    challenge = null;
    if (c.isPit) {
      pitDone = true;
      if (ok) {
        pitPerfect = true;
        nitroMeter = 100;
        nitroLeft = 4.0;
        nitroUses++;
        brake = 0;
        bonusChars += 3;
        player.eff += 3;
        _emit(RaceEventType.pitSuccess);
      } else {
        // slow pit: lose ~2.5 seconds of progress
        final cps = max(2.0, engine.rollingWpm(timeMs) * 5 / 60);
        player.eff = max(0, player.eff - cps * 2.5);
        brake = 1.2;
        _emit(RaceEventType.pitFail);
      }
      return;
    }
    if (!ok) {
      _emit(RaceEventType.powerFail);
      return;
    }
    powerupsUsed++;
    _emit(RaceEventType.powerSuccess, text: c.kind.name);
    switch (c.kind) {
      case ChallengeKind.shield:
        player.shielded = true;
        break;
      case ChallengeKind.turbo:
        turboLeft = 2.5;
        break;
      case ChallengeKind.emp:
        // disable the closest opponent ahead (or the leader) for 2.5s
        RacerState? target;
        for (final r in racers) {
          if (r.isPlayer || r.finished || r.isGhost) continue;
          if (target == null) {
            target = r;
            continue;
          }
          final dr = r.eff - player.eff, dt = target.eff - player.eff;
          if ((dr > 0 && (dt <= 0 || dr < dt)) || (dt <= 0 && dr > dt)) target = r;
        }
        if (target != null) {
          drivers[target.id]?.stun(2.5);
          _emit(RaceEventType.stunned, who: target.name);
        }
        break;
      case ChallengeKind.pit:
        break;
    }
  }

  // ---------------------------------------------------------------- update
  void update(double dt) {
    if (!started) return;
    if (over) {
      return;
    }
    time += dt;
    final playerFrac = fractionOf(player);
    final playerWpm = engine.rollingWpm(timeMs);
    player.speedCps = playerWpm * 5 / 60;

    if (brake > 0) brake -= dt;
    if (nitroActive) {
      nitroLeft -= dt;
      nitroMeter = max(0, nitroLeft / 4.0 * 100);
      if (nitroLeft <= 0) {
        nitroLeft = 0;
        nitroMeter = 0;
        _emit(RaceEventType.nitroEnd);
      }
    }
    if (turboLeft > 0) {
      final d = min(dt, turboLeft);
      turboLeft -= dt;
      final add = 6.0 / 2.5 * d;
      player.eff += add;
      bonusChars += add;
    }
    if (challenge != null) {
      challenge!.left -= dt;
      if (challenge!.left <= 0) _challengeDone(challenge!, false);
    }
    if (challenge == null && _sched.isNotEmpty && fractionOf(player) > _sched.first.at + 0.12) _maybeStartChallenge();

    // coasting when the last key was typed but distance remains
    if (!player.finished && engine.finished && player.eff < total) {
      player.eff = min(total.toDouble(), player.eff + max(3.0, player.speedCps) * dt);
    }
    if (config.rules.pure && engine.finished) player.eff = total.toDouble();
    if (!player.finished && player.eff >= total - 1e-6) _finish(player);

    // AI and ghosts
    for (final r in racers) {
      if (r.isPlayer) continue;
      if (r.isGhost) {
        final g = ghostDrivers[r.id]!;
        if (!r.finished) {
          final before = g.pos;
          g.update(dt);
          r.eff = g.pos;
          r.speedCps = (g.pos - before) / max(dt, 1e-6);
          if (g.finished) _finish(r);
        }
        continue;
      }
      final d = drivers[r.id]!;
      if (!r.finished) {
        final before = d.pos;
        d.update(dt, playerFrac: playerFrac, playerWpm: playerWpm, rubberEnabled: !config.rules.pure || true);
        r.eff = d.pos;
        r.stunLeft = d.stunLeft;
        r.speedCps = (d.pos - before) / max(dt, 1e-6);
        if (d.finished) _finish(r);
      }
    }
    _updateSlipstream();
    _updateOvertakes();
    _updateTaunts(dt);

    // sampling for ghost + replay
    _sampleAcc += dt;
    if (_sampleAcc >= 0.25) {
      _sampleAcc = 0;
      samples.add([double.parse(time.toStringAsFixed(2)), double.parse(engine.pos.toString())]);
    }
    _histAcc += dt;
    if (_histAcc >= 1 / 30) {
      _histAcc = 0;
      for (final r in racers) {
        final h = history.putIfAbsent(r.id, () => <double>[]);
        h.add(fractionOf(r));
        if (h.length > 240) h.removeRange(0, h.length - 240);
      }
    }

    final limit = config.timeLimitMs;
    if (limit != null && timeMs >= limit && !player.finished) {
      timeUp = true;
      _finish(player);
    }
    if (player.finished && !over) {
      // race ends for results once the player crossed the line (others are ranked by current progress)
      _finalize();
    }
  }

  void _finish(RacerState r) {
    if (r.finished) return;
    r.finished = true;
    r.finishTime = time;
    finishedCount++;
    finishOrder.add(r);
    _emit(RaceEventType.finish, who: r.id);
  }

  void _updateSlipstream() {
    if (!config.rules.slipstream || config.rules.pure) return;
    var on = false;
    if (engine.combo >= 6 && !player.finished) {
      for (final r in racers) {
        if (r.isPlayer || r.finished) continue;
        final d = (r.eff - player.eff) / total;
        if (d > 0.004 && d < 0.07) {
          on = true;
          break;
        }
      }
    }
    if (on != slipstream) {
      slipstream = on;
      _emit(on ? RaceEventType.slipstreamOn : RaceEventType.slipstreamOff);
    }
  }

  void _updateOvertakes() {
    for (final r in racers) {
      if (r.isPlayer) continue;
      final d = r.eff - player.eff;
      final sign = d > 0.5 ? 1 : (d < -0.5 ? -1 : 0);
      final prev = _lastSign[r.id] ?? 0;
      if (sign != 0 && prev != 0 && sign != prev) {
        _emit(sign < 0 ? RaceEventType.overtake : RaceEventType.overtaken, who: r.name);
        if ((d.abs() / total) < 0.02) _emit(RaceEventType.bump, who: r.name);
      }
      if (sign != 0) _lastSign[r.id] = sign;
    }
  }

  void _updateTaunts(double dt) {
    final tb = taunts;
    if (tb == null) return;
    _tauntCd -= dt;
    if (_tauntCd > 0) return;
    _tauntCd = 5 + rnd.nextDouble() * 6;
    final ais = racers.where((r) => r.spec != null && !r.finished).toList();
    if (ais.isEmpty) return;
    final bosses = ais.where((r) => r.spec!.isBoss).toList();
    final r = bosses.isNotEmpty && rnd.nextDouble() < 0.7 ? bosses.first : ais[rnd.nextInt(ais.length)];
    final ahead = r.eff > player.eff;
    final line = r.spec!.isBoss ? tb.bossLine(r.spec!.bossId!, rnd) : tb.line(r.spec!.persona, ahead ? 'lead' : 'behind', rnd);
    if (line != null) _emit(RaceEventType.taunt, text: line, who: r.name);
  }

  bool _finalized = false;
  void _finalize() {
    if (_finalized) return;
    _finalized = true;
    over = true;
    // Rank: finished racers by finish time; unfinished by progress.
    final ordered = <RacerState>[...finishOrder];
    final rest = racers.where((r) => !r.finished).toList()..sort((a, b) => b.eff.compareTo(a.eff));
    ordered.addAll(rest);
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].rank = i + 1;
    }
    if (finishOrder.length >= 2) {
      final gap = finishOrder[1].finishTime - finishOrder[0].finishTime;
      if (gap < 0.4 && (finishOrder[0].isPlayer || finishOrder[1].isPlayer)) {
        photoFinish = true;
        _emit(RaceEventType.photoFinish, value: gap);
      }
    } else if (finishOrder.length == 1 && ordered.length > 1) {
      final gapChars = (ordered[1].eff - ordered[0].eff).abs();
      final cps = max(1.0, player.speedCps);
      if (gapChars / cps < 0.4 && ordered[0].isPlayer) photoFinish = true;
    }
  }

  /// Builds the final result. Call after [over] is true (or to force-finish).
  RaceResult buildResult() {
    if (!_finalized) {
      if (!player.finished) _finish(player);
      _finalize();
    }
    final tEnd = max(0.5, player.finishTime);
    final elapsedMs = (engine.lastKeyMs - (engine.firstKeyMs ?? 0)).clamp(500, 1 << 30);
    final wpm = wpmFrom(engine.correctKeys + challengeChars, config.timeLimitMs != null ? min(tEnd * 1000, config.timeLimitMs!.toDouble()) : max(elapsedMs, 500));
    final standings = <RacerResult>[];
    final sorted = [...racers]..sort((a, b) => a.rank.compareTo(b.rank));
    for (final r in sorted) {
      final typedChars = r.isPlayer ? engine.correctKeys.toDouble() : r.eff;
      final tm = r.finished ? r.finishTime : time;
      standings.add(RacerResult(
        id: r.id,
        name: r.isPlayer ? playerName : r.name,
        cc: r.cc,
        isPlayer: r.isPlayer,
        isAi: r.spec != null,
        isGhost: r.isGhost,
        isBoss: r.spec?.isBoss ?? false,
        rank: r.rank,
        time: tm,
        wpm: r.isPlayer ? wpm : wpmFrom(typedChars.round(), max(500, tm * 1000)),
        accuracy: r.isPlayer ? engine.accuracy : 97 - rnd.nextDouble() * 4,
      ));
    }
    final iv = engine.intervals();
    return RaceResult(
      config: config,
      standings: standings,
      playerRank: player.rank,
      wpm: wpm,
      rawWpm: wpmFrom(engine.totalKeys, max(elapsedMs, 500)),
      accuracy: engine.accuracy,
      time: tEnd,
      maxCombo: engine.maxCombo,
      errors: engine.wrongKeys,
      chars: engine.correctKeys,
      nitroUses: nitroUses,
      perfectWords: perfectWords,
      powerupsUsed: powerupsUsed,
      pitPerfect: pitPerfect,
      photoFinish: photoFinish,
      timeUp: timeUp,
      suspicious: false,
      intervals: iv.length > 600 ? iv.sublist(0, 600) : iv,
      samples: samples,
      charStats: engine.charStats,
      wordStats: wordErrorMap,
    );
  }
}

class _Sched {
  final double at;
  final ChallengeKind kind;
  _Sched(this.at, this.kind);
}
