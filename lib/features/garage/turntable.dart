import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'look.dart';
import 'vehicle_end_painter.dart';
import 'vehicle_painter.dart';

/// Interactive 360° showroom: drag to spin (with inertia), auto-rotates when idle.
/// The vehicle is composed from its side, front and rear procedural views, cross-faded and foreshortened as it turns.
class Turntable extends StatefulWidget {
  const Turntable({super.key, required this.look, this.autoRotate = true, this.initialAngle = pi / 2, this.showRider = true});
  final Look look;
  final bool autoRotate;
  final double initialAngle;
  final bool showRider;
  @override
  State<Turntable> createState() => _TurntableState();
}

class _TurntableState extends State<Turntable> with SingleTickerProviderStateMixin {
  late double angle = widget.initialAngle;
  double velocity = 0;
  bool dragging = false;
  double idle = 0;
  double t = 0;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration d) {
    final dt = _last == Duration.zero ? 0.016 : (d - _last).inMicroseconds / 1e6;
    _last = d;
    t += dt;
    if (!dragging) {
      if (velocity.abs() > 0.05) {
        angle += velocity * dt;
        velocity *= pow(0.04, dt).toDouble();
        idle = 0;
      } else {
        idle += dt;
        if (widget.autoRotate && idle > 1.2) angle += dt * 0.55;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          dragging = true;
          velocity = 0;
        },
        onPanUpdate: (d) {
          angle -= d.delta.dx * 0.012;
          velocity = -d.delta.dx * 0.012 * 60 * 0.6;
        },
        onPanEnd: (_) => dragging = false,
        onPanCancel: () => dragging = false,
        child: CustomPaint(painter: TurntablePainter(widget.look, angle, t, widget.showRider), size: Size.infinite),
      );
}

class TurntablePainter extends CustomPainter {
  final Look look;
  final double angle, t;
  final bool showRider;
  TurntablePainter(this.look, this.angle, this.t, this.showRider);

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    final floorY = H * 0.78;
    // stage light
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..shader = ui.Gradient.radial(Offset(W / 2, floorY - H * 0.25), W * 0.75, [const Color(0xFF26335F), const Color(0xFF0B0F1E)]));
    // floor disc with rotating ring marks
    final discRect = Rect.fromCenter(center: Offset(W / 2, floorY), width: W * 0.92, height: H * 0.2);
    canvas.drawOval(discRect, Paint()..shader = ui.Gradient.radial(discRect.center, W * 0.46, [const Color(0xFF2A3566), const Color(0xFF131A36)]));
    canvas.drawOval(discRect, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF00E5FF).withValues(alpha: 0.6));
    for (var i = 0; i < 24; i++) {
      final a = angle * 1.0 + i * pi / 12;
      final x = discRect.center.dx + cos(a) * discRect.width * 0.47;
      final y = discRect.center.dy + sin(a) * discRect.height * 0.47;
      canvas.drawCircle(Offset(x, y), 1.6, Paint()..color = Colors.white.withValues(alpha: 0.35 + 0.35 * sin(a)));
    }
    paintVehicle(canvas, size, look, angle, t, showRider: showRider);
  }

  /// Draws the vehicle only (no stage), composed from its side, front and rear procedural
  /// views cross-faded and foreshortened as it turns. Shared by the garage showroom and the
  /// home lobby so the player always sees the exact same car in both places.
  static void paintVehicle(Canvas canvas, Size size, Look look, double angle, double t, {bool showRider = true}) {
    final W = size.width, H = size.height;
    final floorY = H * 0.78;
    final bike = look.vehicle.isBike;
    final L = min(W * 0.78, H * 0.62 / (bike ? 0.85 : 0.5));
    final sinT = sin(angle), cosT = cos(angle);
    final sideW = sinT.abs(), endW = cosT.abs();
    final facingRight = sinT >= 0;
    // contact shadow
    canvas.drawOval(Rect.fromCenter(center: Offset(W / 2, floorY + 2), width: L * (0.35 + 0.65 * sideW), height: L * 0.08), Paint()..color = Colors.black.withValues(alpha: 0.45)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.save();
    canvas.translate(W / 2, floorY);
    // side view, foreshortened and mirrored when facing left
    final sx = 0.16 + 0.84 * sideW;
    final sideAlpha = pow(sideW, 1.1).toDouble().clamp(0.0, 1.0);
    if (sideAlpha > 0.03) {
      canvas.saveLayer(Rect.fromLTWH(-W, -H, W * 2, H * 1.3), Paint()..color = Color.fromRGBO(255, 255, 255, sideAlpha));
      canvas.scale(facingRight ? sx : -sx, 1);
      canvas.translate(-L / 2, 0);
      VehiclePainter.paint(canvas, look, L, t: t, wheelAngle: angle * 2.2, showRider: showRider);
      canvas.restore();
    }
    // front / rear view attaches to the matching end of the side view
    final endAlpha = pow(endW, 1.1).toDouble().clamp(0.0, 1.0);
    if (endAlpha > 0.03) {
      final rear = cosT < 0;
      // front is on the right when the vehicle faces right
      final onRight = rear ? !facingRight : facingRight;
      final attach = (onRight ? 1 : -1) * (L * 0.5 * sx) * (1 - endW * 0.92);
      canvas.save();
      canvas.translate(attach, 0);
      canvas.saveLayer(Rect.fromLTWH(-W, -H, W * 2, H * 1.3), Paint()..color = Color.fromRGBO(255, 255, 255, endAlpha));
      final k = 0.72 + 0.28 * endW;
      canvas.scale(k, 1);
      VehicleEndPainter.paint(canvas, look, L, rear: rear, t: t);
      canvas.restore();
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TurntablePainter old) => true;
}
