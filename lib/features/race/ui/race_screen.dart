import 'dart:async';
import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/misc.dart';
import '../../../core/widgets/common.dart';
import '../../ai/ai_driver.dart';
import '../../ai/taunts.dart';
import '../../garage/look.dart';
import '../engine/metrics.dart';
import '../engine/race_models.dart';
import '../engine/race_session.dart';
import '../engine/typing_engine.dart';
import '../game/env_painter.dart';
import '../game/race_game.dart';
import '../race_builder.dart';
import '../race_outcome.dart';
import 'result_screen.dart';
import 'text_panel.dart';

enum _Phase { lobby, countdown, racing, finishing }

class _Popup {
  final int id;
  final String text;
  final Color color;
  _Popup(this.id, this.text, this.color);
}

/// The race screen: lobby -> countdown -> race -> finish (photo-finish replay) -> results.
/// [rebuild] creates a fresh config for "race again".
class RaceScreen extends ConsumerStatefulWidget {
  /// Test hook: the session of the most recently created race screen.
  @visibleForTesting
  static RaceSession? debugSession;

  const RaceScreen({super.key, required this.config, this.rebuild, this.onFinished});
  final RaceConfig config;
  final RaceConfig Function()? rebuild;

  /// Lets a mode (campaign, tournament...) post-process the outcome and decide what happens next.
  final Future<Widget?> Function(BuildContext context, RaceResult result, RaceOutcome outcome)? onFinished;

  @override
  ConsumerState<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends ConsumerState<RaceScreen> with WidgetsBindingObserver {
  static const _guard = '\u200B\u200B';
  late RaceConfig cfg;
  late TypingEngine engine;
  late RaceSession session;
  late RaceGame game;
  late EnvPainter env;
  late PlayerRig rig;
  final input = TextEditingController(text: _guard);
  final focus = FocusNode();
  final tick = ValueNotifier<int>(0);
  Timer? _hud;
  Timer? _storm;
  _Phase phase = _Phase.lobby;
  int countdown = 3;
  bool riskOn = false;
  bool _paused = false;
  bool _done = false;
  bool _disposed = false;
  int _wordStartMs = 0;
  Offset _stormShake = Offset.zero;
  final List<_Popup> popups = [];
  int _popupId = 0;
  ({String who, String text})? taunt;
  Timer? _tauntTimer;
  bool photoReplay = false;
  late AudioService audio;
  int _bulkInputs = 0;
  final Random _rnd = Random();
  final Stopwatch _sw = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    audio = ref.read(audioProvider);
    _setup(widget.config);
    audio.startMusic();
    _hud = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_disposed) tick.value++;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _setup(RaceConfig c) {
    final db = ref.read(contentProvider);
    final p = ref.read(profileProvider);
    final s = ref.read(settingsProvider);
    cfg = c;
    rig = c.playerLookOverride != null ? PlayerRig(c.playerLookOverride!, const VehicleMods(), c.playerLookOverride!.vehicle) : PlayerRig.from(db, p);
    engine = TypingEngine(c.text.text, allowBackspace: s.backspace, foldAccents: s.foldAccents || c.text.lang == 'en');
    final tb = TauntBook((db.ai['taunts'] as Map?)?.cast<String, dynamic>() ?? {}, {for (final b in db.bosses) b.id: {'taunts': b.taunts}});
    session = RaceSession(c, engine, mods: rig.mods, playerName: p.name, playerCc: p.country, playerVehicleId: rig.vehicle.id, taunts: tb);
    session.clock = () => _sw.elapsedMilliseconds;
    RaceScreen.debugSession = session;
    final looks = <String, Look>{'player': rig.look};
    for (final o in c.opponents) {
      looks[o.id] = Look.forAi(db, o.vehicleId, o.paintId);
    }
    final ghostLook = Look.forAi(db, rig.vehicle.id, 'p_white');
    for (var i = 0; i < c.ghosts.length; i++) {
      looks['ghost$i'] = ghostLook;
    }
    final biome = db.biomeOf(c.biomeId);
    final city = c.meta['cityId'] as String?;
    final landmark = city == null ? null : db.cities.where((x) => x.id == city).firstOrNull?.landmark;
    env = EnvPainter(EnvSpec.fromBiome(biome, mod: c.mod, landmark: landmark, sky: c.meta['sky'] is List ? (c.meta['sky'] as List).map((e) => hexColor(e.toString())).toList() : null));
    game = RaceGame(
      session: session,
      env: env,
      looks: looks,
      fps30: s.fps30,
      audio: audio,
      haptics: ref.read(hapticsProvider),
      onEvents: _onEvents,
    );
    final horn = db.skin(p.loadout(rig.vehicle.id)['horn'] as String? ?? '');
    if (horn != null) {
      audio.setHorn(((horn.params['seq'] as List?) ?? const []).map((e) => (e as List).map((x) => x as num).toList()).toList(), (horn.params['wave'] as String?) ?? 'saw');
    } else {
      audio.setHorn(null, 'saw');
    }
    ref.read(hapticsProvider).keys = false;
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _hud?.cancel();
    _storm?.cancel();
    _tauntTimer?.cancel();
    audio.stopEngine();
    audio.stopMusic();
    input.dispose();
    focus.dispose();
    tick.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      if (phase == _Phase.racing && !_paused) {
        setState(() => _paused = true);
        _sw.stop();
        game.frozen = true;
        audio.pauseAll();
      }
    }
  }

  // ------------------------------------------------------------------ flow
  Future<void> _start() async {
    if (phase != _Phase.lobby) return;
    if (riskOn) {
      final c = widget.config;
      _setup(RaceConfig(modeId: c.modeId, title: c.title, text: c.text, biomeId: c.biomeId, mod: c.mod, opponents: c.opponents, ghosts: c.ghosts, rules: c.rules, riskMul: max(2.0, c.riskMul * 2), ranked: c.ranked, rewards: c.rewards, meta: c.meta, vocabHints: c.vocabHints, timeLimitMs: c.timeLimitMs, playerLookOverride: c.playerLookOverride, bossId: c.bossId));
    }
    setState(() {
      phase = _Phase.countdown;
      countdown = 3;
    });
    _focusInput();
    for (var n = 3; n >= 1; n--) {
      if (_disposed) return;
      setState(() => countdown = n);
      audio.play(Sfx.beep);
      await Future<void>.delayed(const Duration(milliseconds: 850));
    }
    if (_disposed) return;
    setState(() {
      countdown = 0;
      phase = _Phase.racing;
    });
    _sw
      ..reset()
      ..start();
    session.start();
    _wordStartMs = 0;
    audio.startEngine();
    if (cfg.mod == 'storm') {
      _storm = Timer.periodic(const Duration(milliseconds: 60), (_) {
        if (!_disposed && phase == _Phase.racing) {
          setState(() => _stormShake = Offset((_rnd.nextDouble() - 0.5) * 5, (_rnd.nextDouble() - 0.5) * 4));
        }
      });
    }
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!_disposed && countdown == 0 && phase == _Phase.racing) setState(() => countdown = -1);
    });
  }

  void _focusInput() {
    focus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _onInput(String v) {
    if (phase != _Phase.racing || _paused) {
      input.value = const TextEditingValue(text: _guard, selection: TextSelection.collapsed(offset: 2));
      return;
    }
    if (v.length < _guard.length) {
      for (var i = 0; i < _guard.length - v.length; i++) {
        session.onBackspace();
      }
    } else if (v.length > _guard.length) {
      var added = v.substring(_guard.length).replaceAll('\u200B', '');
      if (added.length > 3) {
        _bulkInputs++; // paste / gesture typing: only the first characters count
        added = added.substring(0, 1);
      }
      for (final ch in added.split('')) {
        _typeChar(ch);
      }
    }
    input.value = const TextEditingValue(text: _guard, selection: TextSelection.collapsed(offset: 2));
    if (mounted) setState(() {});
  }

  void _typeChar(String ch) {
    final before = engine.pos;
    final res = session.onChar(ch);
    if (res == KeyResult.correct) {
      audio.play(Sfx.click, vol: 0.5);
      if (session.challenge == null && engine.pos > 0 && engine.pos <= engine.length && engine.text[engine.pos - 1] == ' ' && engine.pos != before) {
        _wordStartMs = session.timeMs;
      }
    }
  }

  void _onEvents(List<RaceEvent> events) {
    if (_disposed) return;
    for (final e in events) {
      switch (e.type) {
        case RaceEventType.comboTier:
          _popup('COMBO x${e.value.toInt()}', C.gold);
          break;
        case RaceEventType.nitroStart:
          _popup('🔥 NITRO!', C.cyan);
          break;
        case RaceEventType.perfectWord:
          _popup('✨ كلمة مثالية', C.gold);
          break;
        case RaceEventType.pitPrompt:
          _popup('🔧 نقطة صيانة!', C.green);
          break;
        case RaceEventType.pitSuccess:
          _popup('🔧 صيانة مثالية! +نيترو', C.green);
          break;
        case RaceEventType.pitFail:
          _popup('🔧 صيانة بطيئة!', C.red);
          break;
        case RaceEventType.powerPrompt:
          _popup('⚡ اكتب الكلمة!', C.cyan);
          break;
        case RaceEventType.powerSuccess:
          _popup(const {'shield': '🛡️ درع!', 'emp': '📡 EMP!', 'turbo': '🚀 توربو!', 'dodge': '✅ تفاديت الهجوم'}[e.text] ?? '⚡', C.cyan);
          break;
        case RaceEventType.powerFail:
          _popup('فاتتك الفرصة', C.textDim);
          break;
        case RaceEventType.shieldBlocked:
          _popup('🛡️ الدرع حماك!', C.cyan);
          break;
        case RaceEventType.stunned:
          _popup('📡 تعطّل ${e.who}', C.cyan);
          break;
        case RaceEventType.overtake:
          _popup('تجاوزت ${e.who}', C.green);
          break;
        case RaceEventType.overtaken:
          _popup('${e.who} تجاوزك', C.red);
          break;
        case RaceEventType.incoming:
          _popup('⚠️ هجوم من ${e.who}!', C.red);
          break;
        case RaceEventType.hit:
          _popup('💥 أصابك ${e.who}', C.red);
          break;
        case RaceEventType.rocket:
          _popup('🚀 إصابة ${e.who}', C.gold);
          break;
        case RaceEventType.kill:
          _popup('☠️ دُمّر ${e.who}!', C.gold);
          break;
        case RaceEventType.slipstreamOn:
          _popup('💨 Slipstream', C.textDim);
          break;
        case RaceEventType.taunt:
          setState(() => taunt = (who: e.who ?? '', text: e.text ?? ''));
          _tauntTimer?.cancel();
          _tauntTimer = Timer(const Duration(milliseconds: 2600), () {
            if (mounted) setState(() => taunt = null);
          });
          break;
        case RaceEventType.finish:
          if (e.who == 'player') _onPlayerFinished();
          break;
        default:
          break;
      }
    }
  }

  void _popup(String text, Color color) {
    final p = _Popup(_popupId++, text, color);
    setState(() {
      popups.add(p);
      if (popups.length > 3) popups.removeAt(0);
    });
    Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => popups.remove(p));
    });
  }

  Future<void> _onPlayerFinished() async {
    if (phase == _Phase.finishing) return;
    setState(() => phase = _Phase.finishing);
    audio.stopEngine();
    _sw.stop();
    _storm?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    // let the session finalize (ranking + photo finish flag) on its next update
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (_disposed) return;
    if (session.photoFinish && cfg.opponents.isNotEmpty) {
      setState(() => photoReplay = true);
      game.onReplayDone = () {
        if (mounted) _toResults();
      };
      game.startReplay();
      audio.play(Sfx.whoosh, vol: 0.5);
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      if (!_disposed) _toResults();
    }
  }

  Future<void> _toResults() async {
    if (_done || _disposed) return;
    _done = true;
    final res = session.buildResult();
    final suspicious = _bulkInputs > 0 || AntiCheatLocal.isSuspicious(res.intervals, res.wpm);
    final result = suspicious
        ? RaceResult(config: res.config, standings: res.standings, playerRank: res.playerRank, wpm: res.wpm, rawWpm: res.rawWpm, accuracy: res.accuracy, time: res.time, maxCombo: res.maxCombo, errors: res.errors, chars: res.chars, nitroUses: res.nitroUses, perfectWords: res.perfectWords, powerupsUsed: res.powerupsUsed, pitPerfect: res.pitPerfect, photoFinish: res.photoFinish, timeUp: res.timeUp, suspicious: true, intervals: res.intervals, samples: res.samples, charStats: res.charStats, wordStats: res.wordStats)
        : res;
    final db = ref.read(contentProvider);
    late RaceOutcome outcome;
    final ctl = ref.read(profileProvider.notifier);
    ctl.update((p) {
      outcome = RaceRewards.apply(p, result, db, earningsMul: rig.mods.earnings);
    });
    if (!result.suspicious && result.chars >= RaceRewards.minCharsForStats && cfg.modeId != 'lesson') {
      ref.read(storeProvider).saveGhostIfBetter('${cfg.text.id}|${cfg.text.lang}', result.wpm, result.samples).then((v) => outcome.newGhost = v);
    }
    unawaited(ctl.syncNow());
    if (!mounted) return;
    Widget? next;
    if (widget.onFinished != null) next = await widget.onFinished!(context, result, outcome);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => next ?? ResultScreen(result: result, outcome: outcome, rebuild: widget.rebuild),
    ));
  }

  Future<bool> _confirmQuit() async {
    if (phase == _Phase.lobby) return true;
    final wasFrozen = game.frozen;
    final wasRunning = _sw.isRunning;
    _sw.stop();
    game.frozen = true;
    final ok = await confirmDialog(context, 'إنهاء السباق؟', 'إن خرجت الآن فلن تحصل على أي مكافآت.', ok: 'خروج', cancel: 'متابعة', okColor: C.red);
    game.frozen = wasFrozen;
    if (wasRunning && !ok) _sw.start();
    if (!ok && mounted) _focusInput();
    return ok;
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final pal = TypingPalette.forMode(s.colorBlind);
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmQuit() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: C.bg,
        body: SafeArea(
          child: Stack(children: [
            Column(children: [
              _topBar(),
              _progressStrip(),
              Expanded(flex: 5, child: _trackArea()),
              Expanded(flex: 4, child: _textArea(s, pal, kb)),
            ]),
            // hidden input capturing the keyboard
            Positioned(
              left: 0,
              top: 0,
              width: 2,
              height: 2,
              child: Opacity(
                opacity: 0.01,
                child: TextField(
                  controller: input,
                  focusNode: focus,
                  autofocus: false,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.none,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 1, color: Colors.transparent),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                  onChanged: _onInput,
                ),
              ),
            ),
            if (phase == _Phase.lobby) _lobby(),
            if (phase == _Phase.countdown || (phase == _Phase.racing && countdown >= 0)) _countdownOverlay(),
            if (photoReplay) _photoOverlay(),
            if (_paused) _pausedOverlay(),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() => SizedBox(
        height: 46,
        child: ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (_, _, _) {
            final t = session.time;
            final wpm = engine.rollingWpm(session.timeMs, windowMs: 5000);
            final left = cfg.timeLimitMs == null ? null : max(0, cfg.timeLimitMs! / 1000 - t);
            return Row(children: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () async {
                  if (await _confirmQuit() && mounted) Navigator.of(context).pop();
                },
              ),
              Expanded(child: Text(cfg.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14), overflow: TextOverflow.ellipsis)),
              _stat(left != null ? '⏱ ${left.toStringAsFixed(0)}s' : '⏱ ${t.toStringAsFixed(1)}s', C.textDim),
              _stat('${wpm.round()} WPM', C.cyan, big: true),
              _stat('${engine.accuracy.toStringAsFixed(0)}%', engine.accuracy >= 95 ? C.green : (engine.accuracy >= 85 ? C.gold : C.red)),
              const SizedBox(width: 8),
            ]);
          },
        ),
      );

  Widget _stat(String t, Color c, {bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t, textDirection: TextDirection.ltr, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: big ? 17 : 13, fontFamily: 'FiraMono')),
      );

  Widget _progressStrip() => SizedBox(
        height: 30,
        child: ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (_, _, _) => CustomPaint(size: const Size(double.infinity, 30), painter: _StripPainter(session)),
        ),
      );

  Widget _trackArea() => Stack(children: [
        Positioned.fill(child: GameWidget(game: game)),
        // nitro meter + combo
        Positioned(
          left: 10,
          top: 8,
          right: 10,
          child: ValueListenableBuilder<int>(
            valueListenable: tick,
            builder: (_, _, _) {
              final mult = comboMultiplier(engine.combo);
              return Row(textDirection: TextDirection.ltr, children: [
                if (cfg.rules.nitro && !cfg.rules.pure)
                  Expanded(
                    child: Row(children: [
                      Icon(Icons.local_fire_department_rounded, size: 16, color: session.nitroActive ? C.cyan : C.textDim),
                      const SizedBox(width: 4),
                      Expanded(child: ProgressBar(value: session.nitroMeter / 100, color: session.nitroActive ? C.cyan : C.magenta, height: 7)),
                    ]),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 12),
                if (engine.combo >= 10)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.gold)),
                    child: Text('x$mult  ${engine.combo}', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w900, fontFamily: 'FiraMono')),
                  ),
                if (session.riskBadge(cfg)) ...[const SizedBox(width: 8), const Text('🎲 x2', style: TextStyle(fontWeight: FontWeight.w900))],
              ]);
            },
          ),
        ),
        // popups
        Positioned(
          left: 0,
          right: 0,
          top: 38,
          child: IgnorePointer(
            child: Column(children: [
              for (final p in popups)
                TweenAnimationBuilder<double>(
                  key: ValueKey(p.id),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1200),
                  builder: (_, v, _) => Opacity(
                    opacity: (1 - v * v).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -16 * v),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                        child: Text(p.text, style: TextStyle(color: p.color, fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        // AI chatter (always labelled as AI)
        if (taunt != null)
          Positioned(
            right: 10,
            bottom: 8,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
              child: Text('🤖 ${taunt!.who}: ${taunt!.text}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
      ]);

  Widget _textArea(GameSettings s, TypingPalette pal, double kb) {
    return GestureDetector(
      onTap: _focusInput,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(color: const Color(0xFF0F1530), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
        child: ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (_, _, _) {
            final hint = cfg.vocabHints == null ? null : cfg.vocabHints![_wordIndex()];
            return Stack(children: [
              Transform.translate(
                offset: cfg.mod == 'storm' && phase == _Phase.racing ? _stormShake : Offset.zero,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Directionality(textDirection: TextDirection.rtl, child: Text('المعنى: $hint', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800, fontSize: 14))),
                      ),
                    Expanded(
                      child: TypingTextPanel(
                        engine: engine,
                        palette: pal,
                        mod: cfg.mod,
                        fontScale: s.fontScale,
                        dyslexia: s.dyslexia,
                        hint: s.nextCharHint,
                        nowMs: session.timeMs,
                        wordStartMs: _wordStartMs,
                        hideAll: phase == _Phase.lobby || phase == _Phase.countdown,
                      ),
                    ),
                  ]),
                ),
              ),
              if (session.challenge != null) _challengeCard(session.challenge!),
              if (phase == _Phase.racing && kb == 0 && !_paused)
                Positioned.fill(
                  child: Container(
                    color: C.bg.withValues(alpha: 0.75),
                    alignment: Alignment.center,
                    child: const Text('اضغط لإظهار لوحة المفاتيح ⌨️', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }

  int _wordIndex() {
    var n = 0;
    final t = engine.text;
    for (var i = 0; i < engine.pos && i < t.length; i++) {
      if (t[i] == ' ') n++;
    }
    return n;
  }

  Widget _challengeCard(Challenge c) {
    final label = switch (c.kind) { ChallengeKind.shield => '🛡️ درع — اكتب الكلمة', ChallengeKind.emp => '📡 EMP — عطّل منافساً', ChallengeKind.turbo => '🚀 توربو — اكتب بسرعة', ChallengeKind.pit => '🔧 نقطة صيانة — بدون أي خطأ!', ChallengeKind.defend => '🎯 هجوم قادم — تفادَ بسرعة!' };
    final color = c.isPit ? C.green : (c.kind == ChallengeKind.defend ? C.red : C.cyan);
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(color: const Color(0xEE0B1026), borderRadius: BorderRadius.circular(14), border: Border.all(color: color, width: 2)),
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: RichText(
              text: TextSpan(style: const TextStyle(fontFamily: 'FiraMono', fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3), children: [
                TextSpan(text: c.word.substring(0, c.typed), style: const TextStyle(color: C.green)),
                TextSpan(text: c.word.substring(c.typed), style: const TextStyle(color: Colors.white)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          ProgressBar(value: (c.left / c.timeLimit).clamp(0, 1), color: color, height: 6),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ overlays
  Widget _lobby() {
    final db = ref.read(contentProvider);
    final biome = db.biomeOf(cfg.biomeId);
    final vehicle = rig.vehicle;
    final canRisk = cfg.rules.penalties && cfg.rewards && cfg.opponents.isNotEmpty && !cfg.rules.pure;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const SizedBox(height: 20),
            Text(cfg.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${loc(biome.name)}${cfg.mod != 'none' ? '  •  ${_modLabel(cfg.mod)}' : ''}', style: const TextStyle(color: C.textDim)),
            const SizedBox(height: 12),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.directions_car_filled_rounded, color: C.cyan),
                  const SizedBox(width: 8),
                  Expanded(child: Text(loc(vehicle.name), style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text('${cfg.text.len} حرف • صعوبة ${cfg.text.diff}/5', style: const TextStyle(color: C.textDim, fontSize: 12)),
                ]),
                if (cfg.opponents.isNotEmpty || cfg.ghosts.isNotEmpty) ...[
                  const Divider(color: Colors.white12),
                  for (final o in cfg.opponents)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Text(flagEmoji(o.cc), style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${o.isBoss ? '👑 ' : ''}${o.name}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text(Persona.label(o.persona), style: const TextStyle(color: C.textDim, fontSize: 11)),
                        const SizedBox(width: 8),
                        _aiBadge(),
                      ]),
                    ),
                  for (final g in cfg.ghosts)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [const Text('👻', style: TextStyle(fontSize: 18)), const SizedBox(width: 8), Expanded(child: Text(g.name)), Text('${g.wpm.round()} WPM', style: const TextStyle(color: C.textDim, fontSize: 12))])),
                  const SizedBox(height: 6),
                  const Text('جميع المنافسين ذكاء اصطناعي — لا يوجد لاعبون حقيقيون في السباقات.', style: TextStyle(color: C.textDim, fontSize: 11)),
                ],
              ]),
            ),
            if (canRisk) ...[
              const SizedBox(height: 10),
              Panel(
                child: Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: riskOn,
                  onChanged: (v) => setState(() => riskOn = v),
                  title: const Text('🎲 مضاعف المخاطرة x2', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('مكافآت مضاعفة، لكن كل خطأ يبطئك أكثر ويصفّر النيترو.', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            NeonButton(label: 'ابدأ السباق', icon: Icons.flag_rounded, onPressed: _start),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('رجوع')),
          ]),
        ),
      ),
    );
  }

  String _modLabel(String m) => const {'fog': 'ضباب', 'ice': 'جليد', 'blackout': 'انقطاع الإضاءة', 'storm': 'عاصفة'}[m] ?? '';

  Widget _aiBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.cyan.withValues(alpha: 0.5))),
        child: const Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: C.cyan)),
      );

  Widget _countdownOverlay() {
    final go = countdown == 0;
    if (!go && countdown < 1) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(countdown),
            tween: Tween(begin: 1.6, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (_, v, _) => Transform.scale(
              scale: v,
              child: Text(go ? 'انطلق!' : '$countdown', style: TextStyle(fontSize: 88, fontWeight: FontWeight.w900, color: go ? C.green : C.gold, shadows: const [Shadow(blurRadius: 24, color: Colors.black)])),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoOverlay() => Positioned.fill(
        child: IgnorePointer(
          child: Container(
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 90),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.gold, width: 2)),
                child: const Text('📸 PHOTO FINISH', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: C.gold, fontSize: 20)),
              ),
              const SizedBox(height: 6),
              const Text('إعادة بطيئة', style: TextStyle(color: Colors.white70)),
            ]),
          ),
        ),
      );

  Widget _pausedOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.8),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⏸ السباق متوقف', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            SizedBox(
              width: 220,
              child: NeonButton(
                label: 'متابعة',
                icon: Icons.play_arrow_rounded,
                onPressed: () {
                  setState(() => _paused = false);
                  _sw.start();
                  game.frozen = false;
                  audio.resumeAll();
                  _focusInput();
                },
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async {
                if (await _confirmQuit() && mounted) Navigator.of(context).pop();
              },
              child: const Text('إنهاء السباق', style: TextStyle(color: C.red)),
            ),
          ]),
        ),
      );
}

/// Top strip: every racer as a dot along the track; the player's dot is bigger.
class _StripPainter extends CustomPainter {
  final RaceSession s;
  _StripPainter(this.s);
  @override
  void paint(Canvas canvas, Size size) {
    const pad = 22.0;
    final w = size.width - pad * 2, y = size.height / 2;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(pad, y - 2, w, 4), const Radius.circular(2)), Paint()..color = Colors.white12);
    final pf = s.fractionOf(s.player);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(pad, y - 2, w * pf, 4), const Radius.circular(2)), Paint()..color = C.cyan);
    canvas.drawRect(Rect.fromLTWH(pad + w - 2, y - 9, 3, 18), Paint()..color = Colors.white);
    for (final r in s.racers) {
      if (r.isPlayer) continue;
      final f = s.fractionOf(r);
      final c = r.isGhost ? Colors.white54 : (r.spec?.isBoss == true ? C.gold : C.magenta.withValues(alpha: 0.85));
      canvas.drawCircle(Offset(pad + w * f, y), 5, Paint()..color = c);
    }
    canvas.drawCircle(Offset(pad + w * pf, y), 8, Paint()..color = C.cyan);
    canvas.drawCircle(Offset(pad + w * pf, y), 8, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _StripPainter old) => true;
}

/// Client-side plausibility checks (the server repeats them for leaderboard submissions).
class AntiCheatLocal {
  static bool isSuspicious(List<int> intervals, double wpm) {
    if (intervals.length < 30) return false;
    if (wpm > 260) return true;
    final fast = intervals.where((i) => i < 25).length;
    if (fast > intervals.length * 0.25) return true;
    final m = meanOf(intervals);
    if (m > 0 && stdDevOf(intervals) < m * 0.04 && intervals.length > 60) return true; // robotic timing
    return false;
  }
}
