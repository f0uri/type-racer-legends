import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

enum PKind { dot, spark, smoke, confetti, star, ring }

/// Fixed-capacity particle pool: no allocations while racing. Dead slots are recycled in a ring.
class ParticleSystem {
  ParticleSystem(this.capacity)
      : x = Float32List(capacity),
        y = Float32List(capacity),
        vx = Float32List(capacity),
        vy = Float32List(capacity),
        life = Float32List(capacity),
        maxLife = Float32List(capacity),
        size = Float32List(capacity),
        gravity = Float32List(capacity),
        rot = Float32List(capacity),
        color = Int32List(capacity),
        kind = Uint8List(capacity);

  final int capacity;
  final Float32List x, y, vx, vy, life, maxLife, size, gravity, rot;
  final Int32List color;
  final Uint8List kind;
  int _cursor = 0;
  int alive = 0;
  final Paint _paint = Paint()..isAntiAlias = true;
  final Random _rnd = Random();

  void emit(PKind k, double px, double py, double pvx, double pvy, double lifeSec, double sz, Color c, {double g = 0}) {
    // find a free slot (at most capacity probes); if the pool is full, steal the oldest.
    var i = _cursor;
    for (var n = 0; n < capacity; n++) {
      if (life[i] <= 0) break;
      i = (i + 1) % capacity;
    }
    _cursor = (i + 1) % capacity;
    x[i] = px;
    y[i] = py;
    vx[i] = pvx;
    vy[i] = pvy;
    life[i] = lifeSec;
    maxLife[i] = lifeSec;
    size[i] = sz;
    gravity[i] = g;
    rot[i] = _rnd.nextDouble() * 6.28;
    color[i] = c.toARGB32();
    kind[i] = k.index;
  }

  void burst(PKind k, double px, double py, int n, {double speed = 120, double life = 0.8, double size = 3, List<Color> colors = const [Color(0xFFFFFFFF)], double g = 200, double spread = 6.283, double angle = 0}) {
    for (var i = 0; i < n; i++) {
      final a = angle + (_rnd.nextDouble() - 0.5) * spread;
      final s = speed * (0.35 + _rnd.nextDouble() * 0.8);
      emit(k, px, py, cos(a) * s, sin(a) * s, life * (0.6 + _rnd.nextDouble() * 0.6), size * (0.6 + _rnd.nextDouble() * 0.8), colors[_rnd.nextInt(colors.length)], g: g);
    }
  }

  void update(double dt) {
    var a = 0;
    for (var i = 0; i < capacity; i++) {
      if (life[i] <= 0) continue;
      life[i] -= dt;
      if (life[i] <= 0) continue;
      a++;
      vy[i] += gravity[i] * dt;
      x[i] += vx[i] * dt;
      y[i] += vy[i] * dt;
      rot[i] += dt * 6;
    }
    alive = a;
  }

  void render(Canvas c) {
    for (var i = 0; i < capacity; i++) {
      final l = life[i];
      if (l <= 0) continue;
      final t = 1 - l / maxLife[i]; // 0 -> 1
      final col = Color(color[i]);
      final px = x[i], py = y[i];
      switch (PKind.values[kind[i]]) {
        case PKind.dot:
          _paint
            ..style = PaintingStyle.fill
            ..color = col.withValues(alpha: col.a * (1 - t));
          c.drawCircle(Offset(px, py), size[i] * (1 - t * 0.5), _paint);
          break;
        case PKind.spark:
          _paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1, size[i] * 0.6)
            ..strokeCap = StrokeCap.round
            ..color = col.withValues(alpha: col.a * (1 - t));
          c.drawLine(Offset(px, py), Offset(px - vx[i] * 0.04, py - vy[i] * 0.04), _paint);
          break;
        case PKind.smoke:
          _paint
            ..style = PaintingStyle.fill
            ..color = col.withValues(alpha: col.a * 0.5 * (1 - t));
          c.drawCircle(Offset(px, py), size[i] * (1 + t * 2.2), _paint);
          break;
        case PKind.confetti:
          _paint
            ..style = PaintingStyle.fill
            ..color = col.withValues(alpha: col.a * (1 - t * t));
          c.save();
          c.translate(px, py);
          c.rotate(rot[i]);
          c.drawRect(Rect.fromCenter(center: Offset.zero, width: size[i] * 1.6, height: size[i] * 0.8 * (0.3 + 0.7 * cos(rot[i] * 2).abs())), _paint);
          c.restore();
          break;
        case PKind.star:
          _paint
            ..style = PaintingStyle.fill
            ..color = col.withValues(alpha: col.a * (1 - t));
          c.save();
          c.translate(px, py);
          c.rotate(rot[i] * 0.5);
          final s = size[i] * (1 - t * 0.3);
          c.drawRect(Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 0.4), _paint);
          c.drawRect(Rect.fromCenter(center: Offset.zero, width: s * 0.4, height: s * 2), _paint);
          c.restore();
          break;
        case PKind.ring:
          _paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = col.withValues(alpha: col.a * (1 - t));
          c.drawCircle(Offset(px, py), size[i] * (0.3 + t * 2), _paint);
          break;
      }
    }
  }

  void clear() {
    life.fillRange(0, capacity, 0);
    alive = 0;
  }
}
