import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../garage/look.dart';
import '../garage/turntable.dart';

/// Scenery seeds.
///
/// They are generated once at load time: every frame then draws the exact same city, so nothing
/// flickers, and the paint loop allocates nothing.
final List<(double, double, double)> _stars = List.generate(44, (i) {
  final r = Random(i * 17 + 3);
  return (r.nextDouble(), r.nextDouble(), 0.35 + r.nextDouble() * 0.65);
});
final List<(double, double, double, double)> _towers = List.generate(24, (i) {
  final r = Random(i * 29 + 11);
  return (r.nextDouble(), 0.20 + r.nextDouble() * 0.48, 0.55 + r.nextDouble() * 0.75, r.nextDouble());
});
final List<(double, double, double)> _dust = List.generate(20, (i) {
  final r = Random(i * 31 + 7);
  return (r.nextDouble(), r.nextDouble(), 0.35 + r.nextDouble() * 0.9);
});
final List<(double, double, double)> _rivals = List.generate(4, (i) {
  final r = Random(i * 37 + 5);
  return (r.nextDouble(), r.nextDouble(), 0.55 + r.nextDouble() * 0.7);
});

/// The living lobby stage.
///
/// A top mobile game never shows a dead screen: the home screen has a world running in the
/// background and the player's own car standing in the middle of it, spin-able with a finger.
/// This is deliberately *not* a menu illustration — it is the real vehicle (the same painter the
/// garage and the race use), on a lit platform, inside a moving night city with traffic and dust.
class LobbyScene extends StatefulWidget {
  const LobbyScene({super.key, required this.look, this.height = 208});
  final Look look;
  final double height;

  @override
  State<LobbyScene> createState() => _LobbySceneState();
}

class _LobbySceneState extends State<LobbyScene> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _t = 0;
  double _angle = pi * 0.5;
  double _velocity = 0;
  double _idle = 0;
  bool _dragging = false;

  /// The OS 'remove animations' flag, read once: MediaQuery is not available in initState, and the
  /// platform value is the same one MediaQuery would have copied.
  late final bool _reduced;

  @override
  void initState() {
    super.initState();
    _reduced = reduceMotion(null);
    // The ticker always runs so dragging still repaints; under reduced motion it only repaints,
    // it never advances: no showroom spin, no glide after a flick, no ambient traffic.
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration d) {
    if (_last == Duration.zero) {
      _last = d;
      return;
    }
    var dt = (d - _last).inMicroseconds / 1e6;
    _last = d;
    if (dt <= 0) return;
    // clamp: after the app was paused the first delta can be seconds long, which would teleport
    // the city forward in one frame.
    dt = dt.clamp(0.0, 0.05);
    if (!_reduced) _t += dt;
    if (!_dragging) {
      if (_reduced) {
        // nothing keeps moving once the finger is gone
        _velocity = 0;
      } else if (_velocity.abs() > 0.05) {
        _angle += _velocity * dt;
        _velocity *= pow(0.04, dt).toDouble();
        _idle = 0;
      } else {
        _idle += dt;
        // idle: slow showroom rotation, so the car is never a static picture
        if (_idle > 1.2) _angle += dt * 0.5;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _dragging = true;
          _velocity = 0;
        },
        onPanUpdate: (d) {
          _angle -= d.delta.dx * 0.012;
          _velocity = -d.delta.dx * 0.012 * 36;
        },
        onPanEnd: (_) => _dragging = false,
        onPanCancel: () => _dragging = false,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: LobbyScenePainter(look: widget.look, angle: _angle, t: _t),
            isComplex: true,
            willChange: true,
          ),
        ),
      ),
    );
  }
}

/// Paints the night city, the platform and the player's car in one pass.
class LobbyScenePainter extends CustomPainter {
  LobbyScenePainter({required this.look, required this.angle, required this.t});
  final Look look;
  final double angle, t;

  /// Where the skyline meets the ground, and the platform line (same as [TurntablePainter]).
  static const double _horizon = 0.60;
  static const double _floor = 0.78;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizon = h * _horizon;
    final floorY = h * _floor;

    _sky(canvas, w, h, horizon);
    _stars_(canvas, w, horizon);
    _city(canvas, w, h, horizon);
    _traffic(canvas, w, horizon, floorY);
    _beams(canvas, w, h, floorY);
    _platform(canvas, w, floorY, h);
    TurntablePainter.paintVehicle(canvas, size, look, angle, t);
    _dust_(canvas, w, h);
    _vignette(canvas, w, h);
  }

  void _sky(Canvas c, double w, double h, double horizon) {
    c.drawRect(
      Rect.fromLTWH(0, 0, w, horizon + 2),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, horizon),
          const [Color(0xFF04060F), Color(0xFF141B42), Color(0xFF2B2159)],
          const [0.0, 0.68, 1.0],
        ),
    );
    // moon + halo
    final moon = Offset(w * 0.79, h * 0.15);
    c.drawCircle(moon, 30, Paint()..shader = ui.Gradient.radial(moon, 30, const [Color(0x55FFF3C4), Color(0x00FFF3C4)]));
    c.drawCircle(moon, 9, Paint()..color = const Color(0xFFFDF6D8));
  }

  void _stars_(Canvas c, double w, double horizon) {
    final paint = Paint();
    for (final s in _stars) {
      final twinkle = 0.5 + 0.5 * sin(t * (0.6 + s.$3) + s.$1 * 12);
      paint.color = Colors.white.withValues(alpha: 0.18 + 0.55 * twinkle * s.$3);
      c.drawCircle(Offset(s.$1 * w, s.$2 * horizon * 0.94), 0.8 + s.$3 * 0.7, paint);
    }
  }

  void _city(Canvas c, double w, double h, double horizon) {
    const speeds = [0.010, 0.020, 0.034]; // parallax per second (farthest layer barely moves)
    const fills = [Color(0xFF1C2450), Color(0xFF121838), Color(0xFF080C22)];
    const scales = [0.55, 0.78, 1.0];
    const span = 120.0;
    for (var layer = 0; layer < 3; layer++) {
      final offset = (t * speeds[layer] * w) % (w + span);
      final body = Paint()..color = fills[layer];
      for (final tower in _towers) {
        final x = (tower.$1 * (w + span) - span / 2 - offset) % (w + span) - span / 2;
        final bw = (22 + tower.$3 * 40) * scales[layer];
        final bh = tower.$2 * h * 0.34 * scales[layer];
        if (bh < 6) continue;
        c.drawRect(Rect.fromLTWH(x, horizon - bh, bw, bh + 2), body);
        // roof antenna
        c.drawRect(Rect.fromLTWH(x + bw * 0.45, horizon - bh - 6 * scales[layer], 1.4, 6 * scales[layer]), body);
        if (layer == 2) {
          // lit windows only on the closest layer: cheap, and it reads as a real skyline
          for (var k = 0; k < 3; k++) {
            final wx = x + bw * (0.2 + 0.28 * ((tower.$4 * 7 + k) % 3) / 2);
            final wy = horizon - bh * (0.30 + 0.22 * k);
            c.drawCircle(
              Offset(wx, wy),
              1.3,
              Paint()..color = (k.isEven ? C.cyan : C.magenta).withValues(alpha: 0.40),
            );
          }
        }
      }
      // a couple of neon signs hanging in the far layers
      if (layer == 1) {
        for (var i = 0; i < 2; i++) {
          final x = (w * (0.22 + 0.5 * i) - offset) % (w + span);
          c.drawRect(
            Rect.fromLTWH(x, horizon - h * 0.16 - i * 12, 3 + i * 26, 3),
            Paint()..color = (i.isEven ? C.magenta : C.cyan).withValues(alpha: 0.55),
          );
        }
      }
    }
    // ground haze so the skyline does not end in a hard line
    c.drawRect(
      Rect.fromLTWH(0, horizon - h * 0.06, w, h * 0.08),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, horizon - h * 0.06),
          Offset(0, horizon + h * 0.02),
          [C.cyan.withValues(alpha: 0.0), C.cyan.withValues(alpha: 0.12)],
        ),
    );
  }

  void _traffic(Canvas c, double w, double horizon, double floorY) {
    final laneY = horizon + (floorY - horizon) * 0.30;
    // the elevated road behind the platform
    c.drawRect(Rect.fromLTWH(0, laneY, w, 1.6), Paint()..color = C.cyan.withValues(alpha: 0.22));
    c.drawRect(Rect.fromLTWH(0, laneY + 3, w, 0.8), Paint()..color = Colors.white.withValues(alpha: 0.06));
    for (var i = 0; i < _rivals.length; i++) {
      final r = _rivals[i];
      final dir = i.isEven ? 1.0 : -1.0;
      final gap = w + 200;
      var x = (r.$1 * gap + dir * t * (0.10 + r.$2 * 0.16) * w) % gap;
      if (x < 0) x += gap;
      x -= 100;
      _passingCar(c, x, laneY, 0.7 + r.$3 * 0.55, dir);
    }
  }

  void _passingCar(Canvas c, double x, double y, double s, double dir) {
    final body = Paint()..color = const Color(0xFF04060F);
    final bw = 34 * s, bh = 9 * s;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y - bh, bw, bh), Radius.circular(3 * s)), body);
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x + bw * 0.22, y - bh - 5 * s, bw * 0.5, 5.5 * s), Radius.circular(2.5 * s)),
      body,
    );
    c.drawCircle(Offset(x + bw * 0.22, y), 2.6 * s, Paint()..color = const Color(0xFF01030A));
    c.drawCircle(Offset(x + bw * 0.8, y), 2.6 * s, Paint()..color = const Color(0xFF01030A));
    // headlight streak, pointing the way the car actually drives
    final from = dir > 0 ? x + bw : x;
    final to = dir > 0 ? x + bw - 18 * s : x + 18 * s;
    c.drawRect(
      Rect.fromLTWH(min(from, to), y - bh * 0.6, 18 * s, 1.4 * s),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(from, 0),
          Offset(to, 0),
          [const Color(0xCC00E5FF), const Color(0x0000E5FF)],
        ),
    );
  }

  void _beams(Canvas c, double w, double h, double floorY) {
    for (var i = 0; i < 2; i++) {
      final dir = i == 0 ? 1.0 : -1.0;
      final a = 0.35 + 0.55 * (0.5 + 0.5 * sin(t * 0.35 + i * 2.1));
      final origin = Offset(w * (i == 0 ? 0.20 : 0.80), floorY);
      final len = h * 0.66;
      final tip = Offset(origin.dx + cos(a) * len * dir, origin.dy - sin(a) * len);
      final edge = Offset(origin.dx + cos(a + 0.1) * len * dir, origin.dy - sin(a + 0.1) * len);
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(edge.dx, edge.dy)
        ..close();
      c.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(origin, tip, [C.cyan.withValues(alpha: 0.15), C.cyan.withValues(alpha: 0.0)]),
      );
    }
  }

  void _platform(Canvas c, double w, double floorY, double h) {
    final disc = Rect.fromCenter(center: Offset(w / 2, floorY), width: w * 0.76, height: h * 0.15);
    c.drawOval(
      disc.inflate(10),
      Paint()..shader = ui.Gradient.radial(disc.center, disc.width * 0.5, [C.cyan.withValues(alpha: 0.20), const Color(0x0000E5FF)]),
    );
    c.drawOval(disc, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = C.cyan.withValues(alpha: 0.5));
    c.drawOval(disc.deflate(disc.width * 0.07), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.10));
    // underglow: the car's own neon colour when one is equipped
    c.drawOval(
      Rect.fromCenter(center: Offset(w / 2, floorY + 2), width: w * 0.30, height: 10),
      Paint()..color = (look.neon ?? C.cyan).withValues(alpha: 0.32)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  void _dust_(Canvas c, double w, double h) {
    for (final d in _dust) {
      final y = h - ((t * (6 + d.$3 * 14) + d.$2 * h) % (h * 1.1));
      final x = d.$1 * w + sin(t * 0.6 + d.$2 * 6) * 10;
      c.drawCircle(Offset(x, y), 0.9 + d.$3 * 0.9, Paint()..color = Colors.white.withValues(alpha: 0.08 + 0.12 * d.$3));
    }
  }

  void _vignette(Canvas c, double w, double h) {
    c.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.55),
          max(w, h) * 0.62,
          const [Color(0x00000000), Color(0x88000000)],
          const [0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant LobbyScenePainter old) => true;
}
