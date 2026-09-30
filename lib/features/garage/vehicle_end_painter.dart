import 'dart:math';
import 'dart:ui';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight, TextDirection, HSVColor;
import 'look.dart';
import 'vehicle_painter.dart';

/// Front and rear views of a vehicle (used by the 360° garage turntable). Origin: ground, horizontally centred.
/// [S] is the vehicle length in pixels, the same scale as the side view.
class VehicleEndPainter {
  static final Paint _p = Paint()..isAntiAlias = true;
  static Paint _f(Color c) => _p
    ..shader = null
    ..maskFilter = null
    ..style = PaintingStyle.fill
    ..color = c;
  static Paint _s(Color c, double w) => _p
    ..shader = null
    ..maskFilter = null
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = c;
  static double _n(Map<String, dynamic> m, String k, double d) => (m[k] as num?)?.toDouble() ?? d;

  /// Half width (in S units) of the end view, for layout.
  static double halfWidth(Look look) => look.vehicle.isBike ? 0.12 : 0.24;

  static void paint(Canvas c, Look look, double S, {required bool rear, double t = 0}) {
    if (look.neon != null) _glow(c, look, S, t);
    if (look.vehicle.isBike) {
      _bike(c, look, S, rear, t);
    } else {
      _car(c, look, S, rear, t);
    }
  }

  static void _glow(Canvas c, Look look, double S, double t) {
    final col = look.neonRainbow ? HSVColor.fromAHSV(1, (t * 120) % 360, 0.9, 1).toColor() : look.neon!;
    final a = look.neonPulse ? 0.5 + 0.3 * sin(t * 5) : 0.6;
    final w = halfWidth(look) * S * 2.2;
    c.drawOval(Rect.fromCenter(center: Offset(0, -S * 0.01), width: w, height: S * 0.06), _p..shader = Gradient.radial(Offset(0, -S * 0.01), w / 2, [col.withValues(alpha: a), col.withValues(alpha: 0)]));
    _p.shader = null;
  }

  static Paint _bodyPaint(Look look, Rect r) {
    final base = look.primary;
    if (['gradient', 'rainbow', 'galaxy', 'carbon'].contains(look.pattern) && look.patternColors.length >= 2) {
      final cs = look.patternColors;
      return _p
        ..style = PaintingStyle.fill
        ..shader = Gradient.linear(r.centerLeft, r.centerRight, cs, List.generate(cs.length, (i) => i / (cs.length - 1)));
    }
    return _p
      ..style = PaintingStyle.fill
      ..shader = Gradient.linear(r.topCenter, r.bottomCenter, [VehiclePainter.shade(base, 1.25), base, VehiclePainter.shade(base, 0.7)], const [0, 0.45, 1]);
  }

  static void _car(Canvas c, Look look, double S, bool rear, double t) {
    final s = look.vehicle.shape;
    final ride = _n(s, 'ride', 0.05), wr = _n(s, 'wr', 0.09), belt = _n(s, 'belt', 0.2), roof = _n(s, 'roof', 0.35);
    final wing = (s['wing'] as num?)?.toInt() ?? 0;
    final W = S * 0.46;
    final tyreW = S * 0.075, tyreH = wr * 2 * S;
    // tyres
    for (final sx in [-1.0, 1.0]) {
      final rr = RRect.fromRectAndRadius(Rect.fromLTWH(sx * (W / 2 - tyreW * 0.1) - (sx > 0 ? 0 : tyreW), -tyreH, tyreW, tyreH), Radius.circular(tyreW * 0.3));
      c.drawRRect(rr, _f(const Color(0xFF14161B)));
      c.drawRRect(rr.deflate(tyreW * 0.15), _s(const Color(0xFF2B2F38), 1.2));
    }
    // lower body
    final lowTop = -belt * S, lowBot = -ride * S;
    final low = RRect.fromRectAndCorners(Rect.fromLTRB(-W / 2, lowTop, W / 2, lowBot), topLeft: Radius.circular(S * 0.05), topRight: Radius.circular(S * 0.05), bottomLeft: Radius.circular(S * 0.02), bottomRight: Radius.circular(S * 0.02));
    c.drawRRect(low, _bodyPaint(look, low.outerRect));
    _p.shader = null;
    // cabin
    final topY = -roof * S;
    final cabin = Path()
      ..moveTo(-W * 0.44, lowTop)
      ..lineTo(-W * 0.31, topY)
      ..lineTo(W * 0.31, topY)
      ..lineTo(W * 0.44, lowTop)
      ..close();
    c.drawPath(cabin, _bodyPaint(look, Rect.fromLTRB(-W / 2, topY, W / 2, lowTop)));
    _p.shader = null;
    final glass = Path()
      ..moveTo(-W * 0.385, lowTop - S * 0.008)
      ..lineTo(-W * 0.275, topY + S * 0.02)
      ..lineTo(W * 0.275, topY + S * 0.02)
      ..lineTo(W * 0.385, lowTop - S * 0.008)
      ..close();
    c.drawPath(glass, _p..style = PaintingStyle.fill..shader = Gradient.linear(Offset(0, topY), Offset(0, lowTop), [const Color(0xFF1B2A41), const Color(0xFF0B132B)]));
    _p.shader = null;
    // driver (seen through the glass)
    final o = look.outfit;
    if (!rear) {
      c.drawCircle(Offset(-W * 0.14, topY + (lowTop - topY) * 0.45), S * 0.032, _f(o.helmet));
      c.drawRect(Rect.fromLTWH(-W * 0.14 - S * 0.022, topY + (lowTop - topY) * 0.42, S * 0.044, S * 0.012), _f(o.visor));
    }
    // pattern accent: centre stripes
    if (look.pattern == 'stripes' || look.pattern == 'chevron' || look.pattern == 'flames') {
      final sc = look.patternColors.length > 1 ? look.patternColors.last : look.secondary;
      c.drawRect(Rect.fromLTRB(-W * 0.07, topY + S * 0.005, -W * 0.02, lowBot - S * 0.01), _f(sc.withValues(alpha: 0.9)));
      c.drawRect(Rect.fromLTRB(W * 0.02, topY + S * 0.005, W * 0.07, lowBot - S * 0.01), _f(sc.withValues(alpha: 0.9)));
    }
    // lights / grille / plate
    final ly = lowTop + (lowBot - lowTop) * 0.32;
    if (!rear) {
      for (final sx in [-1.0, 1.0]) {
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sx * W * 0.34, ly), width: W * 0.2, height: S * 0.032), Radius.circular(S * 0.015));
        c.drawRRect(r.inflate(S * 0.006), _f(look.accent.withValues(alpha: 0.35)));
        c.drawRRect(r, _f(const Color(0xFFFFF8D6)));
      }
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, ly + S * 0.006), width: W * 0.4, height: S * 0.03), Radius.circular(S * 0.008)), _f(const Color(0xFF0B0D12)));
      for (var i = -2; i <= 2; i++) {
        c.drawLine(Offset(i * W * 0.07, ly - S * 0.008), Offset(i * W * 0.07, ly + S * 0.02), _s(const Color(0xFF3A3F4B), 1));
      }
    } else {
      for (final sx in [-1.0, 1.0]) {
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sx * W * 0.36, ly), width: W * 0.18, height: S * 0.03), Radius.circular(S * 0.01));
        c.drawRRect(r.inflate(S * 0.007), _f(const Color(0xFFFF2D55).withValues(alpha: 0.35)));
        c.drawRRect(r, _f(const Color(0xFFE5173F)));
      }
      _plate(c, look, S, Offset(0, ly + S * 0.008), W * 0.32, S * 0.04);
      for (final sx in [-1.0, 1.0]) {
        c.drawCircle(Offset(sx * W * 0.26, lowBot - S * 0.004), S * 0.016, _f(const Color(0xFF8A8F99)));
        c.drawCircle(Offset(sx * W * 0.26, lowBot - S * 0.004), S * 0.009, _f(const Color(0xFF111111)));
      }
      if (wing > 0) {
        final wy = topY - S * 0.01 - wing * S * 0.012;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, wy), width: W * 1.04, height: S * 0.014), Radius.circular(S * 0.005)), _f(look.secondary));
        for (final sx in [-1.0, 1.0]) {
          c.drawRect(Rect.fromLTWH(sx * W * 0.5 - S * 0.004, wy - S * 0.022, S * 0.008, S * 0.04), _f(look.accent));
        }
        c.drawRect(Rect.fromLTWH(-S * 0.006, wy, S * 0.012, S * 0.03), _f(look.secondary));
      }
    }
    // sills + stickers
    c.drawRect(Rect.fromLTRB(-W / 2, lowBot - S * 0.012, W / 2, lowBot), _f(VehiclePainter.shade(look.secondary, 0.8)));
    for (var i = 0; i < look.stickers.length && i < 2; i++) {
      VehiclePainter.drawSticker(c, look.stickers[i].shape, look.stickers[i].color, Offset((i == 0 ? -1 : 1) * W * 0.3, lowTop + (lowBot - lowTop) * 0.7), S * 0.03, number: look.stickers[i].number);
    }
  }

  static void _plate(Canvas c, Look look, double S, Offset ctr, double w, double h) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: ctr, width: w, height: h), Radius.circular(S * 0.006));
    if (look.plateGlow) c.drawRRect(r.inflate(S * 0.006), _f(look.plateBorder.withValues(alpha: 0.4)));
    c.drawRRect(r, _f(look.plateBg));
    c.drawRRect(r, _s(look.plateBorder, max(1, S * 0.004)));
    final txt = (look.plateText.isEmpty ? 'TRL' : look.plateText.toUpperCase());
    final tp = TextPainter(text: TextSpan(text: txt.length > 7 ? txt.substring(0, 7) : txt, style: TextStyle(fontSize: h * 0.62, color: look.plateFg, fontWeight: FontWeight.w800, fontFamily: 'FiraMono', height: 1)), textDirection: TextDirection.ltr)..layout();
    if (tp.width < w * 0.95) tp.paint(c, ctr - Offset(tp.width / 2, tp.height / 2));
  }

  static void _bike(Canvas c, Look look, double S, bool rear, double t) {
    final s = look.vehicle.shape;
    final wr = _n(s, 'wr', 0.12);
    final bars = (s['bars'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [0.7, 0.55];
    final barsY = bars[1];
    final fair = (s['fair'] as num?)?.toInt() ?? 0;
    final o = look.outfit;
    final tyreW = S * (rear ? 0.065 : 0.05);
    final tyre = RRect.fromRectAndRadius(Rect.fromLTWH(-tyreW / 2, -wr * 2 * S, tyreW, wr * 2 * S), Radius.circular(tyreW * 0.5));
    c.drawRRect(tyre, _f(const Color(0xFF14161B)));
    c.drawLine(Offset(0, -wr * 2 * S + 3), Offset(0, -3), _s(const Color(0xFF2B2F38), 1.2));
    // tank / body
    final tankY = -barsY * S * 0.78;
    final tank = Rect.fromCenter(center: Offset(0, tankY), width: S * (rear ? 0.12 : 0.15), height: S * 0.11);
    c.drawOval(tank, _bodyPaint(look, tank));
    _p.shader = null;
    // fork / swingarm
    if (!rear) {
      for (final sx in [-1.0, 1.0]) {
        c.drawLine(Offset(sx * S * 0.022, -wr * S), Offset(sx * S * 0.03, -barsY * S), _s(const Color(0xFFB8BCC6), S * 0.012));
      }
    } else {
      c.drawRect(Rect.fromCenter(center: Offset(0, -wr * S * 1.5), width: S * 0.05, height: S * 0.04), _f(VehiclePainter.shade(look.secondary, 0.9)));
    }
    // rider
    final shoulderY = -(barsY + 0.12) * S;
    final torso = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, shoulderY + S * 0.06), width: S * 0.12, height: S * 0.16), Radius.circular(S * 0.04));
    c.drawRRect(torso, _f(o.suit));
    c.drawRect(Rect.fromCenter(center: Offset(0, shoulderY + S * 0.06), width: S * 0.018, height: S * 0.15), _f(o.suit2));
    c.drawCircle(Offset(0, shoulderY - S * 0.03), S * 0.042, _f(o.helmet));
    if (!rear) c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, shoulderY - S * 0.03), width: S * 0.05, height: S * 0.02), Radius.circular(S * 0.008)), _f(o.visor));
    // bars
    final by = -barsY * S;
    c.drawLine(Offset(-S * 0.11, by), Offset(S * 0.11, by), _s(const Color(0xFFB8BCC6), S * 0.012));
    for (final sx in [-1.0, 1.0]) {
      c.drawCircle(Offset(sx * S * 0.115, by), S * 0.013, _f(const Color(0xFF111111)));
      c.drawLine(Offset(sx * S * 0.06, shoulderY + S * 0.05), Offset(sx * S * 0.11, by), _s(o.suit, S * 0.03));
    }
    if (!rear) {
      final hl = Offset(0, by + S * 0.05);
      c.drawCircle(hl, S * 0.05, _f(look.accent.withValues(alpha: 0.3)));
      c.drawCircle(hl, S * 0.032, _f(const Color(0xFFFFF8D6)));
      if (fair > 0) {
        final path = Path()
          ..moveTo(-S * 0.07, by + S * 0.09)
          ..quadraticBezierTo(0, by - S * 0.06, S * 0.07, by + S * 0.09)
          ..close();
        c.drawPath(path, _f(look.primary.withValues(alpha: 0.95)));
        c.drawCircle(hl, S * 0.028, _f(const Color(0xFFFFF8D6)));
      }
    } else {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -wr * 2 * S - S * 0.02), width: S * 0.08, height: S * 0.018), Radius.circular(S * 0.006)), _f(const Color(0xFFE5173F)));
      _plate(c, look, S, Offset(0, -wr * S * 1.25), S * 0.12, S * 0.05);
      for (final sx in [-1.0, 1.0]) {
        c.drawCircle(Offset(sx * S * 0.06, -S * 0.07), S * 0.016, _f(const Color(0xFF8A8F99)));
      }
    }
  }
}
