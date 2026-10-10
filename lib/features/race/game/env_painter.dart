import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import '../../../data/models/content_models.dart';
import '../../garage/look.dart';

class EnvSpec {
  final String biome;
  final Color skyTop, skyBottom, ground, accent;
  final String weather, mod;
  final String? landmark;
  const EnvSpec({required this.biome, required this.skyTop, required this.skyBottom, required this.ground, required this.accent, required this.weather, required this.mod, this.landmark});

  factory EnvSpec.fromBiome(Biome b, {String? mod, String? weather, String? landmark, List<Color>? sky}) {
    final s = b.sky.map((e) => hexColor(e)).toList();
    return EnvSpec(
      biome: b.id,
      skyTop: sky != null && sky.isNotEmpty ? sky.first : (s.isNotEmpty ? s.first : const Color(0xFF6D83C9)),
      skyBottom: sky != null && sky.length > 1 ? sky[1] : (s.length > 1 ? s[1] : const Color(0xFFFFB27A)),
      ground: hexColor(b.ground, const Color(0xFF2B2F3A)),
      accent: hexColor(b.accent, const Color(0xFF0EA5E9)), // واقعي بدل النيون
      weather: weather ?? b.weather,
      mod: mod ?? 'none',
      landmark: landmark,
    );
  }

  bool get night => biome == 'neon' || biome == 'future';
}

class EnvObj {
  final double x, w, h;
  final int k, seed;
  const EnvObj(this.x, this.w, this.h, this.k, this.seed);
}

/// Parallax environments drawn with canvas primitives only. Each biome has a far and a mid layer.
class EnvPainter {
  EnvPainter(this.spec, {int seed = 1}) {
    final r = Random(seed + spec.biome.hashCode);
    double x = 0;
    while (x < tileW) {
      final w = 40 + r.nextDouble() * 70;
      far.add(EnvObj(x, w, 0.12 + r.nextDouble() * 0.23, r.nextInt(4), r.nextInt(1 << 20)));
      x += w * (0.7 + r.nextDouble() * 0.5);
    }
    x = 0;
    while (x < tileW) {
      final w = 30 + r.nextDouble() * 60;
      mid.add(EnvObj(x, w, 0.10 + r.nextDouble() * 0.2, r.nextInt(4), r.nextInt(1 << 20)));
      x += w * (1.1 + r.nextDouble() * 1.4);
    }
    final rr = Random(seed * 7);
    for (var i = 0; i < 9; i++) {
      clouds.add(EnvObj(rr.nextDouble() * tileW, 70 + rr.nextDouble() * 90, 0.05 + rr.nextDouble() * 0.12, 0, i));
    }
    for (var i = 0; i < 40; i++) {
      stars.add(EnvObj(rr.nextDouble() * tileW, 1 + rr.nextDouble() * 1.6, rr.nextDouble() * 0.45, 0, i));
    }
    for (var i = 0; i < _n; i++) {
      _sx[i] = rr.nextDouble();
      _sy[i] = rr.nextDouble();
      _sv[i] = 0.6 + rr.nextDouble() * 0.8;
    }
  }

  final EnvSpec spec;
  static const tileW = 1100.0;
  final List<EnvObj> far = [], mid = [], clouds = [], stars = [];
  static const _n = 150;
  final Float32List _sx = Float32List(_n), _sy = Float32List(_n), _sv = Float32List(_n);
  final Float32List _pts = Float32List(_n * 4);
  final Paint _p = Paint()..isAntiAlias = true;

  // lane ground lines as fractions of the scene height
  static const lanes = [0.70, 0.82, 0.94];
  static const horizonF = 0.52;

  Paint _f(Color c) => _p
    ..shader = null
    ..maskFilter = null
    ..style = PaintingStyle.fill
    ..color = c;
  Paint _s(Color c, double w) => _p
    ..shader = null
    ..maskFilter = null
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = c;

  Color get _farCol => Color.lerp(spec.skyBottom, const Color(0xFF0B1020), spec.night ? 0.75 : 0.42)!;
  Color get _midCol => Color.lerp(spec.skyBottom, const Color(0xFF0B1020), spec.night ? 0.88 : 0.6)!;

  // ------------------------------------------------------------------ scene
  void paint(Canvas c, Size size, double camX, double t) {
    final W = size.width, H = size.height, hz = H * horizonF;
    // sky
    c.drawRect(Rect.fromLTWH(0, 0, W, hz + 2), _p..style = PaintingStyle.fill..shader = Gradient.linear(Offset.zero, Offset(0, hz), [spec.skyTop, spec.skyBottom]));
    _p.shader = null;
    if (spec.night) {
      for (final s in stars) {
        final tw = 0.45 + 0.55 * sin(t * 2 + s.seed);
        c.drawCircle(Offset((s.x - camX * 0.01) % W, s.h * hz), s.w * (0.6 + 0.4 * tw), _f(Color.fromRGBO(255, 255, 255, 0.35 + 0.5 * tw)));
      }
    }
    _sun(c, W, H, hz, t);
    if (!spec.night) {
      for (final cl in clouds) {
        final x = ((cl.x - camX * 0.04) % (W + 300)) - 150;
        final y = hz * (0.12 + cl.h * 2.2);
        final col = Color.fromRGBO(255, 255, 255, spec.biome == 'snow' ? 0.5 : 0.28);
        c.drawOval(Rect.fromCenter(center: Offset(x, y), width: cl.w, height: cl.w * 0.3), _f(col));
        c.drawOval(Rect.fromCenter(center: Offset(x + cl.w * 0.25, y - cl.w * 0.08), width: cl.w * 0.6, height: cl.w * 0.3), _f(col));
      }
    }
    _layer(c, size, camX, 0.15, far, true, t);
    if (spec.landmark != null) _landmark(c, size, camX, hz);
    _layer(c, size, camX, 0.42, mid, false, t);
    _road(c, size, camX, t);
  }

  void _sun(Canvas c, double W, double H, double hz, double t) {
    final night = spec.night;
    final ctr = Offset(W * 0.74, spec.biome == 'city' ? hz * 0.72 : hz * 0.3);
    final r = H * (spec.biome == 'desert' ? 0.12 : 0.075);
    final col = night ? const Color(0xFFE9ECFF) : (spec.biome == 'snow' ? const Color(0xFFFFFFFF) : const Color(0xFFFFF1B8));
    c.drawCircle(ctr, r * 2.6, _p..style = PaintingStyle.fill..shader = Gradient.radial(ctr, r * 2.6, [col.withValues(alpha: night ? 0.25 : 0.5), col.withValues(alpha: 0)]));
    _p.shader = null;
    c.drawCircle(ctr, r, _f(col));
    if (night) c.drawCircle(ctr + Offset(r * 0.3, -r * 0.1), r * 0.85, _f(Color.lerp(spec.skyTop, spec.skyBottom, 0.3)!.withValues(alpha: 0.35)));
  }

  void _layer(Canvas c, Size size, double camX, double par, List<EnvObj> objs, bool isFar, double t) {
    final W = size.width, H = size.height, hz = H * horizonF;
    final off = camX * par;
    final k0 = (off / tileW).floor() - 0, k1 = ((off + W) / tileW).floor();
    for (var k = k0; k <= k1; k++) {
      for (final o in objs) {
        final x = o.x + k * tileW - off;
        if (x > W + 80 || x + o.w < -80) continue;
        final base = isFar ? hz + 2 : hz + 4;
        final h = o.h * H * (isFar ? 1.0 : 1.05);
        _object(c, x, base, o.w, h, o, isFar, t, H);
      }
    }
  }

  void _object(Canvas c, double x, double base, double w, double h, EnvObj o, bool isFar, double t, double H) {
    final col = isFar ? _farCol : _midCol;
    switch (spec.biome) {
      case 'desert':
        if (isFar) {
          final path = Path()
            ..moveTo(x - w, base)
            ..quadraticBezierTo(x + w * 0.4, base - h * 1.1, x + w * 1.6, base)
            ..close();
          c.drawPath(path, _f(col));
        } else if (o.k == 0) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, base - h * 0.9, w * 0.14, h * 0.9), Radius.circular(w * 0.07)), _f(col));
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - w * 0.16, base - h * 0.55, w * 0.14, h * 0.3), Radius.circular(w * 0.07)), _f(col));
          c.drawRect(Rect.fromLTWH(x - w * 0.14, base - h * 0.3, w * 0.2, w * 0.1), _f(col));
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + w * 0.14, base - h * 0.7, w * 0.12, h * 0.25), Radius.circular(w * 0.06)), _f(col));
        } else if (o.k == 1) {
          c.drawOval(Rect.fromLTWH(x, base - h * 0.35, w * 0.9, h * 0.45), _f(col));
        } else {
          c.drawPath(Path()..moveTo(x, base)..lineTo(x + w * 0.5, base - h * 0.8)..lineTo(x + w, base)..close(), _f(col));
        }
        break;
      case 'forest':
        if (isFar) {
          c.drawOval(Rect.fromLTWH(x - w * 0.6, base - h * 1.0, w * 2.2, h * 2.0), _f(col));
        } else {
          final g = Color.lerp(col, const Color(0xFF1B4332), 0.6)!;
          c.drawRect(Rect.fromLTWH(x + w * 0.45, base - h * 0.15, w * 0.1, h * 0.15), _f(const Color(0xFF2B2118)));
          for (var i = 0; i < 3; i++) {
            final ww = w * (1 - i * 0.22), yy = base - h * (0.12 + i * 0.3);
            c.drawPath(Path()..moveTo(x + w * 0.5 - ww * 0.5, yy)..lineTo(x + w * 0.5, yy - h * 0.42)..lineTo(x + w * 0.5 + ww * 0.5, yy)..close(), _f(i.isEven ? g : Color.lerp(g, const Color(0xFF2D6A4F), 0.5)!));
          }
        }
        break;
      case 'snow':
        if (isFar) {
          final hh = h * 1.3;
          c.drawPath(Path()..moveTo(x - w * 0.4, base)..lineTo(x + w * 0.5, base - hh)..lineTo(x + w * 1.4, base)..close(), _f(col));
          c.drawPath(Path()..moveTo(x + w * 0.5, base - hh)..lineTo(x + w * 0.28, base - hh * 0.72)..lineTo(x + w * 0.42, base - hh * 0.78)..lineTo(x + w * 0.55, base - hh * 0.7)..lineTo(x + w * 0.7, base - hh * 0.76)..close(), _f(const Color(0xFFFFFFFF)));
        } else {
          final g = Color.lerp(col, const Color(0xFF1B4332), 0.5)!;
          for (var i = 0; i < 3; i++) {
            final ww = w * (0.9 - i * 0.2), yy = base - h * (0.1 + i * 0.28);
            c.drawPath(Path()..moveTo(x + w * 0.5 - ww * 0.5, yy)..lineTo(x + w * 0.5, yy - h * 0.4)..lineTo(x + w * 0.5 + ww * 0.5, yy)..close(), _f(g));
            c.drawPath(Path()..moveTo(x + w * 0.5 - ww * 0.22, yy - h * 0.2)..lineTo(x + w * 0.5, yy - h * 0.4)..lineTo(x + w * 0.5 + ww * 0.22, yy - h * 0.2)..close(), _f(const Color(0xFFF1FAFF)));
          }
        }
        break;
      case 'neon':
        // ألوان مدينة واقعية هادئة بدل النيون الصارخ
        final neon = [const Color(0xFF8B5CF6), const Color(0xFF0EA5E9), const Color(0xFFF59E0B), const Color(0xFF64748B)][o.k % 4];
        if (isFar) {
          c.drawRect(Rect.fromLTWH(x, base - h, w, h), _f(const Color(0xFF1E293B)));
          c.drawRect(Rect.fromLTWH(x, base - h, w, h), _s(neon.withValues(alpha: 0.32), 1.2));
        } else {
          c.drawRect(Rect.fromLTWH(x, base - h, w, h), _f(const Color(0xFF1E293B)));
          final glow = 0.45 + 0.25 * sin(t * 3 + o.seed);
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + w * 0.12, base - h * 0.85, w * 0.76, h * 0.22), const Radius.circular(3)), _s(neon.withValues(alpha: glow), 1.8));
          c.drawRect(Rect.fromLTWH(x + w * 0.2, base - h * 0.74, w * 0.6, h * 0.05), _f(neon.withValues(alpha: 0.45 * glow)));
          _windows(c, x, base, w, h * 0.55, o.seed, neon);
        }
        break;
      case 'future':
        final cyan = spec.accent;
        if (isFar) {
          final tw = w * 0.5;
          c.drawPath(Path()..moveTo(x, base)..lineTo(x + tw * 0.3, base - h * 1.5)..lineTo(x + tw * 0.7, base - h * 1.5)..lineTo(x + tw, base)..close(), _f(col));
          c.drawLine(Offset(x + tw * 0.5, base), Offset(x + tw * 0.5, base - h * 1.5), _s(cyan.withValues(alpha: 0.4), 1.5));
        } else if (o.k % 2 == 0) {
          c.drawRect(Rect.fromLTWH(x, base - h * 1.1, w * 0.6, h * 1.1), _f(const Color(0xFF07122A)));
          _windows(c, x, base, w * 0.6, h * 1.1, o.seed, cyan);
        } else {
          // elevated rail with a moving pod
          final y = base - h * 1.25;
          c.drawRect(Rect.fromLTWH(x - w, y, w * 3, 3), _f(cyan.withValues(alpha: 0.6)));
          c.drawRect(Rect.fromLTWH(x + w * 0.5, y, 3, h * 1.25), _f(const Color(0xFF0A1A3F)));
          final px = x - w + ((t * 90 + o.seed) % (w * 3));
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px, y - 7, 20, 7), const Radius.circular(3)), _f(Colors2.white.withValues(alpha: 0.85)));
        }
        break;
      default: // city
        if (isFar) {
          c.drawRect(Rect.fromLTWH(x, base - h, w, h), _f(col));
          if (o.k == 0) c.drawRect(Rect.fromLTWH(x + w * 0.45, base - h - h * 0.25, w * 0.06, h * 0.25), _f(col));
        } else {
          c.drawRect(Rect.fromLTWH(x, base - h, w, h), _f(col));
          c.drawRect(Rect.fromLTWH(x, base - h, w, 3), _f(Color.lerp(col, Colors2.white, 0.12)!));
          _windows(c, x, base, w, h, o.seed, spec.accent);
        }
    }
  }

  void _windows(Canvas c, double x, double base, double w, double h, int seed, Color lit) {
    final rows = max(2, (h / 14).floor()), cols = max(1, (w / 12).floor());
    final r = Random(seed);
    final cw = w / (cols + 1), ch = h / (rows + 1);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        if (r.nextDouble() < 0.55) c.drawRect(Rect.fromLTWH(x + cw * (j + 0.5), base - h + ch * (i + 0.6), cw * 0.55, ch * 0.45), _f(lit.withValues(alpha: 0.75)));
      }
    }
  }

  void _road(Canvas c, Size size, double camX, double t) {
    final W = size.width, H = size.height, hz = H * horizonF;
    // verge + road
    c.drawRect(Rect.fromLTWH(0, hz, W, H - hz), _p..style = PaintingStyle.fill..shader = Gradient.linear(Offset(0, hz), Offset(0, H), [Color.lerp(spec.ground, const Color(0xFF000000), 0.35)!, spec.ground, Color.lerp(spec.ground, const Color(0xFF000000), 0.2)!], [0, 0.25, 1]));
    _p.shader = null;
    // barrier blocks (fast parallax)
    final bw = H * 0.09;
    final off = camX % (bw * 2);
    for (var x = -off; x < W; x += bw * 2) {
      c.drawRect(Rect.fromLTWH(x, hz, bw, H * 0.022), _f(spec.biome == 'snow' ? const Color(0xFFE63946) : const Color(0xFFE5383B)));
      c.drawRect(Rect.fromLTWH(x + bw, hz, bw, H * 0.022), _f(const Color(0xFFF1F1F1)));
    }
    // lane dashes
    final dashW = H * 0.14, gap = H * 0.12;
    final dOff = camX % (dashW + gap);
    for (final ly in [(lanes[0] + lanes[1]) / 2 + 0.03, (lanes[1] + lanes[2]) / 2 + 0.03]) {
      for (var x = -dOff; x < W; x += dashW + gap) {
        c.drawRect(Rect.fromLTWH(x, H * ly, dashW, max(2, H * 0.012)), _f(const Color(0x55FFFFFF)));
      }
    }
    if (spec.biome == 'neon' || spec.biome == 'future') {
      // reflective wet road glow
      c.drawRect(Rect.fromLTWH(0, hz, W, H - hz), _p..style = PaintingStyle.fill..shader = Gradient.linear(Offset(0, hz), Offset(0, H), [spec.accent.withValues(alpha: 0.18), spec.accent.withValues(alpha: 0)]));
      _p.shader = null;
    }
    if (spec.mod == 'ice' || spec.biome == 'snow') {
      c.drawRect(Rect.fromLTWH(0, H * 0.74, W, H * 0.26), _f(const Color(0x1A9BE7FF)));
      final sOff = camX * 1.0;
      for (var i = 0; i < 7; i++) {
        final x = ((i * 173.0 - sOff) % (W + 120)) - 60;
        c.drawLine(Offset(x, H * (0.78 + 0.03 * (i % 4))), Offset(x + 50, H * (0.78 + 0.03 * (i % 4))), _s(const Color(0x66FFFFFF), 1.5));
      }
    }
    // foreground posts rushing past: strongest speed cue
    final pw = H * 0.6;
    final poff = (camX * 1.8) % pw;
    for (var x = -poff; x < W + 20; x += pw) {
      c.drawRect(Rect.fromLTWH(x, hz - H * 0.12, 3, H * 0.135), _f(Color.lerp(spec.ground, Colors2.white, 0.2)!));
      c.drawRect(Rect.fromLTWH(x - 6, hz - H * 0.12, 15, 3), _f(Color.lerp(spec.ground, Colors2.white, 0.25)!));
      if (spec.night) c.drawCircle(Offset(x + 1.5, hz - H * 0.115), 4, _f(spec.accent.withValues(alpha: 0.9)));
    }
  }

  // ------------------------------------------------------------------ landmarks
  void _landmark(Canvas c, Size size, double camX, double hz) {
    final W = size.width, H = size.height;
    final off = camX * 0.15;
    final x0 = W * 0.62 - (off % (tileW * 1.4));
    final x = x0;
    if (x < -300 || x > W + 300) return;
    final col = Color.lerp(spec.skyBottom, const Color(0xFF0B1020), 0.6)!;
    final s = H * 0.42;
    final base = hz + 2;
    final p = _f(col);
    switch (spec.landmark) {
      case 'lighthouse':
        c.drawPath(Path()..moveTo(x - s * 0.06, base)..lineTo(x - s * 0.03, base - s * 0.8)..lineTo(x + s * 0.03, base - s * 0.8)..lineTo(x + s * 0.06, base)..close(), p);
        c.drawRect(Rect.fromLTWH(x - s * 0.05, base - s * 0.9, s * 0.1, s * 0.1), _f(const Color(0xFFFFE066)));
        c.drawPath(Path()..moveTo(x - s * 0.06, base - s * 0.9)..lineTo(x, base - s * 1.0)..lineTo(x + s * 0.06, base - s * 0.9)..close(), p);
        break;
      case 'eiffel':
        c.drawPath(Path()..moveTo(x - s * 0.28, base)..lineTo(x - s * 0.05, base - s * 0.55)..lineTo(x - s * 0.02, base - s * 1.0)..lineTo(x, base - s * 1.12)..lineTo(x + s * 0.02, base - s * 1.0)..lineTo(x + s * 0.05, base - s * 0.55)..lineTo(x + s * 0.28, base)..lineTo(x + s * 0.16, base)..quadraticBezierTo(x, base - s * 0.3, x - s * 0.16, base)..close(), p);
        c.drawRect(Rect.fromLTWH(x - s * 0.1, base - s * 0.45, s * 0.2, s * 0.03), p);
        break;
      case 'bigben':
        c.drawRect(Rect.fromLTWH(x - s * 0.06, base - s * 0.8, s * 0.12, s * 0.8), p);
        c.drawRect(Rect.fromLTWH(x - s * 0.08, base - s * 0.92, s * 0.16, s * 0.14), p);
        c.drawPath(Path()..moveTo(x - s * 0.08, base - s * 0.92)..lineTo(x, base - s * 1.12)..lineTo(x + s * 0.08, base - s * 0.92)..close(), p);
        c.drawCircle(Offset(x, base - s * 0.85), s * 0.04, _f(const Color(0xFFFFF3B0)));
        c.drawRect(Rect.fromLTWH(x - s * 0.35, base - s * 0.25, s * 0.3, s * 0.25), p);
        break;
      case 'colosseum':
        c.drawOval(Rect.fromLTWH(x - s * 0.45, base - s * 0.34, s * 0.9, s * 0.34), p);
        for (var i = 0; i < 9; i++) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - s * 0.4 + i * s * 0.09, base - s * 0.22, s * 0.04, s * 0.1), Radius.circular(s * 0.02)), _f(Color.lerp(col, Colors2.white, 0.25)!));
        }
        break;
      case 'pyramids':
        c.drawPath(Path()..moveTo(x - s * 0.5, base)..lineTo(x - s * 0.1, base - s * 0.55)..lineTo(x + s * 0.3, base)..close(), p);
        c.drawPath(Path()..moveTo(x + s * 0.05, base)..lineTo(x + s * 0.35, base - s * 0.38)..lineTo(x + s * 0.65, base)..close(), p);
        break;
      case 'burj':
        c.drawPath(Path()..moveTo(x - s * 0.06, base)..lineTo(x - s * 0.03, base - s * 0.6)..lineTo(x - s * 0.012, base - s * 1.15)..lineTo(x, base - s * 1.3)..lineTo(x + s * 0.012, base - s * 1.15)..lineTo(x + s * 0.03, base - s * 0.6)..lineTo(x + s * 0.06, base)..close(), p);
        break;
      case 'gateway':
        c.drawRect(Rect.fromLTWH(x - s * 0.3, base - s * 0.4, s * 0.6, s * 0.4), p);
        c.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x - s * 0.1, base - s * 0.3, s * 0.2, s * 0.3), topLeft: Radius.circular(s * 0.1), topRight: Radius.circular(s * 0.1)), _f(Color.lerp(spec.skyBottom, col, 0.3)!));
        for (final dx in [-0.27, -0.03, 0.21, 0.0]) {
          c.drawCircle(Offset(x + s * dx + s * 0.03, base - s * 0.42), s * 0.035, p);
        }
        break;
      case 'pagoda':
        for (var i = 0; i < 5; i++) {
          final w = s * (0.36 - i * 0.05), y = base - s * (0.12 + i * 0.16);
          c.drawRect(Rect.fromLTWH(x - w * 0.35, y - s * 0.1, w * 0.7, s * 0.1), p);
          c.drawPath(Path()..moveTo(x - w * 0.6, y - s * 0.09)..quadraticBezierTo(x, y - s * 0.17, x + w * 0.6, y - s * 0.09)..lineTo(x + w * 0.45, y - s * 0.12)..lineTo(x - w * 0.45, y - s * 0.12)..close(), p);
        }
        c.drawRect(Rect.fromLTWH(x - s * 0.005, base - s * 1.0, s * 0.01, s * 0.15), p);
        break;
      case 'tokyotower':
        c.drawPath(Path()..moveTo(x - s * 0.18, base)..lineTo(x - s * 0.04, base - s * 0.5)..lineTo(x - s * 0.012, base - s * 1.1)..lineTo(x + s * 0.012, base - s * 1.1)..lineTo(x + s * 0.04, base - s * 0.5)..lineTo(x + s * 0.18, base)..lineTo(x + s * 0.1, base)..lineTo(x, base - s * 0.2)..lineTo(x - s * 0.1, base)..close(), _f(Color.lerp(const Color(0xFFE63946), col, 0.55)!));
        break;
      case 'opera':
        for (var i = 0; i < 4; i++) {
          final sx = x - s * 0.3 + i * s * 0.14;
          c.drawPath(Path()..moveTo(sx, base)..quadraticBezierTo(sx + s * 0.02, base - s * (0.5 - i * 0.05), sx + s * 0.16, base - s * 0.08)..lineTo(sx + s * 0.16, base)..close(), p);
        }
        c.drawRect(Rect.fromLTWH(x - s * 0.35, base - s * 0.05, s * 0.8, s * 0.05), p);
        break;
      case 'christ':
        c.drawPath(Path()..moveTo(x - s * 0.4, base)..quadraticBezierTo(x, base - s * 0.5, x + s * 0.4, base)..close(), p);
        c.drawRect(Rect.fromLTWH(x - s * 0.02, base - s * 0.78, s * 0.04, s * 0.3), p);
        c.drawRect(Rect.fromLTWH(x - s * 0.17, base - s * 0.73, s * 0.34, s * 0.035), p);
        c.drawCircle(Offset(x, base - s * 0.8), s * 0.022, p);
        break;
      case 'liberty':
        c.drawRect(Rect.fromLTWH(x - s * 0.06, base - s * 0.18, s * 0.12, s * 0.18), p);
        c.drawRect(Rect.fromLTWH(x - s * 0.035, base - s * 0.62, s * 0.07, s * 0.44), p);
        c.drawCircle(Offset(x, base - s * 0.66), s * 0.03, p);
        c.drawRect(Rect.fromLTWH(x + s * 0.02, base - s * 0.9, s * 0.02, s * 0.25), p);
        c.drawCircle(Offset(x + s * 0.03, base - s * 0.93), s * 0.028, _f(const Color(0xFFFFD166)));
        break;
    }
  }

  // ------------------------------------------------------------------ weather + overlays
  /// Stateless weather: positions are functions of time, drawn in a single batch.
  void paintWeather(Canvas c, Size size, double t, double speed, {double intensity = 1}) {
    final W = size.width, H = size.height;
    final n = (_n * intensity).clamp(20, _n.toDouble()).toInt();
    switch (spec.weather) {
      case 'rain':
      case 'storm':
        final heavy = spec.weather == 'storm';
        final slant = (heavy ? 0.45 : 0.22) + speed * 0.0004;
        final len = H * (heavy ? 0.09 : 0.06);
        var k = 0;
        for (var i = 0; i < n; i++) {
          final fall = (_sy[i] + t * _sv[i] * (heavy ? 1.6 : 1.1)) % 1.0;
          final x = ((_sx[i] - fall * slant * 0.6) % 1.0) * (W + 60);
          final y = fall * H;
          _pts[k++] = x;
          _pts[k++] = y;
          _pts[k++] = x - len * slant;
          _pts[k++] = y + len;
        }
        c.drawRawPoints(PointMode.lines, Float32List.sublistView(_pts, 0, k), _s(Color.fromRGBO(200, 225, 255, heavy ? 0.6 : 0.45), 1.3));
        if (heavy) {
          final flash = _lightning(t);
          if (flash > 0) {
            c.drawRect(Rect.fromLTWH(0, 0, W, H), _f(Color.fromRGBO(255, 255, 255, 0.55 * flash)));
            final bx = W * (0.2 + 0.6 * ((t / 3.5).floor() * 0.37 % 1));
            final path = Path()..moveTo(bx, 0);
            var y = 0.0, px = bx;
            final r = Random((t / 3.5).floor());
            while (y < H * 0.5) {
              y += H * 0.07;
              px += (r.nextDouble() - 0.5) * W * 0.06;
              path.lineTo(px, y);
            }
            c.drawPath(path, _s(Color.fromRGBO(255, 255, 255, flash), 2.5));
          }
        }
        break;
      case 'snow':
        var k = 0;
        for (var i = 0; i < n; i++) {
          final fall = (_sy[i] + t * 0.12 * _sv[i]) % 1.0;
          _pts[k++] = ((_sx[i] + sin(t * 0.9 + i) * 0.03 - speed * 0.00003 * fall * 10) % 1.0) * W;
          _pts[k++] = fall * H;
        }
        c.drawRawPoints(PointMode.points, Float32List.sublistView(_pts, 0, k), _s(const Color(0xDDFFFFFF), max(2.0, H * 0.012)));
        break;
      case 'dust':
        var k = 0;
        for (var i = 0; i < n; i++) {
          final x = ((_sx[i] - t * 0.5 * _sv[i] - speed * 0.0004) % 1.0) * W;
          _pts[k++] = x;
          _pts[k++] = H * (0.45 + 0.55 * _sy[i]);
          _pts[k++] = x + H * 0.08 * _sv[i];
          _pts[k++] = H * (0.45 + 0.55 * _sy[i]) + 1;
        }
        c.drawRawPoints(PointMode.lines, Float32List.sublistView(_pts, 0, k), _s(const Color(0x66E9C89A), 1.6));
        c.drawRect(Rect.fromLTWH(0, H * horizonF, W, H * 0.48), _f(const Color(0x12E9B872)));
        break;
    }
  }

  double _lightning(double t) {
    final w = (t / 3.5).floor();
    final h = (w * 2654435761) & 0xFFFF;
    if (h % 3 != 0) return 0;
    final tf = w * 3.5 + (h % 100) / 100 * 2.5;
    final d = t - tf;
    if (d < 0 || d > 0.25) return 0;
    return (1 - d / 0.25) * (0.6 + 0.4 * sin(d * 60).abs());
  }

  /// Gameplay modifier overlays (fog, blackout, ice, storm tint).
  void paintOverlay(Canvas c, Size size, Offset focus, double t) {
    final W = size.width, H = size.height;
    switch (spec.mod) {
      case 'fog':
        c.drawRect(Rect.fromLTWH(0, 0, W, H), _f(const Color(0x38E8EEF5)));
        for (var i = 0; i < 4; i++) {
          final x = ((i * 0.31 + t * 0.02 * (1 + i * 0.3)) % 1.4 - 0.2) * W;
          c.drawOval(Rect.fromCenter(center: Offset(x, H * (0.55 + 0.12 * i)), width: W * 0.8, height: H * 0.18), _f(const Color(0x30F1F5F9)));
        }
        break;
      case 'blackout':
        final rect = Rect.fromLTWH(0, 0, W, H);
        final pulse = 0.55 + 0.05 * sin(t * 2);
        c.drawRect(rect, _p..style = PaintingStyle.fill..shader = Gradient.radial(focus, H * 0.95, [const Color(0x00000000), Color.fromRGBO(0, 0, 0, pulse + 0.15)], [0.35, 1]));
        _p.shader = null;
        break;
      case 'ice':
        c.drawRect(Rect.fromLTWH(0, 0, W, H), _f(const Color(0x129BE7FF)));
        break;
      case 'storm':
        c.drawRect(Rect.fromLTWH(0, 0, W, H), _f(const Color(0x22101830)));
        break;
    }
  }
}

/// Tiny color helper so this file avoids importing Material.
class Colors2 {
  static const white = Color(0xFFFFFFFF);
}
