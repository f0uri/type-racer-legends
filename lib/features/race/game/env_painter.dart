import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import '../../../data/models/content_models.dart';
import '../../garage/look.dart';

// ── C# Style: محرك بيئات أسطوري واقعي بدون نيون — منقول من JS الأصلي ──

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
      accent: hexColor(b.accent, const Color(0xFF0EA5E9)),
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

/// ثيم أسطوري — مطابق تماماً للـ JS المعطى — C# style
class _Theme {
  final String name;
  final List<Color> sky;
  final String sun; // dusk, day, moon
  final Color gA, gB;
  final List<Color> roadP;
  final Color barA, barB;
  final Color haze; final double hazeA;
  final Color far, near;
  final String kind; // city, desert
  final Color cloud; final Color win;
  final bool stars, rain, wet;
  const _Theme({
    required this.name, required this.sky, required this.sun,
    required this.gA, required this.gB, required this.roadP,
    required this.barA, required this.barB, required this.haze, required this.hazeA,
    required this.far, required this.near, required this.kind,
    required this.cloud, required this.win,
    this.stars=false, this.rain=false, this.wet=false,
  });
}

const _themes = [
  _Theme(name:'غروب المدينة', sky:const [Color(0xFF0B0E15), Color(0xFF2A1B2E), Color(0xFFB14A0C), Color(0xFFFF9A1F)], sun:'dusk', gA:const Color(0xFF1D232C), gB:const Color(0xFF171C24), roadP:const [Color(0xFF2D323C), Color(0xFF30353F), Color(0xFF292D36), Color(0xFF2C3039)], barA:const Color(0xFF8D96A5), barB:const Color(0xFFC4CAD4), haze:const Color(0xFFFF8C28), hazeA:0.5, far:const Color(0xFF2A2230), near:const Color(0xFF141821), kind:'city', cloud:const Color(0x72FFAA5A), win:const Color(0xFFFFB74D)),
  _Theme(name:'صحراء الظهيرة', sky:const [Color(0xFF2F78B5), Color(0xFF78B8E0), Color(0xFFF2D3A0), Color(0xFFFFE2B0)], sun:'day', gA:const Color(0xFFD4A062), gB:const Color(0xFFC99557), roadP:const [Color(0xFF575A63), Color(0xFF5B5E67), Color(0xFF515459), Color(0xFF54575F)], barA:const Color(0xFFE8E2D6), barB:const Color(0xFFC0452B), haze:const Color(0xFFFFE2B4), hazeA:0.55, far:const Color(0xFFC58A55), near:const Color(0xFFA8703F), kind:'desert', cloud:const Color(0xB3FFFFFF), win:const Color(0xFFFFFFFF)),
  _Theme(name:'ليل ممطر', sky:const [Color(0xFF04060A), Color(0xFF0C1220), Color(0xFF182740), Color(0xFF2A3C58)], sun:'moon', gA:const Color(0xFF0E131A), gB:const Color(0xFF0A0F15), roadP:const [Color(0xFF1F242C), Color(0xFF222730), Color(0xFF1C2027), Color(0xFF20252D)], barA:const Color(0xFF59616F), barB:const Color(0xFF7B8494), haze:const Color(0xFF465F82), hazeA:0.55, far:const Color(0xFF0B0F17), near:const Color(0xFF0F1520), kind:'city', cloud:const Color(0x803C506E), win:const Color(0xFFFFC14D), stars:true, rain:true, wet:true),
];

_Theme _pickTheme(String biome) {
  if (biome == 'desert') return _themes[1];
  if (biome == 'neon' || biome == 'future' || biome == 'snow') return _themes[2];
  return _themes[0];
}

double _hash(num n) {
  final x = sin(n * 127.1 + 31.7) * 43758.5453;
  return x - x.floor();
}

final Map<String, Color> _shCache = {};
Color _shade(Color hex, double f) {
  final v0 = hex.value;
  final k = '$v0:$f';
  if (_shCache.containsKey(k)) return _shCache[k]!;
  int r = (v0 >> 16) & 255, g = (v0 >> 8) & 255, b = v0 & 255;
  final t = f < 0 ? 0 : 255;
  final a = f.abs();
  r = ((t - r) * a + r).round().clamp(0, 255);
  g = ((t - g) * a + g).round().clamp(0, 255);
  b = ((t - b) * a + b).round().clamp(0, 255);
  final c = Color.fromARGB(255, r, g, b);
  _shCache[k] = c;
  return c;
}

/// Parallax environments — C# encapsulation, legendary rendering
class EnvPainter {
  EnvPainter(this.spec, {int seed = 1}) {
    final r = Random(seed + spec.biome.hashCode);
    const tileW0 = 1100.0;
    double x = 0;
    while (x < tileW0) {
      final w = 40 + r.nextDouble() * 70;
      far.add(EnvObj(x, w, 0.12 + r.nextDouble() * 0.23, r.nextInt(4), r.nextInt(1 << 20)));
      x += w * (0.7 + r.nextDouble() * 0.5);
    }
    x = 0;
    while (x < tileW0) {
      final w = 30 + r.nextDouble() * 60;
      mid.add(EnvObj(x, w, 0.10 + r.nextDouble() * 0.2, r.nextInt(4), r.nextInt(1 << 20)));
      x += w * (1.1 + r.nextDouble() * 1.4);
    }
    final rr = Random(seed * 7);
    for (var i = 0; i < 9; i++) {
      clouds.add(EnvObj(rr.nextDouble() * tileW0, 70 + rr.nextDouble() * 90, 0.05 + rr.nextDouble() * 0.12, 0, i));
    }
    for (var i = 0; i < 40; i++) {
      stars.add(EnvObj(rr.nextDouble() * tileW0, 1 + rr.nextDouble() * 1.6, rr.nextDouble() * 0.45, 0, i));
    }
    for (var i = 0; i < _n; i++) {
      _sx[i] = rr.nextDouble();
      _sy[i] = rr.nextDouble();
      _sv[i] = 0.6 + rr.nextDouble() * 0.8;
    }
    for (var i = 0; i < 80; i++) {
      _rain.add(_Rain(rr.nextDouble(), rr.nextDouble(), 0.6 + rr.nextDouble() * 0.6));
    }
    _theme = _pickTheme(spec.biome);
  }

  final EnvSpec spec;
  late final _Theme _theme;
  static const tileW = 1100.0;
  final List<EnvObj> far = [], mid = [], clouds = [], stars = [];
  static const _n = 150;
  final Float32List _sx = Float32List(_n), _sy = Float32List(_n), _sv = Float32List(_n);
  final Float32List _pts = Float32List(_n * 4);
  final List<_Rain> _rain = [];
  final Paint _p = Paint()..isAntiAlias = true;

  static const lanes = [0.70, 0.82, 0.94];
  static const horizonF = 0.52;

  Paint _f(Color c) => _p..shader = null..maskFilter = null..style = PaintingStyle.fill..color = c;
  Paint _s(Color c, double w) => _p..shader = null..maskFilter = null..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round..color = c;

  Color get _farCol => Color.lerp(_theme.far, const Color(0xFF0B1020), spec.night ? 0.22 : 0.12)!;
  Color get _midCol => Color.lerp(_theme.near, const Color(0xFF0B1020), spec.night ? 0.18 : 0.10)!;

  double _curveAt(double dist) => 0.012 * sin(dist * 0.0026);

  // ── Public API kept compatible with RaceGame ──
  void paint(Canvas c, Size size, double camX, double t) {
    final W = size.width, H = size.height;
    final hy = H * horizonF;
    final th = _theme;
    final curve = _curveAt(camX);
    // sky gradient — JS: skyC
    final skySh = Gradient.linear(Offset(0, 0), Offset(0, hy), th.sky, List.generate(th.sky.length, (i) => i / (th.sky.length - 1)));
    c.drawRect(Rect.fromLTWH(0, 0, W, hy + 2), _p..style = PaintingStyle.fill..shader = skySh);
    _p.shader = null;
    if (th.stars) {
      for (final s in stars) {
        final tw = 0.45 + 0.55 * sin(t * 2 + s.seed);
        c.drawCircle(Offset((s.x - camX * 0.01) % W, s.h * hy), s.w * (0.6 + 0.4 * tw), _f(Color.fromRGBO(255, 255, 255, 0.35 + 0.5 * tw)));
      }
    }
    _drawSun(c, W, H, hy, t, camX, curve);
    if (!th.stars) {
      for (final cl in clouds) {
        final x = ((cl.x - camX * 0.04) % (W + 300)) - 150;
        final y = hy * (0.12 + cl.h * 2.2);
        final col = th.kind == 'desert' ? const Color(0xB3FFFFFF) : Color.fromRGBO(255, 255, 255, 0.28);
        c.drawOval(Rect.fromCenter(center: Offset(x, y), width: cl.w, height: cl.w * 0.3), _f(col));
        c.drawOval(Rect.fromCenter(center: Offset(x + cl.w * 0.25, y - cl.w * 0.08), width: cl.w * 0.6, height: cl.w * 0.3), _f(col));
      }
    }
    _layer(c, size, camX, 0.15, far, true, t, curve, hy);
    if (spec.landmark != null) _landmark(c, size, camX, hy);
    _layer(c, size, camX, 0.42, mid, false, t, curve, hy);
    _road(c, size, camX, t, hy, curve);
  }

  void _drawSun(Canvas c, double W, double H, double hy, double t, double camX, double curve) {
    final th = _theme;
    final sx = W * 0.5 + curve * W * 0.12 - camX * W * 0.03;
    if (th.sun == 'dusk') {
      final ctr = Offset(sx, hy - H * 0.012);
      final sg = Gradient.radial(ctr, W * 0.55, [const Color(0xF2FFD666), const Color(0x80FF961E), const Color(0x00FF7A00)]);
      c.drawRect(Rect.fromLTWH(-60, -60, W + 120, hy + 62), _p..style = PaintingStyle.fill..shader = sg);
      _p.shader = null;
      c.drawCircle(ctr, W * 0.05, _f(const Color(0xF2FFECAA)));
    } else if (th.sun == 'day') {
      final sy = hy - H * 0.25, sg = Gradient.radial(Offset(sx, sy), W * 0.5, [const Color(0xF2FFFFFF), const Color(0x8CFFF8D2), const Color(0x00FFF0C8)]);
      c.drawRect(Rect.fromLTWH(-60, -60, W + 120, hy + 62), _p..style = PaintingStyle.fill..shader = sg);
      _p.shader = null;
    } else {
      final mx = W * 0.74 - camX * W * 0.02, my = hy - H * 0.27;
      final mg = Gradient.radial(Offset(mx, my), W * 0.28, [const Color(0x80C8DCFF), const Color(0x00C8DCFF)]);
      c.drawRect(Rect.fromLTWH(mx - W * 0.3, my - W * 0.3, W * 0.6, W * 0.6), _p..style = PaintingStyle.fill..shader = mg);
      _p.shader = null;
      c.drawCircle(Offset(mx, my), W * 0.03, _f(const Color(0xFFDFE9FF)));
    }
  }

  void _layer(Canvas c, Size size, double camX, double par, List<EnvObj> objs, bool isFar, double t, double curve, double hy) {
    final W = size.width, H = size.height;
    final off = camX * par + curve * W * (isFar ? 0.08 : 0.2);
    final k0 = (off / tileW).floor() - 0, k1 = ((off + W) / tileW).floor();
    for (var k = k0; k <= k1; k++) {
      for (final o in objs) {
        final x = o.x + k * tileW - off;
        if (x > W + 80 || x + o.w < -80) continue;
        final base = isFar ? hy + 2 : hy + 4;
        final h = o.h * H * (isFar ? 1.0 : 1.05);
        _object(c, x, base, o.w, h, o, isFar, t, H, isFar ? _farCol : _midCol);
      }
    }
  }

  void _object(Canvas c, double x, double base, double w, double h, EnvObj o, bool isFar, double t, double H, Color col) {
    final th = _theme;
    switch (th.kind) {
      case 'desert':
        if (isFar) {
          final path = Path()..moveTo(x - w, base)..quadraticBezierTo(x + w * 0.4, base - h * 1.1, x + w * 1.6, base)..close();
          c.drawPath(path, _f(col));
        } else if (o.k == 0) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, base - h * 0.9, w * 0.14, h * 0.9), Radius.circular(w * 0.07)), _f(col));
        } else {
          c.drawPath(Path()..moveTo(x, base)..lineTo(x + w * 0.5, base - h * 0.8)..lineTo(x + w, base)..close(), _f(col));
        }
        break;
      default: // city — uses th.far/near already, but we use col
        if (isFar) {
          c.drawRect(Rect.fromLTWH(x, base - h, w, h), _f(col));
          if (o.k == 0) c.drawRect(Rect.fromLTWH(x + w * 0.45, base - h - h * 0.25, w * 0.06, h * 0.25), _f(col));
        } else {
          c.drawRect(Rect.fromLTWH(x, base - h, w, h), _f(col));
          c.drawRect(Rect.fromLTWH(x, base - h, w, 3), _f(Color.lerp(col, const Color(0xFFFFFFFF), 0.12)!));
          _windows(c, x, base, w, h, o.seed, th.win);
        }
        break;
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

  void _road(Canvas c, Size size, double camX, double t, double hy, double curve) {
    final W = size.width, H = size.height, rh = H - hy;
    final th = _theme;
    // verge + road with JS band logic simplified to gradient
    c.drawRect(Rect.fromLTWH(0, hy, W, rh), _p..style = PaintingStyle.fill..shader = Gradient.linear(Offset(0, hy), Offset(0, H), [Color.lerp(th.gA, const Color(0xFF000000), 0.20)!, th.gA, Color.lerp(th.gA, const Color(0xFF000000), 0.12)!], [0, 0.25, 1]));
    _p.shader = null;
    final bw = H * 0.09;
    final off = camX % (bw * 2);
    for (var x = -off; x < W; x += bw * 2) {
      c.drawRect(Rect.fromLTWH(x, hy, bw, H * 0.022), _f(th.barA));
      c.drawRect(Rect.fromLTWH(x + bw, hy, bw, H * 0.022), _f(th.barB));
    }
    final dashW = H * 0.14, gap = H * 0.12;
    final dOff = camX % (dashW + gap);
    for (final ly in [(lanes[0] + lanes[1]) / 2 + 0.03, (lanes[1] + lanes[2]) / 2 + 0.03]) {
      for (var x = -dOff; x < W; x += dashW + gap) {
        c.drawRect(Rect.fromLTWH(x, H * ly, dashW, max(2, H * 0.012)), _f(const Color(0x55FFFFFF)));
      }
    }
    if (th.wet) {
      c.drawRect(Rect.fromLTWH(0, hy, W, rh), _p..style = PaintingStyle.fill..shader = Gradient.linear(Offset(0, hy), Offset(0, H), [th.haze.withValues(alpha: 0.10), const Color(0x00000000)]));
      _p.shader = null;
    }
    // haze — غروب/ضباب
    final hz = Gradient.linear(Offset(0, hy - H * 0.05), Offset(0, hy + rh * 0.36), [th.haze.withValues(alpha: 0), th.haze.withValues(alpha: th.hazeA), th.haze.withValues(alpha: 0)]);
    c.drawRect(Rect.fromLTWH(-60, hy - H * 0.05, W + 120, rh * 0.36 + H * 0.05), _p..style = PaintingStyle.fill..shader = hz);
    _p.shader = null;
    // posts
    final pw = H * 0.6;
    final poff = (camX * 1.8) % pw;
    for (var x = -poff; x < W + 20; x += pw) {
      c.drawRect(Rect.fromLTWH(x, hy - H * 0.12, 3, H * 0.135), _f(Color.lerp(th.gA, const Color(0xFFFFFFFF), 0.2)!));
      c.drawRect(Rect.fromLTWH(x - 6, hy - H * 0.12, 15, 3), _f(Color.lerp(th.gA, const Color(0xFFFFFFFF), 0.25)!));
      if (th.stars) c.drawCircle(Offset(x + 1.5, hy - H * 0.115), 4, _f(th.win.withValues(alpha: 0.9)));
    }
  }

  void _landmark(Canvas c, Size size, double camX, double hz) {
    final W = size.width, H = size.height;
    final off = camX * 0.15;
    final x0 = W * 0.62 - (off % (tileW * 1.4));
    final x = x0;
    if (x < -300 || x > W + 300) return;
    final col = Color.lerp(_theme.haze, const Color(0xFF0B1020), 0.55)!;
    final s = H * 0.42;
    final base = hz + 2;
    final p = _f(col);
    switch (spec.landmark) {
      case 'lighthouse':
        c.drawPath(Path()..moveTo(x - s * 0.06, base)..lineTo(x - s * 0.03, base - s * 0.8)..lineTo(x + s * 0.03, base - s * 0.8)..lineTo(x + s * 0.06, base)..close(), p);
        c.drawRect(Rect.fromLTWH(x - s * 0.05, base - s * 0.9, s * 0.1, s * 0.1), _f(const Color(0xFFFFE066)));
        break;
      default:
        c.drawRect(Rect.fromLTWH(x - s * 0.06, base - s * 0.5, s * 0.12, s * 0.5), p);
        break;
    }
  }

  // ── weather — مطابق لـ JS paintWeather ──
  void paintWeather(Canvas c, Size size, double t, double speed, {double intensity = 1}) {
    final W = size.width, H = size.height;
    final th = _theme;
    if (!th.rain) return;
    final n = (80 * intensity).clamp(20, 80).toInt();
    c.strokeCap = StrokeCap.round;
    final p = Paint()..color = const Color(0x59BED7FF)..strokeWidth = 1.2..style = PaintingStyle.stroke;
    for (var i = 0; i < n; i++) {
      final d = _rain[i];
      d.y += 0.016 * d.v * (1.6 + speed * 0.004);
      d.x -= 0.016 * 0.15 * (0.5 + speed * 0.002);
      if (d.y > 1) { d.y = 0; d.x = Random().nextDouble(); }
      if (d.x < 0) d.x += 1;
      final x = d.x * W, y = d.y * H;
      c.drawLine(Offset(x, y), Offset(x - 4 - speed * 0.02, y + 14 + speed * 0.06), p);
    }
  }

  void paintOverlay(Canvas c, Size size, Offset focus, double t) {
    final W = size.width, H = size.height;
    switch (spec.mod) {
      case 'fog':
        c.drawRect(Rect.fromLTWH(0, 0, W, H), _f(const Color(0x38E8EEF5)));
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
    // vignette أسطوري
    final v = Gradient.radial(Offset(W / 2, H * 0.5), H * 0.95, [const Color(0x00000000), const Color(0x80000000)], [0.35, 1]);
    c.drawRect(Rect.fromLTWH(0, 0, W, H), _p..style = PaintingStyle.fill..shader = v);
    _p.shader = null;
  }
}

class _Rain {
  double x, y, v;
  _Rain(this.x, this.y, this.v);
}

class Colors2 {
  static const white = Color(0xFFFFFFFF);
}
