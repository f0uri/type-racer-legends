import 'dart:math';
import 'dart:ui';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, TextDirection, FontWeight, HSVColor;
import '../../../core/services/audio_service.dart';
import '../../../core/services/haptics_service.dart';
import '../../garage/look.dart';
import '../../garage/vehicle_painter.dart';
import '../engine/race_session.dart';
import 'env_painter.dart';
import 'particles.dart';

class _Vis {
  double wheel = 0;
  double x = 0;
  double afterFinish = 0;
  double wobble = 0;
  Picture? body;
  double bodyL = 0;
  double flicker = 0;
}

/// Flame game that renders the race (parallax environment, vehicles, effects) from a [RaceSession].
/// The session is advanced here so simulation and rendering stay in lock-step (fixed 60 fps or 30 fps mode).
class RaceGame extends FlameGame {
  RaceGame({required this.session, required this.env, required this.looks, this.fps30 = false, this.audio, this.haptics, this.weatherIntensity = 1.0, this.onEvents, this.hintWpmScale = 1.0});

  final RaceSession session;
  final EnvPainter env;
  final Map<String, Look> looks;
  final bool fps30;
  final AudioService? audio;
  final Haptics? haptics;
  final double weatherIntensity;
  final void Function(List<RaceEvent> events)? onEvents;
  final double hintWpmScale;

  final ParticleSystem particles = ParticleSystem(520);
  final Map<String, _Vis> _vis = {};
  final Random _rnd = Random();
  Size _size = const Size(360, 240);

  double sceneT = 0;
  double camX = 0;
  double _dist = 0;
  double scrollSpeed = 140;
  double speed01 = 0;
  double nitroFx = 0, turboFx = 0, slipFx = 0, shieldFx = 0, shake = 0, flash = 0;
  double _playerX = 100;
  double _accum = 0;
  Picture? _lastFrame;
  bool _skipRender = false;
  double timeScale = 1;

  // replay (photo finish)
  bool replaying = false;
  double _replayPos = 0;
  int _replayLen = 0;
  VoidCallback? onReplayDone;
  bool frozen = false;

  Offset get playerScreenPos => Offset(_playerX, _size.height * EnvPainter.lanes[2]);

  @override
  Color backgroundColor() => const Color(0xFF0B0F1E);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _size = Size(size.x, size.y);
    _playerX = size.x * 0.3;
    for (final v in _vis.values) {
      v.body = null;
    }
  }

  _Vis _v(String id) => _vis.putIfAbsent(id, _Vis.new);

  // ------------------------------------------------------------------ update
  @override
  void update(double dt) {
    super.update(dt);
    if (frozen) return;
    dt = min(dt, 1 / 20) * timeScale;
    if (fps30) {
      _accum += dt;
      _skipRender = !_skipRender;
      if (_accum < 1 / 31) return;
      dt = _accum;
      _accum = 0;
    }
    sceneT += dt;
    if (replaying) {
      _updateReplay(dt);
      particles.update(dt);
      return;
    }
    final s = session;
    s.update(dt);
    final events = s.drainEvents();
    if (events.isNotEmpty) {
      _handle(events);
      onEvents?.call(events);
    }
    final p = s.player;
    final cps = s.started ? p.speedCps : 0.0;
    final targetSpeed = s.started ? 150 + cps * 40 + (s.nitroActive ? 140 : 0) + (s.turboLeft > 0 ? 100 : 0) : 40;
    scrollSpeed += (targetSpeed - scrollSpeed) * min(1, dt * 3);
    if (p.finished && s.over) scrollSpeed += (90 - scrollSpeed) * min(1, dt * 1.5);
    speed01 = ((scrollSpeed - 40) / 360).clamp(0.0, 1.0);
    _dist += scrollSpeed * dt;
    camX = _dist;
    nitroFx += ((s.nitroActive ? 1 : 0) - nitroFx) * min(1, dt * 4);
    turboFx += ((s.turboLeft > 0 ? 1 : 0) - turboFx) * min(1, dt * 5);
    slipFx += ((s.slipstream ? 1 : 0) - slipFx) * min(1, dt * 4);
    shieldFx += ((p.shielded ? 1 : 0) - shieldFx) * min(1, dt * 6);
    shake = max(0, shake - dt * 3.2);
    flash = max(0, flash - dt * 3);
    final targetX = _size.width * (0.27 + 0.07 * nitroFx + 0.03 * speed01 + 0.03 * turboFx);
    _playerX += (targetX - _playerX) * min(1, dt * 3);
    audio?.engineSpeed(speed01 + nitroFx * 0.25);

    for (final r in s.racers) {
      final v = _v(r.id);
      final vr = r.isPlayer ? scrollSpeed : 140 + r.speedCps * 40;
      v.wheel += vr * dt / 18;
      if (r.finished) v.afterFinish += dt;
      v.wobble = max(0, v.wobble - dt * 2.5);
      v.flicker = r.stunLeft > 0 ? v.flicker + dt : 0;
    }
    _emitEffects(dt);
    particles.update(dt);
  }

  void _handle(List<RaceEvent> events) {
    final pp = playerScreenPos;
    for (final e in events) {
      switch (e.type) {
        case RaceEventType.keyWrong:
          shake = max(shake, 0.35);
          _v('player').wobble = 1;
          particles.burst(PKind.spark, pp.dx + 20, pp.dy - 28, 7, speed: 120, colors: const [Color(0xFFFF4D6D), Color(0xFFFFB3C1)], life: 0.35, size: 2.5);
          audio?.play(Sfx.wrong);
          haptics?.wrong();
          break;
        case RaceEventType.comboTier:
          final tier = e.value.toInt().clamp(2, 6);
          particles.burst(PKind.star, pp.dx + 30, pp.dy - 46, 8 + tier * 2, speed: 90, colors: const [Color(0xFFFFD166), Color(0xFFFFFFFF), Color(0xFF7DF9FF)], life: 0.8, size: 4, g: 60);
          audio?.play(Sfx.values[Sfx.combo2.index + tier - 2]);
          haptics?.combo();
          break;
        case RaceEventType.nitroStart:
          flash = 0.5;
          shake = max(shake, 0.5);
          audio?.play(Sfx.whoosh);
          haptics?.nitro();
          break;
        case RaceEventType.perfectWord:
          particles.burst(PKind.star, pp.dx + 10, pp.dy - 60, 10, speed: 70, colors: const [Color(0xFFFFD166), Color(0xFFFFF3B0)], life: 0.9, size: 4, g: -20);
          audio?.play(Sfx.ding);
          break;
        case RaceEventType.pitPrompt:
        case RaceEventType.powerPrompt:
          audio?.play(Sfx.pit);
          break;
        case RaceEventType.pitSuccess:
        case RaceEventType.powerSuccess:
          particles.burst(PKind.ring, pp.dx + 30, pp.dy - 30, 3, speed: 0, life: 0.6, size: 30, colors: const [Color(0xFF7DF9FF)]);
          audio?.play(Sfx.power);
          break;
        case RaceEventType.pitFail:
        case RaceEventType.powerFail:
          shake = max(shake, 0.25);
          break;
        case RaceEventType.bump:
          shake = max(shake, 0.6);
          particles.burst(PKind.spark, pp.dx + 60, pp.dy - 20, 12, speed: 160, colors: const [Color(0xFFFFD166), Color(0xFFFFFFFF)], life: 0.4, size: 2.5);
          audio?.play(Sfx.thump, vol: 0.6);
          haptics?.light();
          break;
        case RaceEventType.stunned:
          final target = session.racers.where((r) => r.name == e.who).firstOrNull;
          if (target != null) {
            final x = _screenX(target);
            particles.burst(PKind.spark, x + 30, _laneY(target) - 30, 14, speed: 140, colors: const [Color(0xFF7DF9FF), Color(0xFFFFFFFF)], life: 0.5, size: 3);
            particles.burst(PKind.ring, x + 30, _laneY(target) - 30, 3, speed: 0, life: 0.7, size: 26, colors: const [Color(0xFF7DF9FF)]);
          }
          break;
        case RaceEventType.shieldBlocked:
          particles.burst(PKind.ring, pp.dx + 30, pp.dy - 30, 3, speed: 0, life: 0.5, size: 34, colors: const [Color(0xFF4CC9F0)]);
          break;
        case RaceEventType.finish:
          if (e.who == 'player') {
            _celebrate();
            audio?.play(Sfx.fanfare);
            haptics?.finish();
          }
          break;
        case RaceEventType.go:
          audio?.play(Sfx.go);
          break;
        default:
          break;
      }
    }
  }

  void _celebrate() {
    final look = looks['player'];
    final pp = playerScreenPos;
    final cols = look?.celebrationColors ?? const [Color(0xFFFF006E), Color(0xFFFFBE0B), Color(0xFF3A86FF)];
    switch (look?.celebration ?? 'confetti') {
      case 'fireworks':
        for (var i = 0; i < 4; i++) {
          final cx = _size.width * (0.25 + 0.15 * i), cy = _size.height * (0.15 + 0.12 * (i % 2));
          particles.burst(PKind.spark, cx, cy, 36, speed: 170, colors: cols, life: 1.2, size: 3, g: 120);
        }
        break;
      case 'flags':
        particles.burst(PKind.confetti, _size.width * 0.5, -10, 70, speed: 60, colors: const [Color(0xFF111111), Color(0xFFFFFFFF)], life: 2.5, size: 6, g: 80, spread: 3.14, angle: 1.57);
        break;
      case 'lightning':
        flash = 1;
        particles.burst(PKind.spark, pp.dx + 30, pp.dy - 30, 40, speed: 260, colors: cols, life: 0.6, size: 3, g: 0);
        break;
      case 'smoke':
      case 'donut':
        particles.burst(PKind.smoke, pp.dx + 10, pp.dy - 8, 40, speed: 70, colors: cols, life: 1.6, size: 10, g: -25, spread: 3.14, angle: 3.14);
        break;
      case 'wheelie':
        _v('player').wobble = 2;
        particles.burst(PKind.star, pp.dx + 30, pp.dy - 50, 24, speed: 120, colors: cols, life: 1.2, size: 4, g: 60);
        break;
      default:
        particles.burst(PKind.confetti, _size.width * 0.5, -10, 90, speed: 80, colors: cols, life: 2.6, size: 6, g: 100, spread: 3.14, angle: 1.57);
        particles.burst(PKind.confetti, pp.dx + 30, pp.dy - 40, 40, speed: 160, colors: cols, life: 1.8, size: 5, g: 160, spread: 3.14, angle: -1.57);
    }
  }

  void _emitEffects(double dt) {
    final s = session;
    final look = looks['player'];
    if (look == null) return;
    final pp = playerScreenPos;
    final L = _lenOf(look, 2);
    final ex = VehiclePainter.exhaustAnchor(look, L);
    final ox = pp.dx + ex.dx, oy = pp.dy + ex.dy;
    final intensity = (speed01 * 0.8 + nitroFx);
    if (s.started && _rnd.nextDouble() < dt * (20 + 50 * intensity)) {
      final back = -scrollSpeed * 0.8 - 40;
      switch (look.exhaustEffect) {
        case 'fire':
          particles.emit(PKind.dot, ox, oy, back, (_rnd.nextDouble() - 0.5) * 30, 0.35, 3.5, _rnd.nextBool() ? const Color(0xFFFF9E00) : const Color(0xFFFF4D00));
          break;
        case 'sparks':
          particles.emit(PKind.spark, ox, oy, back, (_rnd.nextDouble() - 0.6) * 90, 0.45, 2.5, look.exhaustColor, g: 160);
          break;
        case 'electric':
          particles.emit(PKind.spark, ox, oy, back, (_rnd.nextDouble() - 0.5) * 140, 0.3, 2.5, const Color(0xFF7DF9FF));
          break;
        case 'bubbles':
          particles.emit(PKind.ring, ox, oy, back * 0.6, -20 - _rnd.nextDouble() * 30, 0.9, 6, const Color(0xFFB8F2FF));
          break;
        case 'rainbow':
          particles.emit(PKind.dot, ox, oy, back, (_rnd.nextDouble() - 0.5) * 20, 0.6, 4, HSVColor.fromAHSV(1, (sceneT * 240) % 360, 0.9, 1).toColor());
          break;
        case 'stars':
          particles.emit(PKind.star, ox, oy, back * 0.8, (_rnd.nextDouble() - 0.5) * 40, 0.8, 3.5, const Color(0xFFFFD166));
          break;
        default:
          particles.emit(PKind.smoke, ox, oy, back * 0.6, -10 - _rnd.nextDouble() * 20, 0.7, 4, const Color(0xFFB0B7C3));
      }
    }
    if (nitroFx > 0.3 && _rnd.nextDouble() < dt * 60) {
      final c = look.flameColors.isEmpty ? const Color(0xFF7DF9FF) : look.flameColors[_rnd.nextInt(look.flameColors.length)];
      particles.emit(PKind.spark, ox - 6, oy, -scrollSpeed * 1.2 - 100, (_rnd.nextDouble() - 0.5) * 70, 0.35, 3, c);
    }
    // weather splashes
    if (session.config.modeId != 'lesson' && env.spec.weather == 'rain' && _rnd.nextDouble() < dt * 20) {
      particles.emit(PKind.dot, _rnd.nextDouble() * _size.width, _size.height * (0.72 + 0.26 * _rnd.nextDouble()), 0, -25, 0.25, 1.6, const Color(0x99C8E1FF));
    }
    // dust trail for deserts / snow spray
    if ((env.spec.biome == 'desert' || env.spec.biome == 'snow') && s.started && _rnd.nextDouble() < dt * 25 * speed01) {
      particles.emit(PKind.smoke, pp.dx + 6, pp.dy - 2, -scrollSpeed * 0.5, -15, 0.7, 3, env.spec.biome == 'desert' ? const Color(0xFFE9C89A) : const Color(0xFFFFFFFF));
    }
  }

  // ------------------------------------------------------------------ geometry helpers
  double _laneOf(String id, int index) {
    if (id == 'player') return 2;
    return index.isEven ? 1 : 0;
  }

  double _pxPerFrac() => _size.width * 5.0 * (1 - 0.1 * nitroFx);

  double _screenX(RacerState r) {
    final rel = (r.eff - session.player.eff) / max(1, session.total);
    final v = _v(r.id);
    var x = _playerX + rel * _pxPerFrac();
    if (r.finished) x += v.afterFinish * (r.isPlayer ? 120 : 160) * (1 + v.afterFinish * 0.4);
    return x;
  }

  int _indexOf(RacerState r) => session.racers.indexOf(r);

  double _laneY(RacerState r) {
    final lane = _laneOf(r.id, _indexOf(r)).toInt();
    return _size.height * EnvPainter.lanes[lane];
  }

  double _laneScale(int lane) => const [0.76, 0.88, 1.0][lane];

  double _lenOf(Look look, int lane) {
    final base = _size.height * 0.5 * _laneScale(lane);
    return look.vehicle.isBike ? base * 0.78 : base;
  }

  // ------------------------------------------------------------------ render
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (fps30 && _skipRender && _lastFrame != null) {
      canvas.drawPicture(_lastFrame!);
      return;
    }
    if (fps30) {
      final rec = PictureRecorder();
      final c = Canvas(rec);
      _scene(c);
      _lastFrame = rec.endRecording();
      canvas.drawPicture(_lastFrame!);
    } else {
      _scene(canvas);
    }
  }

  void _scene(Canvas c) {
    final W = _size.width, H = _size.height;
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, W, H));
    final stormShake = env.spec.mod == 'storm' ? 1.6 : 0.0;
    final amp = shake * 6 + stormShake + nitroFx * 0.8;
    if (amp > 0) c.translate((_rnd.nextDouble() - 0.5) * amp, (_rnd.nextDouble() - 0.5) * amp);
    // dynamic FOV: zoom out on nitro/turbo
    final zoom = 1 - 0.07 * nitroFx - 0.03 * turboFx;
    final focus = playerScreenPos;
    if (zoom != 1) {
      c.translate(focus.dx, focus.dy);
      c.scale(zoom);
      c.translate(-focus.dx, -focus.dy);
    }
    if (replaying) {
      _renderReplay(c);
    } else {
      env.paint(c, _size, camX, sceneT);
      _startFinishLines(c);
      _vehicles(c);
      _speedFx(c);
      particles.render(c);
      env.paintWeather(c, _size, sceneT, scrollSpeed, intensity: weatherIntensity);
    }
    env.paintOverlay(c, _size, focus + Offset(30, -H * 0.15), sceneT);
    c.restore();
    if (flash > 0) c.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..color = Color.fromRGBO(255, 255, 255, 0.35 * flash));
    if (nitroFx > 0.05) _nitroBlur(c, W, H);
  }

  void _startFinishLines(Canvas c) {
    final W = _size.width, H = _size.height;
    final startX = _playerX + 30 - _dist;
    final hz = H * EnvPainter.horizonF;
    if (startX > -40 && startX < W) {
      final p = Paint()..color = const Color(0xFFFFFFFF);
      c.drawRect(Rect.fromLTWH(startX, hz, 5, H - hz), p..color = const Color(0x99FFFFFF));
    }
    final rel = (session.total - session.player.eff) / max(1, session.total);
    final fx = _playerX + rel * _pxPerFrac() + 30;
    if (fx > -60 && fx < W + 60) _checkered(c, fx, hz, H);
  }

  void _checkered(Canvas c, double x, double hz, double H) {
    final sq = H * 0.03;
    final p = Paint();
    var row = 0;
    for (var y = hz; y < H; y += sq) {
      for (var col = 0; col < 2; col++) {
        p.color = (row + col) % 2 == 0 ? const Color(0xFFFFFFFF) : const Color(0xFF111111);
        c.drawRect(Rect.fromLTWH(x + col * sq, y, sq, sq), p);
      }
      row++;
    }
    // banner
    c.drawRect(Rect.fromLTWH(x - 2, hz - H * 0.16, 4, H * 0.16), Paint()..color = const Color(0xFFDDDDDD));
    c.drawRect(Rect.fromLTWH(x - 2 + sq * 2, hz - H * 0.16, 4, H * 0.16), Paint()..color = const Color(0xFFDDDDDD));
    c.drawRect(Rect.fromLTWH(x - 2, hz - H * 0.16, sq * 2 + 4, H * 0.04), Paint()..color = const Color(0xFFE5383B));
  }

  void _vehicles(Canvas c) {
    final s = session;
    final order = [...s.racers]..sort((a, b) {
        final la = _laneOf(a.id, _indexOf(a)), lb = _laneOf(b.id, _indexOf(b));
        return la != lb ? la.compareTo(lb) : a.eff.compareTo(b.eff);
      });
    for (final r in order) {
      final look = looks[r.id];
      if (look == null) continue;
      final lane = _laneOf(r.id, _indexOf(r)).toInt();
      final x = _screenX(r);
      final L = _lenOf(look, lane);
      if (x < -L * 1.5) continue;
      if (x > _size.width + L) {
        _offscreenArrow(c, r, lane);
        continue;
      }
      _drawRacer(c, r, look, lane, x, L);
    }
  }

  void _offscreenArrow(Canvas c, RacerState r, int lane) {
    final y = _size.height * EnvPainter.lanes[lane] - 14;
    final p = Path()
      ..moveTo(_size.width - 4, y)
      ..lineTo(_size.width - 14, y - 7)
      ..lineTo(_size.width - 14, y + 7)
      ..close();
    c.drawPath(p, Paint()..color = const Color(0xCCFFD166));
  }

  void _drawRacer(Canvas c, RacerState r, Look look, int lane, double x, double L) {
    final v = _v(r.id);
    final gy = _size.height * EnvPainter.lanes[lane];
    final isPlayer = r.isPlayer;
    final alpha = r.isGhost ? 0.45 : (v.flicker > 0 && (v.flicker * 14).floor().isEven ? 0.35 : 1.0);
    c.save();
    if (alpha < 1) c.saveLayer(Rect.fromLTWH(x - L * 0.3, gy - L * 1.2, L * 1.8, L * 1.4), Paint()..color = Color.fromRGBO(255, 255, 255, alpha));
    // pitch: lean back on nitro or celebrate wheelie
    final wb0 = ((look.vehicle.shape['wb'] as List)[0] as num).toDouble();
    final wr = ((look.vehicle.shape['wr'] as num?) ?? 0.09).toDouble();
    final pivot = Offset(x + wb0 * L, gy - wr * L);
    var pitch = isPlayer ? (nitroFx * 0.07 + (session.brake > 0 ? 0.03 : 0)) : 0.0;
    pitch += v.wobble * 0.03 * sin(sceneT * 40);
    if (isPlayer && r.finished && look.celebration == 'wheelie') pitch = 0.45 * min(1, v.afterFinish * 2);
    if (pitch != 0) {
      c.translate(pivot.dx, pivot.dy);
      c.rotate(-pitch);
      c.translate(-pivot.dx, -pivot.dy);
    }
    // ghost/dim afterimages for nitro blur
    final animated = look.shimmer || look.metallic || look.pattern == 'rainbow' || look.pattern == 'galaxy' || look.neonPulse || look.neonRainbow;
    if (isPlayer && nitroFx > 0.2) {
      for (var i = 3; i >= 1; i--) {
        c.save();
        c.translate(x - i * 14 * nitroFx, gy);
        final pic = _bodyPicture(v, look, L);
        c.saveLayer(null, Paint()..color = Color.fromRGBO(255, 255, 255, 0.16 * nitroFx / i));
        _drawBodyPic(c, pic, L);
        c.restore();
        c.restore();
      }
    }
    c.save();
    c.translate(x, gy);
    if (isPlayer && animated) {
      VehiclePainter.paint(c, look, L, layer: VLayer.body, t: sceneT, braking: session.brake > 0);
    } else {
      _drawBodyPic(c, _bodyPicture(v, look, L), L);
    }
    VehiclePainter.paint(c, look, L, layer: VLayer.wheels, wheelAngle: v.wheel);
    // nitro flame
    if (isPlayer && nitroFx > 0.05) _flame(c, look, L, nitroFx, turboFx);
    // shield bubble
    if (isPlayer && shieldFx > 0.05) {
      final h = VehiclePainter.heightOf(look) * L;
      final ctr = Offset(L * 0.5, -h * 0.5);
      c.drawOval(Rect.fromCenter(center: ctr, width: L * 1.25, height: h * 1.45), Paint()..color = Color.fromRGBO(76, 201, 240, 0.16 * shieldFx));
      c.drawOval(Rect.fromCenter(center: ctr, width: L * 1.25, height: h * 1.45), Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Color.fromRGBO(130, 226, 255, 0.7 * shieldFx));
    }
    c.restore();
    if (alpha < 1) c.restore();
    c.restore();
    _tag(c, r, x, gy, L, look);
  }

  Picture _bodyPicture(_Vis v, Look look, double L) {
    const base = 180.0;
    if (v.body == null) {
      final rec = PictureRecorder();
      final cc = Canvas(rec);
      VehiclePainter.paint(cc, look, base, layer: VLayer.body, t: 0);
      v.body = rec.endRecording();
      v.bodyL = base;
    }
    return v.body!;
  }

  void _drawBodyPic(Canvas c, Picture pic, double L) {
    c.save();
    final k = L / 180.0;
    c.scale(k);
    c.drawPicture(pic);
    c.restore();
  }

  void _flame(Canvas c, Look look, double L, double fx, double turbo) {
    final ex = VehiclePainter.exhaustAnchor(look, L);
    final cols = look.flameColors.length >= 2 ? look.flameColors : const [Color(0xFF7DF9FF), Color(0xFF2A6BFF), Color(0xFFFFFFFF)];
    final len = L * (0.35 + 0.25 * sin(sceneT * 60).abs()) * fx * (1 + turbo * 0.4);
    final w = L * 0.05;
    c.save();
    c.translate(ex.dx, ex.dy);
    final shape = look.flameShape;
    final p = Paint();
    void cone(double scale, Color col) {
      final path = Path()
        ..moveTo(0, -w * scale)
        ..quadraticBezierTo(-len * 0.5 * scale, -w * 0.4 * scale, -len * scale, 0)
        ..quadraticBezierTo(-len * 0.5 * scale, w * 0.4 * scale, 0, w * scale)
        ..close();
      c.drawPath(path, p..color = col);
    }

    switch (shape) {
      case 'dual':
        c.save();
        c.translate(0, -w * 0.9);
        cone(0.7, cols[0].withValues(alpha: 0.9));
        c.translate(0, w * 1.8);
        cone(0.7, cols[0].withValues(alpha: 0.9));
        c.restore();
        cone(0.4, cols.last);
        break;
      case 'wave':
        final path = Path()..moveTo(0, -w * 0.6);
        for (var i = 1; i <= 6; i++) {
          path.lineTo(-len * i / 6, sin(sceneT * 40 + i) * w * (1 - i / 7));
        }
        for (var i = 6; i >= 0; i--) {
          path.lineTo(-len * i / 6, w * 0.6 * (1 - i / 7) + sin(sceneT * 40 + i + 2) * w * 0.3);
        }
        c.drawPath(path, p..color = cols[0].withValues(alpha: 0.85));
        cone(0.4, cols.last);
        break;
      case 'spark':
        cone(0.55, cols[0].withValues(alpha: 0.85));
        for (var i = 0; i < 6; i++) {
          final a = (i / 6) * 2 - 1;
          c.drawLine(Offset(-len * 0.3, 0), Offset(-len * (0.7 + 0.4 * ((sceneT * 7 + i) % 1)), a * w * 3), p..style = PaintingStyle.stroke..strokeWidth = 2..color = cols[1]);
        }
        p.style = PaintingStyle.fill;
        break;
      default:
        cone(1.0, cols[0].withValues(alpha: 0.75));
        cone(0.62, cols[1 % cols.length]);
        cone(0.3, cols.last);
    }
    c.restore();
  }

  void _tag(Canvas c, RacerState r, double x, double gy, double L, Look look) {
    if (r.isPlayer) return;
    final txt = r.isGhost ? '👻 ${r.name}' : '${r.spec?.isBoss == true ? '👑 ' : ''}AI · ${r.name}';
    final tp = _tagPainter(txt, r.isGhost ? const Color(0xAAFFFFFF) : const Color(0xDDFFFFFF));
    final h = VehiclePainter.heightOf(look) * L;
    tp.paint(c, Offset(x + L * 0.5 - tp.width / 2, gy - h - tp.height - 2));
  }

  final Map<String, TextPainter> _tags = {};
  TextPainter _tagPainter(String text, Color color) => _tags.putIfAbsent('$text|${color.toARGB32()}', () {
        if (_tags.length > 60) _tags.clear();
        return TextPainter(text: TextSpan(text: text, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w700, shadows: const [Shadow(color: Color(0xFF000000), blurRadius: 3)])), textDirection: TextDirection.ltr)..layout();
      });

  void _speedFx(Canvas c) {
    final W = _size.width, H = _size.height;
    final a = (speed01 - 0.35).clamp(0.0, 1.0) * 0.5 + nitroFx * 0.6 + turboFx * 0.3;
    if (a > 0.04) {
      final p = Paint()
        ..color = Color.fromRGBO(255, 255, 255, (a * 0.5).clamp(0.0, 0.6))
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      final n = (8 + 14 * a).toInt();
      for (var i = 0; i < n; i++) {
        final seed = i * 97.13;
        final y = H * (0.05 + 0.9 * ((sin(seed) * 0.5 + 0.5)));
        final x = ((seed * 3.1 - sceneT * (900 + 600 * a)) % (W + 300)) - 100;
        final len = 40 + 90 * a * (0.4 + (seed % 7) / 7);
        c.drawLine(Offset(x, y), Offset(x + len, y), p);
      }
    }
    if (slipFx > 0.05) {
      final p = Paint()
        ..color = Color.fromRGBO(200, 240, 255, 0.4 * slipFx)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      final pp = playerScreenPos;
      for (var i = 0; i < 4; i++) {
        final y = pp.dy - 14 - i * 9;
        final off = (sceneT * 500 + i * 70) % 160;
        final path = Path()
          ..moveTo(pp.dx + 60 + off, y)
          ..quadraticBezierTo(pp.dx + 100 + off, y - 6, pp.dx + 140 + off, y);
        c.drawPath(path, p);
      }
    }
  }

  void _nitroBlur(Canvas c, double W, double H) {
    final a = 0.5 * nitroFx;
    c.drawRect(Rect.fromLTWH(0, 0, W * 0.22, H), Paint()..shader = Gradient.linear(Offset.zero, Offset(W * 0.22, 0), [Color.fromRGBO(120, 220, 255, a * 0.4), const Color(0x00000000)]));
    c.drawRect(Rect.fromLTWH(W * 0.78, 0, W * 0.22, H), Paint()..shader = Gradient.linear(Offset(W, 0), Offset(W * 0.78, 0), [Color.fromRGBO(120, 220, 255, a * 0.4), const Color(0x00000000)]));
    c.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..shader = Gradient.radial(Offset(W * 0.4, H * 0.7), W * 0.75, [const Color(0x00000000), Color.fromRGBO(0, 20, 60, a * 0.35)], [0.5, 1]));
  }

  // ------------------------------------------------------------------ photo-finish replay
  void startReplay({int frames = 54, double speed = 0.3}) {
    final any = session.history[session.player.id];
    if (any == null || any.length < 10) {
      onReplayDone?.call();
      return;
    }
    _replayLen = min(frames, any.length);
    _replayPos = (any.length - _replayLen).toDouble();
    replaying = true;
    timeScale = 1;
    _replaySpeed = speed;
    particles.clear();
  }

  double _replaySpeed = 0.3;

  void _updateReplay(double dt) {
    final any = session.history[session.player.id]!;
    _replayPos += dt * 30 * _replaySpeed;
    if (_replayPos >= any.length - 1) {
      replaying = false;
      onReplayDone?.call();
    }
  }

  void _renderReplay(Canvas c) {
    final W = _size.width, H = _size.height;
    final hz = H * EnvPainter.horizonF;
    env.paint(c, _size, camX + sceneT * 40, sceneT);
    final finishX = W * 0.68;
    _checkered(c, finishX, hz, H);
    final idx = _replayPos.floor();
    final f = _replayPos - idx;
    // zoomed x-axis: 1 fraction unit = pxPerFrac * 2.5
    final scale = _pxPerFrac() * 2.5;
    final order = [...session.racers]..sort((a, b) => _laneOf(a.id, _indexOf(a)).compareTo(_laneOf(b.id, _indexOf(b))));
    for (final r in order) {
      final look = looks[r.id];
      final h = session.history[r.id];
      if (look == null || h == null || h.isEmpty) continue;
      final i0 = idx.clamp(0, h.length - 1), i1 = (idx + 1).clamp(0, h.length - 1);
      final frac = h[i0] + (h[i1] - h[i0]) * f;
      final x = finishX + (frac - 1) * scale - _lenOf(look, 2) * 0.9;
      final lane = _laneOf(r.id, _indexOf(r)).toInt();
      final L = _lenOf(look, lane);
      final v = _v(r.id);
      v.wheel += 5;
      _drawRacer(c, r, look, lane, x, L);
    }
  }
}
