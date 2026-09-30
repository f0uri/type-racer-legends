import 'dart:math';
import 'dart:ui';
import 'package:flutter/painting.dart' show HSVColor;
import '../../garage/look.dart';
import '../../garage/vehicle_painter.dart';
import 'particles.dart';

/// Visual effects shared by the race game and the garage previews (exhaust, nitro flame, win celebrations).
class Effects {
  /// Emits one exhaust particle for the look's exhaust skin. [back] is the horizontal velocity.
  static void exhaust(ParticleSystem ps, Look look, double x, double y, double back, double t, Random rnd) {
    switch (look.exhaustEffect) {
      case 'fire':
        ps.emit(PKind.dot, x, y, back, (rnd.nextDouble() - 0.5) * 30, 0.35, 3.5, rnd.nextBool() ? const Color(0xFFFF9E00) : const Color(0xFFFF4D00));
        break;
      case 'sparks':
        ps.emit(PKind.spark, x, y, back, (rnd.nextDouble() - 0.6) * 90, 0.45, 2.5, look.exhaustColor, g: 160);
        break;
      case 'electric':
        ps.emit(PKind.spark, x, y, back, (rnd.nextDouble() - 0.5) * 140, 0.3, 2.5, const Color(0xFF7DF9FF));
        break;
      case 'bubbles':
        ps.emit(PKind.ring, x, y, back * 0.6, -20 - rnd.nextDouble() * 30, 0.9, 6, const Color(0xFFB8F2FF));
        break;
      case 'rainbow':
        ps.emit(PKind.dot, x, y, back, (rnd.nextDouble() - 0.5) * 20, 0.6, 4, HSVColor.fromAHSV(1, (t * 240) % 360, 0.9, 1).toColor());
        break;
      case 'stars':
        ps.emit(PKind.star, x, y, back * 0.8, (rnd.nextDouble() - 0.5) * 40, 0.8, 3.5, const Color(0xFFFFD166));
        break;
      default:
        ps.emit(PKind.smoke, x, y, back * 0.6, -10 - rnd.nextDouble() * 20, 0.7, 4, const Color(0xFFB0B7C3));
    }
  }

  /// Win celebration burst. [anchor] is the vehicle position, [area] the screen.
  static void celebrate(ParticleSystem ps, String type, List<Color> cols, Size area, Offset anchor) {
    switch (type) {
      case 'fireworks':
        for (var i = 0; i < 4; i++) {
          final cx = area.width * (0.25 + 0.15 * i), cy = area.height * (0.15 + 0.12 * (i % 2));
          ps.burst(PKind.spark, cx, cy, 36, speed: 170, colors: cols, life: 1.2, size: 3, g: 120);
        }
        break;
      case 'flags':
        ps.burst(PKind.confetti, area.width * 0.5, -10, 70, speed: 60, colors: const [Color(0xFF111111), Color(0xFFFFFFFF)], life: 2.5, size: 6, g: 80, spread: 3.14, angle: 1.57);
        break;
      case 'lightning':
        ps.burst(PKind.spark, anchor.dx + 30, anchor.dy - 30, 40, speed: 260, colors: cols, life: 0.6, size: 3, g: 0);
        break;
      case 'smoke':
      case 'donut':
        ps.burst(PKind.smoke, anchor.dx + 10, anchor.dy - 8, 40, speed: 70, colors: cols, life: 1.6, size: 10, g: -25, spread: 3.14, angle: 3.14);
        break;
      case 'wheelie':
        ps.burst(PKind.star, anchor.dx + 30, anchor.dy - 50, 24, speed: 120, colors: cols, life: 1.2, size: 4, g: 60);
        break;
      default:
        ps.burst(PKind.confetti, area.width * 0.5, -10, 90, speed: 80, colors: cols, life: 2.6, size: 6, g: 100, spread: 3.14, angle: 1.57);
        ps.burst(PKind.confetti, anchor.dx + 30, anchor.dy - 40, 40, speed: 160, colors: cols, life: 1.8, size: 5, g: 160, spread: 3.14, angle: -1.57);
    }
  }

  /// Nitro flame at the exhaust (origin already translated to the vehicle origin).
  static void flame(Canvas c, Look look, double L, double fx, double turbo, double t) {
    final ex = VehiclePainter.exhaustAnchor(look, L);
    final cols = look.flameColors.length >= 2 ? look.flameColors : const [Color(0xFF7DF9FF), Color(0xFF2A6BFF), Color(0xFFFFFFFF)];
    final len = L * (0.35 + 0.25 * sin(t * 60).abs()) * fx * (1 + turbo * 0.4);
    final w = L * 0.05;
    c.save();
    c.translate(ex.dx, ex.dy);
    final p = Paint();
    void cone(double scale, Color col) {
      final path = Path()
        ..moveTo(0, -w * scale)
        ..quadraticBezierTo(-len * 0.5 * scale, -w * 0.4 * scale, -len * scale, 0)
        ..quadraticBezierTo(-len * 0.5 * scale, w * 0.4 * scale, 0, w * scale)
        ..close();
      c.drawPath(path, p..color = col);
    }

    switch (look.flameShape) {
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
          path.lineTo(-len * i / 6, sin(t * 40 + i) * w * (1 - i / 7));
        }
        for (var i = 6; i >= 0; i--) {
          path.lineTo(-len * i / 6, w * 0.6 * (1 - i / 7) + sin(t * 40 + i + 2) * w * 0.3);
        }
        c.drawPath(path, p..color = cols[0].withValues(alpha: 0.85));
        cone(0.4, cols.last);
        break;
      case 'spark':
        cone(0.55, cols[0].withValues(alpha: 0.85));
        for (var i = 0; i < 6; i++) {
          final a = (i / 6) * 2 - 1;
          c.drawLine(Offset(-len * 0.3, 0), Offset(-len * (0.7 + 0.4 * ((t * 7 + i) % 1)), a * w * 3), p..style = PaintingStyle.stroke..strokeWidth = 2..color = cols[1]);
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
}
