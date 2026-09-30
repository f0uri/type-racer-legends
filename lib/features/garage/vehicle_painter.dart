import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, HSLColor, HSVColor;
import 'look.dart';

/// Procedural vehicle renderer (cars and motorcycles). Everything is drawn from the JSON `shape`
/// parameters plus the resolved [Look], so new vehicles/skins need no code.
/// Origin: rear-left ground point, +x forward, y up is negative. [L] is the vehicle length in pixels.
enum VLayer { all, body, wheels }

class VehiclePainter {
  static final Paint _p = Paint()..isAntiAlias = true;
  static final Map<String, TextPainter> _tp = {};

  static Paint _fill(Color c) => _p
    ..shader = null
    ..maskFilter = null
    ..style = PaintingStyle.fill
    ..strokeCap = StrokeCap.butt
    ..color = c;

  static List<double> _stops(int n) => List.generate(n, (i) => n == 1 ? 0.0 : i / (n - 1));

  static Paint _stroke(Color c, double w, {StrokeCap cap = StrokeCap.round}) => _p
    ..shader = null
    ..maskFilter = null
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = cap
    ..color = c;

  static double _n(Map<String, dynamic> m, String k, double d) => (m[k] as num?)?.toDouble() ?? d;

  static Color shade(Color c, double f) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness * f).clamp(0.0, 1.0)).toColor();
  }

  static Path roundedPoly(List<Offset> pts, double r) {
    final path = Path();
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
      final d1 = (prev - cur), d2 = (next - cur);
      final l1 = d1.distance, l2 = d2.distance;
      final rr = min(r, min(l1, l2) / 2);
      final a = cur + d1 / l1 * rr, b = cur + d2 / l2 * rr;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    path.close();
    return path;
  }

  /// Tail-pipe position (for exhaust/nitro effects), relative to the origin.
  static Offset exhaustAnchor(Look look, double L) {
    final s = look.vehicle.shape;
    if (look.vehicle.isBike) {
      final wb0 = (s['wb'] as List)[0] as num;
      return Offset((wb0.toDouble() - 0.02) * L, -0.2 * L);
    }
    return Offset(-0.005 * L, -(_n(s, 'ride', 0.05) + 0.05) * L);
  }

  static Offset headlightAnchor(Look look, double L) {
    final s = look.vehicle.shape;
    if (look.vehicle.isBike) {
      final b = s['bars'] as List;
      return Offset(((b[0] as num).toDouble() + 0.06) * L, -((b[1] as num).toDouble() - 0.05) * L);
    }
    return Offset(0.99 * L, -(_n(s, 'hood', 0.2) - 0.04) * L);
  }

  static double heightOf(Look look) => look.vehicle.isBike ? 1.0 : (_n(look.vehicle.shape, 'roof', 0.35) + 0.14);

  static Offset wheelCenter(Look look, double L, int i) {
    final s = look.vehicle.shape;
    final wb = (s['wb'] as List).map((e) => (e as num).toDouble()).toList();
    return Offset(wb[i] * L, -_n(s, 'wr', 0.09) * L);
  }

  /// [layer] lets callers cache the (static) body as a Picture and draw spinning wheels every frame.
  static void paint(Canvas c, Look look, double L, {double wheelAngle = 0, double t = 0, bool braking = false, bool showRider = true, bool underglow = true, VLayer layer = VLayer.all}) {
    if (layer == VLayer.wheels) {
      _wheelsOnly(c, look, L, wheelAngle);
      return;
    }
    if (look.neon != null && underglow) _underglow(c, look, L, t);
    final wheels = layer == VLayer.all;
    if (look.vehicle.isBike) {
      _bike(c, look, L, wheelAngle, t, braking, showRider, wheels);
    } else {
      _car(c, look, L, wheelAngle, t, braking, wheels);
    }
  }

  static void _wheelsOnly(Canvas c, Look look, double L, double wa) {
    final s = look.vehicle.shape;
    final wb = (s['wb'] as List).map((e) => (e as num).toDouble()).toList();
    final wr = _n(s, 'wr', 0.09);
    for (final w in wb) {
      _wheel(c, look, Offset(w * L, -wr * L), wr * L, wa);
      if (look.vehicle.isBike && s['tron'] == 1) {
        c.drawCircle(Offset(w * L, -wr * L), wr * L * 0.98, _stroke(look.accent.withValues(alpha: 0.85), L * 0.01));
      }
    }
  }

  // ------------------------------------------------------------------ underglow
  static void _underglow(Canvas c, Look look, double L, double t) {
    var col = look.neon!;
    if (look.neonRainbow) col = HSVColor.fromAHSV(1, (t * 120) % 360, 0.9, 1).toColor();
    final pulse = look.neonPulse ? 0.65 + 0.35 * sin(t * 6) : 1.0;
    final rect = Rect.fromCenter(center: Offset(L * 0.5, -0.004 * L), width: L * 1.15, height: L * 0.2);
    final paint = _p
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..shader = Gradient.radial(rect.center, rect.width / 2, [col.withValues(alpha: 0.85 * pulse), col.withValues(alpha: 0)], [0, 1], TileMode.clamp, Float64List.fromList([1, 0, 0, 0, 0, 0.22, 0, 0, 0, 0, 1, 0, 0, rect.center.dy * 0.78, 0, 1]));
    c.drawCircle(rect.center, rect.width / 2, paint);
    _p.shader = null;
  }

  // ------------------------------------------------------------------ car
  static void _car(Canvas c, Look look, double L, double wa, double t, bool braking, bool drawWheels) {
    final s = look.vehicle.shape;
    final wb = (s['wb'] as List).map((e) => (e as num).toDouble()).toList();
    final wr = _n(s, 'wr', 0.09), ride = _n(s, 'ride', 0.05), belt = _n(s, 'belt', 0.2), roof = _n(s, 'roof', 0.34);
    final rx0 = _n(s, 'rx0', 0.3), rx1 = _n(s, 'rx1', 0.6), ax = _n(s, 'ax', 0.15), fx = _n(s, 'fx', 0.72);
    final hood = _n(s, 'hood', 0.2), nose = _n(s, 'nose', 0.12), tail = _n(s, 'tail', 0.22);
    final wing = (s['wing'] as num?)?.toInt() ?? 0;
    final open = s['open'] == 1, bed = s['bed'] == 1;
    Offset P(double x, double y) => Offset(x * L, -y * L);

    // formula-style wings behind the body
    if (wing >= 2) _wing(c, look, L, tail, wing, open);

    final body = roundedPoly([
      P(0.0, ride),
      P(0.0, tail),
      P(ax, belt + (bed ? 0 : 0)),
      P(rx0, roof),
      P(rx1, roof),
      P(fx, belt),
      P(0.985, hood),
      P(1.0, nose),
      P(1.0, ride),
    ], L * 0.03);

    // shadow
    c.drawOval(Rect.fromCenter(center: Offset(L * 0.5, 0), width: L * 1.0, height: L * 0.05), _fill(const Color(0x55000000)));

    // bed interior for pickups
    _bodyFill(c, look, body, L, t, belt, roof);

    // lower skirt
    c.drawRect(Rect.fromLTRB(0.02 * L, -(ride + 0.02) * L, 0.98 * L, -ride * L * 0.6), _fill(const Color(0x66000000)));
    // beltline accent stripe
    c.save();
    c.clipPath(body);
    c.drawRect(Rect.fromLTRB(0, -(belt * 0.42) * L, L, -(belt * 0.42 - 0.012) * L), _fill(look.secondary.withValues(alpha: 0.75)));
    c.drawRect(Rect.fromLTRB(0, -(belt * 0.42 + 0.004) * L, L, -(belt * 0.42 + 0.012) * L), _fill(look.accent.withValues(alpha: 0.6)));
    c.restore();

    if (bed) {
      final inner = roundedPoly([P(0.03, tail), P(ax - 0.015, tail), P(ax - 0.015, belt + 0.01), P(0.03, belt + 0.01)], L * 0.01);
      c.drawPath(inner, _fill(shade(look.primary, 0.35)));
      c.drawRect(Rect.fromLTRB(0.03 * L, -(tail + 0.012) * L, (ax - 0.015) * L, -(tail) * L), _fill(shade(look.primary, 0.6)));
    }

    // wheel arches
    for (final w in wb) {
      c.drawCircle(Offset(w * L, -wr * L), wr * 1.22 * L, _fill(const Color(0xFF0B0C10)));
    }

    // cabin / windows + driver
    if (!open) {
      final cab = [P(ax, belt), P(rx0, roof), P(rx1, roof), P(fx, belt)];
      final cx = cab.map((e) => e.dx).reduce((a, b) => a + b) / 4, cy = cab.map((e) => e.dy).reduce((a, b) => a + b) / 4;
      final win = roundedPoly(cab.map((p) => Offset(cx + (p.dx - cx) * 0.80, cy + (p.dy - cy) * 0.74 - 0.006 * L)).toList(), L * 0.012);
      c.save();
      c.clipPath(win);
      c.drawRect(win.getBounds(), _fill(const Color(0xFF1B2533)));
      _driver(c, look, L, (rx0 + rx1) / 2 + 0.03, roof - 0.055, 0.046, false);
      final g = _p
        ..style = PaintingStyle.fill
        ..shader = Gradient.linear(win.getBounds().topLeft, win.getBounds().bottomRight, [const Color(0x55A8D8FF), const Color(0x10A8D8FF), const Color(0x40FFFFFF)], [0, 0.6, 1]);
      c.drawRect(win.getBounds(), g);
      _p.shader = null;
      c.restore();
      // pillar
      final mid = (rx0 + rx1) / 2 - 0.02;
      c.drawLine(P(mid, belt + 0.004), P(mid + 0.012, roof - 0.02), _stroke(look.primary, L * 0.014));
    } else {
      // open cockpit: helmet sits above the body
      _driver(c, look, L, (rx0 + rx1) / 2 + 0.01, roof + 0.012, 0.05, true);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(rx0 * L, -(roof - 0.03) * L, rx1 * L, -(roof - 0.065) * L), Radius.circular(L * 0.015)), _fill(shade(look.primary, 0.7)));
    }

    // door line + handle
    if (!open) {
      final dx0 = ax + 0.09, dx1 = fx - 0.05;
      c.drawLine(P(dx0, belt - 0.004), P(dx0 - 0.006, ride + 0.03), _stroke(const Color(0x55000000), L * 0.005));
      c.drawLine(P(dx1, belt - 0.004), P(dx1 + 0.006, ride + 0.03), _stroke(const Color(0x55000000), L * 0.005));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH((dx0 + 0.04) * L, -(belt - 0.03) * L, 0.04 * L, 0.012 * L), Radius.circular(L * 0.006)), _fill(const Color(0x99FFFFFF)));
    }

    // stickers and plate
    _stickers(c, look, L, (ax + fx) / 2 - 0.03, belt * 0.68, 0.06);
    _plate(c, look, L, 0.03, ride + 0.055, 0.11, 0.045);

    // lights
    final lightOn = braking ? const Color(0xFFFF2B2B) : const Color(0xFFB00010);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.0, -(tail - 0.045) * L, 0.022 * L, 0.03 * L), Radius.circular(L * 0.006)), _fill(lightOn));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.962 * L, -(hood - 0.02) * L, 0.035 * L, 0.028 * L), Radius.circular(L * 0.008)), _fill(const Color(0xFFFFF3B0)));

    // spoiler on cheaper cars
    if (wing == 1) {
      c.drawRect(Rect.fromLTWH(-0.005 * L, -(tail + 0.03) * L, 0.11 * L, 0.014 * L), _fill(shade(look.primary, 0.6)));
      c.drawRect(Rect.fromLTWH(0.03 * L, -(tail + 0.018) * L, 0.012 * L, 0.02 * L), _fill(const Color(0xFF222222)));
    }
    if (wing == 3) {
      // front wing of formula cars
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.93 * L, -0.045 * L, 0.11 * L, 0.014 * L), Radius.circular(L * 0.006)), _fill(look.secondary));
      c.drawRect(Rect.fromLTWH(0.97 * L, -0.06 * L, 0.012 * L, 0.02 * L), _fill(const Color(0xFF222222)));
    }

    // exhaust pipe
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-0.02 * L, -(ride + 0.06) * L, 0.035 * L, 0.022 * L), Radius.circular(L * 0.008)), _fill(const Color(0xFF8D99AE)));

    if (drawWheels) {
      for (final w in wb) {
        _wheel(c, look, Offset(w * L, -wr * L), wr * L, wa);
      }
    }
  }

  static void _wing(Canvas c, Look look, double L, double tail, int wing, bool open) {
    final y = tail + (open ? 0.15 : 0.085);
    c.drawRect(Rect.fromLTWH(0.015 * L, -(y - 0.085) * L, 0.012 * L, 0.085 * L), _fill(const Color(0xFF222222)));
    c.drawRect(Rect.fromLTWH(0.085 * L, -(y - 0.085) * L, 0.012 * L, 0.085 * L), _fill(const Color(0xFF222222)));
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(-0.025 * L, -y * L, 0.14 * L, 0.02 * L), Radius.circular(L * 0.008));
    c.drawRRect(r, _fill(shade(look.primary, 0.7)));
    c.drawRect(Rect.fromLTWH(-0.025 * L, -(y - 0.012) * L, 0.14 * L, 0.006 * L), _fill(look.accent));
  }

  static void _bodyFill(Canvas c, Look look, Path body, double L, double t, double belt, double roof) {
    final b = body.getBounds();
    c.save();
    c.clipPath(body);
    final base = _p
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..shader = Gradient.linear(b.topCenter, b.bottomCenter, [shade(look.primary, look.metallic ? 1.25 : 1.12), look.primary, shade(look.primary, 0.72)], [0, 0.45, 1]);
    if (look.pattern == 'gradient' || look.pattern == 'rainbow' || look.pattern == 'carbon' || look.pattern == 'galaxy') {
      _patternBase(c, look, b, t);
    } else {
      c.drawRect(b, base);
      _p.shader = null;
      _pattern(c, look, b, L, t);
    }
    // glossy highlight along the shoulder line
    c.drawRect(Rect.fromLTRB(b.left, b.top + b.height * 0.22, b.right, b.top + b.height * 0.3), _fill(const Color(0x22FFFFFF)));
    if (look.shimmer || look.metallic) {
      final x = b.left + ((t * 0.35) % 1.6 - 0.3) * b.width;
      final sh = _p
        ..style = PaintingStyle.fill
        ..shader = Gradient.linear(Offset(x, b.top), Offset(x + b.width * 0.25, b.bottom), [const Color(0x00FFFFFF), look.shimmer ? const Color(0x66FFFFFF) : const Color(0x33FFFFFF), const Color(0x00FFFFFF)], [0, 0.5, 1]);
      c.drawRect(b, sh);
      _p.shader = null;
    }
    c.restore();
    // outline
    c.drawPath(body, _stroke(shade(look.primary, 0.45), L * 0.006));
  }

  static void _patternBase(Canvas c, Look look, Rect b, double t) {
    final cols = look.patternColors;
    switch (look.pattern) {
      case 'gradient':
        final cs = cols.length >= 2 ? cols : [look.primary, shade(look.primary, 0.5)];
        c.drawRect(b, _p..shader = Gradient.linear(b.centerLeft, b.centerRight, cs, _stops(cs.length)));
        break;
      case 'rainbow':
        final shift = (t * 40) % 360;
        final cs = List.generate(7, (i) => HSVColor.fromAHSV(1, (shift + i * 55) % 360, 0.8, 1).toColor());
        c.drawRect(b, _p..shader = Gradient.linear(b.centerLeft, b.centerRight, cs, _stops(cs.length)));
        break;
      case 'carbon':
        c.drawRect(b, _fill(const Color(0xFF16181D)));
        final pen = _stroke(const Color(0xFF2A2E36), b.height * 0.03, cap: StrokeCap.butt);
        final step = b.height * 0.06;
        for (var x = b.left; x < b.right; x += step) {
          c.drawLine(Offset(x, b.top), Offset(x, b.bottom), pen);
        }
        for (var y = b.top; y < b.bottom; y += step) {
          c.drawLine(Offset(b.left, y), Offset(b.right, y), pen);
        }
        c.drawRect(b, _p..style = PaintingStyle.fill..shader = Gradient.linear(b.topCenter, b.bottomCenter, [const Color(0x33FFFFFF), const Color(0x00000000)]));
        if (cols.length > 1) c.drawRect(Rect.fromLTRB(b.left, b.bottom - b.height * 0.3, b.right, b.bottom - b.height * 0.26), _fill(cols[1]));
        break;
      case 'galaxy':
        c.drawRect(b, _p..shader = Gradient.linear(b.topLeft, b.bottomRight, cols.length >= 2 ? cols : const [Color(0xFF10002B), Color(0xFF5A189A)], cols.length >= 2 ? _stops(cols.length) : null));
        final r = Random(7);
        for (var i = 0; i < 26; i++) {
          final tw = 0.5 + 0.5 * sin(t * 3 + i);
          c.drawCircle(Offset(b.left + r.nextDouble() * b.width, b.top + r.nextDouble() * b.height), b.height * (0.01 + r.nextDouble() * 0.014), _fill(Color.fromRGBO(255, 255, 255, 0.4 + 0.6 * tw)));
        }
        break;
    }
    _p.shader = null;
  }

  static void _pattern(Canvas c, Look look, Rect b, double L, double t) {
    final cols = look.patternColors;
    final c2 = cols.length > 1 ? cols[1] : look.accent;
    final c3 = cols.length > 2 ? cols[2] : look.secondary;
    switch (look.pattern) {
      case 'stripes':
        final h = b.height;
        c.drawRect(Rect.fromLTRB(b.left, b.top + h * 0.5, b.right, b.top + h * 0.6), _fill(c2));
        c.drawRect(Rect.fromLTRB(b.left, b.top + h * 0.64, b.right, b.top + h * 0.68), _fill(c2.withValues(alpha: 0.8)));
        break;
      case 'flames':
        final path = Path()..moveTo(b.right, b.bottom);
        final baseY = b.top + b.height * 0.78;
        var x = b.right;
        var i = 0;
        path.lineTo(b.right, baseY);
        while (x > b.left + b.width * 0.35) {
          final w = b.width * 0.08;
          path.quadraticBezierTo(x - w * 0.4, baseY - b.height * (0.22 + 0.06 * (i % 3)), x - w, baseY - b.height * (0.35 + 0.08 * (i % 2)));
          path.quadraticBezierTo(x - w * 0.9, baseY - b.height * 0.1, x - w * 1.3, baseY);
          x -= w * 1.3;
          i++;
        }
        path.lineTo(x, b.bottom);
        path.close();
        c.drawPath(path, _fill(c2));
        c.save();
        c.translate(0, b.height * 0.08);
        c.drawPath(path, _fill(c3.withValues(alpha: 0.9)));
        c.restore();
        break;
      case 'checker':
        final sz = b.height * 0.11;
        var row = 0;
        for (var y = b.bottom - sz * 3; y < b.bottom; y += sz) {
          var col = 0;
          for (var x = b.left; x < b.right; x += sz) {
            if ((row + col) % 2 == 0) c.drawRect(Rect.fromLTWH(x, y, sz, sz), _fill(c2));
            col++;
          }
          row++;
        }
        break;
      case 'chevron':
        final pen = _stroke(c2, b.height * 0.07, cap: StrokeCap.butt);
        for (var x = b.left + b.width * 0.1; x < b.right; x += b.width * 0.1) {
          final path = Path()
            ..moveTo(x, b.top + b.height * 0.35)
            ..lineTo(x + b.width * 0.05, b.top + b.height * 0.6)
            ..lineTo(x, b.top + b.height * 0.85);
          c.drawPath(path, pen);
        }
        break;
      case 'camo':
        final r = Random(3);
        final pal = [c2, c3, if (cols.length > 3) cols[3] else shade(look.primary, 0.6)];
        for (var i = 0; i < 18; i++) {
          c.drawOval(Rect.fromCenter(center: Offset(b.left + r.nextDouble() * b.width, b.top + r.nextDouble() * b.height), width: b.width * (0.08 + r.nextDouble() * 0.12), height: b.height * (0.15 + r.nextDouble() * 0.2)), _fill(pal[i % pal.length]));
        }
        break;
      case 'dots':
        final sz = b.height * 0.1;
        for (var y = b.top + sz; y < b.bottom; y += sz * 2) {
          for (var x = b.left + sz * (((y - b.top) ~/ (sz * 2)) % 2 == 0 ? 1 : 2); x < b.right; x += sz * 2.4) {
            c.drawCircle(Offset(x, y), sz * 0.42, _fill(c2));
          }
        }
        break;
      case 'crescent':
        final cx = b.left + b.width * 0.52, cy = b.top + b.height * 0.55, r = b.height * 0.26;
        c.drawCircle(Offset(cx, cy), r, _fill(c2));
        c.drawCircle(Offset(cx + r * 0.4, cy - r * 0.08), r * 0.82, _fill(look.primary));
        c.drawCircle(Offset(cx + r * 1.4, cy - r * 0.4), r * 0.16, _fill(c2));
        break;
    }
  }

  static void _driver(Canvas c, Look look, double L, double x, double y, double r, bool open) {
    final o = look.outfit;
    final ctr = Offset(x * L, -y * L);
    c.drawCircle(ctr, r * L, _fill(o.helmet));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(ctr.dx + r * L * 0.05, ctr.dy - r * L * 0.35, r * L * 1.0, r * L * 0.55), Radius.circular(r * L * 0.25)), _fill(o.visor));
    c.drawArc(Rect.fromCircle(center: ctr, radius: r * L * 0.85), -pi * 0.9, pi * 0.5, false, _stroke(o.suit2, r * L * 0.22));
    if (open) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(ctr.dx - r * L * 0.7, ctr.dy + r * L * 0.7, r * L * 1.6, r * L * 0.9), Radius.circular(r * L * 0.3)), _fill(o.suit));
    }
  }

  // ------------------------------------------------------------------ wheels
  static void _wheel(Canvas c, Look look, Offset ctr, double r, double angle) {
    c.drawCircle(ctr, r, _fill(const Color(0xFF14161B)));
    c.drawCircle(ctr, r * 0.94, _stroke(const Color(0xFF2B2F38), r * 0.1));
    final rr = r * 0.66;
    if (look.rimGlow != null) {
      c.drawCircle(ctr, rr * 1.22, _p..style = PaintingStyle.fill..shader = Gradient.radial(ctr, rr * 1.3, [look.rimGlow!.withValues(alpha: 0.6), look.rimGlow!.withValues(alpha: 0)]));
      _p.shader = null;
    }
    c.save();
    c.translate(ctr.dx, ctr.dy);
    c.rotate(angle);
    final col = look.rimColor;
    final dark = shade(col, 0.45);
    switch (look.rimStyle) {
      case 'disc':
        c.drawCircle(Offset.zero, rr, _fill(col));
        for (var i = 0; i < 5; i++) {
          final a = i * 2 * pi / 5;
          c.drawCircle(Offset(cos(a) * rr * 0.55, sin(a) * rr * 0.55), rr * 0.13, _fill(dark));
        }
        break;
      case 'mesh':
        c.drawCircle(Offset.zero, rr, _stroke(col, rr * 0.12));
        final pen = _stroke(col, rr * 0.07);
        for (var i = 0; i < 12; i++) {
          final a = i * pi / 6;
          c.drawLine(Offset.zero, Offset(cos(a) * rr, sin(a) * rr), pen);
        }
        c.drawCircle(Offset.zero, rr * 0.5, _stroke(col, rr * 0.06));
        break;
      case 'star':
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final a = i * pi / 5 - pi / 2;
          final rad = i.isEven ? rr : rr * 0.42;
          final pt = Offset(cos(a) * rad, sin(a) * rad);
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        path.close();
        c.drawPath(path, _fill(col));
        c.drawCircle(Offset.zero, rr * 0.22, _fill(dark));
        break;
      case 'split':
        c.drawCircle(Offset.zero, rr, _stroke(col, rr * 0.1));
        final pen = _stroke(col, rr * 0.11);
        for (var i = 0; i < 6; i++) {
          final a = i * pi / 3;
          final d = Offset(-sin(a), cos(a)) * rr * 0.1;
          c.drawLine(d, Offset(cos(a) * rr, sin(a) * rr) + d, pen);
          c.drawLine(-d, Offset(cos(a) * rr, sin(a) * rr) - d, pen);
        }
        break;
      case 'turbine':
        for (var i = 0; i < 8; i++) {
          final a = i * pi / 4;
          final path = Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(cos(a) * rr * 0.6 - sin(a) * rr * 0.35, sin(a) * rr * 0.6 + cos(a) * rr * 0.35, cos(a + 0.5) * rr, sin(a + 0.5) * rr)
            ..lineTo(cos(a + 0.2) * rr, sin(a + 0.2) * rr)
            ..close();
          c.drawPath(path, _fill(col));
        }
        c.drawCircle(Offset.zero, rr, _stroke(col, rr * 0.08));
        break;
      default: // spoke5
        c.drawCircle(Offset.zero, rr, _stroke(col, rr * 0.1));
        final pen = _stroke(col, rr * 0.16);
        for (var i = 0; i < 5; i++) {
          final a = i * 2 * pi / 5;
          c.drawLine(Offset.zero, Offset(cos(a) * rr, sin(a) * rr), pen);
        }
    }
    c.drawCircle(Offset.zero, rr * 0.16, _fill(dark));
    c.restore();
  }

  // ------------------------------------------------------------------ bike
  static void _bike(Canvas c, Look look, double L, double wa, double t, bool braking, bool showRider, bool drawWheels) {
    final s = look.vehicle.shape;
    final wb = (s['wb'] as List).map((e) => (e as num).toDouble()).toList();
    final wr = _n(s, 'wr', 0.15);
    final seat = (s['seat'] as List).map((e) => (e as num).toDouble()).toList();
    final tank = (s['tank'] as List).map((e) => (e as num).toDouble()).toList();
    final bars = (s['bars'] as List).map((e) => (e as num).toDouble()).toList();
    final fair = _n(s, 'fair', 0), exh = _n(s, 'exh', 0.25), cc = _n(s, 'cc', 0.6);
    final step = s['stepthru'] == 1, tron = s['tron'] == 1;
    final long = s['long'] == 1;
    Offset P(double x, double y) => Offset(x * L, -y * L);
    final o = look.outfit;
    final frame = tron ? look.accent : const Color(0xFF30343C);

    c.drawOval(Rect.fromCenter(center: Offset(L * 0.5, 0), width: L * 1.05, height: L * 0.05), _fill(const Color(0x55000000)));

    final rear = P(wb[0], wr), front = P(wb[1], wr);
    final head = P(bars[0] - 0.04, bars[1] - 0.04);

    // rider's far leg + arm are omitted (side view), near side drawn after the body.
    // fork
    final forkW = L * (0.022 + (long ? 0.004 : 0));
    c.drawLine(front, head, _stroke(const Color(0xFFADB5BD), forkW));
    c.drawLine(front + Offset(-L * 0.014, 0), head + Offset(-L * 0.014, 0), _stroke(const Color(0xFF6C757D), forkW * 0.6));
    // swingarm + engine
    final pivot = P(wb[0] + 0.2, wr + 0.02);
    c.drawLine(rear, pivot, _stroke(frame, L * 0.03));
    final ew = 0.14 + 0.12 * cc;
    final engine = RRect.fromRectAndRadius(Rect.fromLTWH((0.36 - ew * 0.2) * L, -0.3 * L, ew * L, 0.17 * L), Radius.circular(L * 0.03));
    if (!step) {
      c.drawRRect(engine, _fill(tron ? const Color(0xFF0A0F1F) : const Color(0xFF3A3F4B)));
      c.drawRect(Rect.fromLTWH(engine.left + 0.03 * L, engine.top - 0.04 * L, ew * 0.5 * L, 0.05 * L), _fill(const Color(0xFF5C6370)));
      if (tron) c.drawRRect(engine, _stroke(look.accent, L * 0.008));
    }
    // frame tubes
    final seatPt = P(seat[0] + 0.02, seat[1] - 0.03);
    c.drawLine(head, P(tank[0] + 0.02, tank[2] - 0.05), _stroke(frame, L * 0.03));
    c.drawLine(seatPt, pivot, _stroke(frame, L * 0.026));
    c.drawLine(P(tank[0] + 0.02, tank[2] - 0.05), P(0.42, 0.17), _stroke(frame, L * 0.024));

    // exhaust
    if (exh > 0) {
      final pipe = Path()
        ..moveTo(0.44 * L, -0.15 * L)
        ..quadraticBezierTo(0.3 * L, -0.08 * L, (wb[0] - 0.02) * L, -(0.2) * L);
      c.drawPath(pipe, _stroke(const Color(0xFF8D99AE), L * 0.028));
      c.drawLine(P(wb[0] - 0.02 - exh * 0.25, 0.2 - 0.0), P(wb[0] + 0.02, 0.2), _stroke(const Color(0xFFCED4DA), L * 0.04, cap: StrokeCap.butt));
    }

    // scooter body
    if (step) {
      final floor = roundedPoly([P(0.2, 0.17), P(0.64, 0.17), P(0.66, 0.11), P(0.24, 0.1)], L * 0.02);
      c.drawPath(floor, _fill(shade(look.primary, 0.75)));
      final shield = roundedPoly([P(bars[0] - 0.08, bars[1] - 0.03), P(bars[0] - 0.01, bars[1] - 0.02), P(0.72, 0.15), P(0.62, 0.12)], L * 0.03);
      _bikeFill(c, look, shield, L, t);
      final cowl = roundedPoly([P(0.0, wr * 2 + 0.02), P(0.04, 0.44), P(0.22, 0.5), P(0.3, 0.3), P(0.28, 0.18), P(0.0, 0.17)], L * 0.05);
      _bikeFill(c, look, cowl, L, t);
    }

    // tail
    if (!step && (fair >= 0.5)) {
      final tailCowl = roundedPoly([P(seat[0] - 0.14, seat[1] - 0.01), P(seat[0] - 0.04, seat[1] + 0.05), P(seat[0] + 0.02, seat[1] + 0.03), P(seat[0] + 0.02, seat[1] - 0.05), P(seat[0] - 0.12, seat[1] - 0.09)], L * 0.02);
      _bikeFill(c, look, tailCowl, L, t);
    }
    // seat
    final seatRect = RRect.fromRectAndRadius(Rect.fromLTWH((seat[0] - 0.12) * L, -(seat[1] + 0.012) * L, (tank[0] - seat[0] + 0.14) * L, 0.045 * L), Radius.circular(L * 0.02));
    c.drawRRect(seatRect, _fill(const Color(0xFF1B1D22)));

    // tank
    final tk = Path()
      ..moveTo(tank[0] * L, -(tank[2] - 0.07) * L)
      ..cubicTo(tank[0] * L, -(tank[2] + 0.04) * L, (tank[0] + (tank[1] - tank[0]) * 0.4) * L, -(tank[2] + 0.045) * L, tank[1] * L, -(tank[2] + 0.0) * L)
      ..lineTo((tank[1] - 0.03) * L, -(tank[2] - 0.085) * L)
      ..close();
    if (!step) _bikeFill(c, look, tk, L, t);

    // fairing
    if (fair > 0) {
      final f = fair.clamp(0.0, 1.0);
      final noseX = bars[0] + 0.05 + 0.05 * f;
      final fairing = roundedPoly([
        P(bars[0] - 0.05, bars[1] + 0.03 * f),
        P(bars[0] + 0.02, bars[1] + 0.05 * f),
        P(noseX, bars[1] - 0.1 * f),
        P(noseX - 0.02, bars[1] - 0.22 * f - 0.03),
        P(bars[0] - 0.12 * f - 0.04, 0.22 + 0.08 * (1 - f)),
        P(bars[0] - 0.15, bars[1] - 0.08),
      ], L * 0.03);
      _bikeFill(c, look, fairing, L, t);
      // windscreen
      final ws = Path()
        ..moveTo((bars[0] - 0.045) * L, -(bars[1] + 0.02) * L)
        ..lineTo((bars[0] - 0.12 - 0.04 * f) * L, -(bars[1] + 0.1 * f + 0.03) * L)
        ..lineTo((bars[0] - 0.12) * L, -(bars[1] + 0.0) * L)
        ..close();
      c.drawPath(ws, _fill(const Color(0x665BC0EB)));
    }
    // headlight
    final hl = P(bars[0] + (fair > 0.3 ? 0.04 : 0.055), bars[1] - (fair > 0.3 ? 0.11 * fair : 0.06));
    c.drawCircle(hl, L * 0.028, _fill(const Color(0xFFFFF3B0)));
    c.drawCircle(hl, L * 0.028, _stroke(const Color(0xFF495057), L * 0.007));
    // tail light
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: P(seat[0] - (fair >= 0.5 ? 0.14 : (step ? -0.0 : 0.13)), seat[1] - 0.0), width: L * 0.022, height: L * 0.03), Radius.circular(L * 0.006)), _fill(braking ? const Color(0xFFFF2B2B) : const Color(0xFFB00010)));

    // handlebar
    c.drawLine(head, P(bars[0], bars[1]), _stroke(const Color(0xFF212529), L * 0.02));
    c.drawCircle(P(bars[0], bars[1]), L * 0.015, _fill(const Color(0xFF111111)));

    // stickers + plate
    if (!step) _stickers(c, look, L, tank[0] + (tank[1] - tank[0]) * 0.4, tank[2] - 0.035, 0.05);
    _plate(c, look, L, wb[0] - 0.02, wr * 2 + 0.06, 0.1, 0.04);

    // wheels
    if (drawWheels) {
      for (final w in wb) {
        _wheel(c, look, P(w, wr), wr * L, wa);
      }
      if (tron) {
        for (final w in wb) {
          c.drawCircle(P(w, wr), wr * L * 0.98, _stroke(look.accent.withValues(alpha: 0.85), L * 0.01));
        }
      }
    }
    // rider
    if (showRider) {
      final hip = P(seat[0], seat[1] + 0.03);
      final lean = 0.16 + 0.1 * fair;
      final shoulder = Offset(hip.dx + lean * L, hip.dy - 0.2 * L);
      final grip = P(bars[0], bars[1]);
      final knee = P(seat[0] + 0.2, seat[1] - 0.06);
      final foot = P(0.42, 0.16);
      c.drawLine(hip, knee, _stroke(o.suit, L * 0.05));
      c.drawLine(knee, foot, _stroke(o.suit, L * 0.042));
      c.drawCircle(foot, L * 0.022, _fill(o.suit2));
      c.drawLine(hip, shoulder, _stroke(o.suit, L * 0.085));
      c.drawLine(hip + Offset(0, -L * 0.02), shoulder + Offset(0, L * 0.02), _stroke(o.suit2.withValues(alpha: 0.7), L * 0.02));
      final elbow = Offset((shoulder.dx + grip.dx) / 2 - L * 0.01, (shoulder.dy + grip.dy) / 2 + L * 0.03);
      c.drawLine(shoulder, elbow, _stroke(o.suit2, L * 0.04));
      c.drawLine(elbow, grip, _stroke(o.suit2, L * 0.034));
      c.drawCircle(grip, L * 0.02, _fill(const Color(0xFF111111)));
      final h = shoulder + Offset(L * 0.04, -L * 0.065);
      c.drawCircle(h, L * 0.062, _fill(o.helmet));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(h.dx + L * 0.005, h.dy - L * 0.03, L * 0.065, L * 0.04), Radius.circular(L * 0.018)), _fill(o.visor));
      c.drawArc(Rect.fromCircle(center: h, radius: L * 0.05), -pi * 0.95, pi * 0.6, false, _stroke(o.suit2, L * 0.012));
    }
  }

  static void _bikeFill(Canvas c, Look look, Path path, double L, double t) {
    final b = path.getBounds();
    c.save();
    c.clipPath(path);
    if (look.pattern == 'gradient' || look.pattern == 'rainbow' || look.pattern == 'carbon' || look.pattern == 'galaxy') {
      _patternBase(c, look, b, t);
    } else {
      c.drawRect(b, _p..style = PaintingStyle.fill..shader = Gradient.linear(b.topCenter, b.bottomCenter, [shade(look.primary, 1.15), look.primary, shade(look.primary, 0.7)], [0, 0.5, 1]));
      _p.shader = null;
      _pattern(c, look, b, L, t);
    }
    c.drawRect(Rect.fromLTRB(b.left, b.top + b.height * 0.15, b.right, b.top + b.height * 0.27), _fill(const Color(0x22FFFFFF)));
    c.restore();
    c.drawPath(path, _stroke(shade(look.primary, 0.45), L * 0.005));
  }

  // ------------------------------------------------------------------ stickers & plate
  static void _stickers(Canvas c, Look look, double L, double x, double y, double size) {
    for (var i = 0; i < look.stickers.length && i < 2; i++) {
      final st = look.stickers[i];
      final ctr = Offset((x - i * 0.15) * L, -y * L);
      drawSticker(c, st.shape, st.color, ctr, size * L, number: st.number);
    }
  }

  static void drawSticker(Canvas c, String shape, Color col, Offset ctr, double s, {int? number}) {
    c.save();
    c.translate(ctr.dx, ctr.dy);
    final fill = _fill(col);
    switch (shape) {
      case 'star':
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final a = i * pi / 5 - pi / 2;
          final r = i.isEven ? s * 0.5 : s * 0.22;
          i == 0 ? path.moveTo(cos(a) * r, sin(a) * r) : path.lineTo(cos(a) * r, sin(a) * r);
        }
        c.drawPath(path..close(), fill);
        break;
      case 'heart':
        final path = Path()
          ..moveTo(0, s * 0.4)
          ..cubicTo(-s * 0.7, -s * 0.05, -s * 0.3, -s * 0.55, 0, -s * 0.18)
          ..cubicTo(s * 0.3, -s * 0.55, s * 0.7, -s * 0.05, 0, s * 0.4);
        c.drawPath(path, fill);
        break;
      case 'bolt':
        final path = Path()
          ..moveTo(s * 0.1, -s * 0.5)
          ..lineTo(-s * 0.3, s * 0.08)
          ..lineTo(0, s * 0.08)
          ..lineTo(-s * 0.1, s * 0.5)
          ..lineTo(s * 0.32, -s * 0.12)
          ..lineTo(0.02 * s, -s * 0.12)
          ..close();
        c.drawPath(path, fill);
        break;
      case 'flame':
        final path = Path()
          ..moveTo(0, -s * 0.5)
          ..cubicTo(s * 0.5, -s * 0.05, s * 0.45, s * 0.45, 0, s * 0.45)
          ..cubicTo(-s * 0.5, s * 0.45, -s * 0.45, 0, -s * 0.1, -s * 0.2)
          ..cubicTo(-s * 0.1, -s * 0.05, 0, -s * 0.2, 0, -s * 0.5);
        c.drawPath(path, fill);
        break;
      case 'skull':
        c.drawCircle(Offset(0, -s * 0.08), s * 0.38, fill);
        c.drawRect(Rect.fromCenter(center: Offset(0, s * 0.3), width: s * 0.38, height: s * 0.26), fill);
        final dark = _fill(const Color(0xFF111111));
        c.drawCircle(Offset(-s * 0.14, -s * 0.08), s * 0.09, dark);
        c.drawCircle(Offset(s * 0.14, -s * 0.08), s * 0.09, dark);
        c.drawRect(Rect.fromCenter(center: Offset(0, s * 0.12), width: s * 0.06, height: s * 0.08), dark);
        break;
      case 'crown':
        final path = Path()
          ..moveTo(-s * 0.45, s * 0.3)
          ..lineTo(-s * 0.45, -s * 0.2)
          ..lineTo(-s * 0.2, 0)
          ..lineTo(0, -s * 0.35)
          ..lineTo(s * 0.2, 0)
          ..lineTo(s * 0.45, -s * 0.2)
          ..lineTo(s * 0.45, s * 0.3)
          ..close();
        c.drawPath(path, fill);
        break;
      case 'wing':
        for (var i = 0; i < 4; i++) {
          c.drawPath(Path()..moveTo(-s * 0.45, s * 0.3 - i * s * 0.17)..quadraticBezierTo(0, s * 0.1 - i * s * 0.22, s * 0.5, -s * 0.15 - i * s * 0.12)..quadraticBezierTo(0, s * 0.2 - i * s * 0.15, -s * 0.45, s * 0.3 - i * s * 0.17), fill);
        }
        break;
      case 'arrow':
        c.drawPath(Path()..moveTo(-s * 0.5, -s * 0.12)..lineTo(s * 0.1, -s * 0.12)..lineTo(s * 0.1, -s * 0.4)..lineTo(s * 0.5, 0)..lineTo(s * 0.1, s * 0.4)..lineTo(s * 0.1, s * 0.12)..lineTo(-s * 0.5, s * 0.12)..close(), fill);
        break;
      case 'crescent':
        c.drawCircle(Offset.zero, s * 0.42, fill);
        c.drawCircle(Offset(s * 0.16, -s * 0.05), s * 0.36, _fill(const Color(0xFF111111)));
        break;
      case 'ball':
        c.drawCircle(Offset.zero, s * 0.44, _fill(const Color(0xFFFFFFFF)));
        c.drawCircle(Offset.zero, s * 0.16, fill);
        for (var i = 0; i < 5; i++) {
          final a = i * 2 * pi / 5 - pi / 2;
          c.drawCircle(Offset(cos(a) * s * 0.34, sin(a) * s * 0.34), s * 0.08, fill);
        }
        break;
      case 'number':
      default:
        c.drawCircle(Offset.zero, s * 0.46, _fill(const Color(0xFFFFFFFF)));
        c.drawCircle(Offset.zero, s * 0.46, _stroke(col, s * 0.07));
        final tp = _text('${number ?? 7}', s * 0.6, col, bold: true);
        tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    }
    c.restore();
  }

  static TextPainter _text(String text, double size, Color color, {bool bold = false}) {
    final key = '$text|${size.round()}|${color.toARGB32()}|$bold';
    return _tp.putIfAbsent(key, () {
      if (_tp.length > 120) _tp.clear();
      return TextPainter(text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontFamily: 'FiraMono', height: 1.0)), textDirection: TextDirection.ltr)..layout();
    });
  }

  static void _plate(Canvas c, Look look, double L, double x, double y, double w, double h) {
    if (L < 70) return;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(x * L, -(y + h) * L, w * L, h * L), Radius.circular(L * 0.008));
    if (look.plateGlow) {
      c.drawRRect(r.inflate(L * 0.008), _fill(look.plateBorder.withValues(alpha: 0.35)));
    }
    c.drawRRect(r, _fill(look.plateBg));
    c.drawRRect(r, _stroke(look.plateBorder, L * 0.005));
    final txt = look.plateText.isEmpty ? 'TRL' : look.plateText.toUpperCase();
    final tp = _text(txt.length > 7 ? txt.substring(0, 7) : txt, h * L * 0.62, look.plateFg, bold: true);
    if (tp.width < w * L) tp.paint(c, Offset(r.left + (r.width - tp.width) / 2, r.top + (r.height - tp.height) / 2));
  }
}
