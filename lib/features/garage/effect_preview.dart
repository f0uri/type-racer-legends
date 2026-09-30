import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../race/game/effects.dart';
import '../race/game/particles.dart';
import 'look.dart';
import 'vehicle_painter.dart';

enum EffectMode { exhaust, flame, celebration }

/// Animated strip that previews an exhaust skin, nitro flame or win celebration on the current vehicle.
class EffectPreview extends StatefulWidget {
  const EffectPreview({super.key, required this.look, required this.mode, this.height = 96});
  final Look look;
  final EffectMode mode;
  final double height;
  @override
  State<EffectPreview> createState() => _EffectPreviewState();
}

class _EffectPreviewState extends State<EffectPreview> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ParticleSystem ps = ParticleSystem(220);
  final Random rnd = Random();
  Duration _last = Duration.zero;
  double t = 0, burstCd = 0;
  Size _size = const Size(300, 96);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration d) {
    final dt = min(0.05, _last == Duration.zero ? 0.016 : (d - _last).inMicroseconds / 1e6);
    _last = d;
    t += dt;
    final L = _len();
    final ox = _originX(L);
    final ground = _size.height * 0.88;
    final ex = VehiclePainter.exhaustAnchor(widget.look, L);
    if (widget.mode == EffectMode.exhaust && rnd.nextDouble() < dt * 55) {
      Effects.exhaust(ps, widget.look, ox + ex.dx, ground + ex.dy, -120, t, rnd);
    }
    if (widget.mode == EffectMode.flame && rnd.nextDouble() < dt * 40) {
      final cols = widget.look.flameColors;
      ps.emit(PKind.spark, ox + ex.dx - 6, ground + ex.dy, -240, (rnd.nextDouble() - 0.5) * 60, 0.3, 2.6, cols.isEmpty ? const Color(0xFF7DF9FF) : cols[rnd.nextInt(cols.length)]);
    }
    if (widget.mode == EffectMode.celebration) {
      burstCd -= dt;
      if (burstCd <= 0) {
        burstCd = 2.2;
        Effects.celebrate(ps, widget.look.celebration, widget.look.celebrationColors, _size, Offset(ox, ground));
      }
    }
    ps.update(dt);
    setState(() {});
  }

  double _len() => min(_size.height * 1.15, 130) * (widget.look.vehicle.isBike ? 0.8 : 1);
  double _originX(double L) => _size.width * 0.5 - L * 0.3;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, c) {
          _size = Size(c.maxWidth, widget.height);
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(size: _size, painter: _EffectPainter(this)),
          );
        }),
      );
}

class _EffectPainter extends CustomPainter {
  final _EffectPreviewState s;
  _EffectPainter(this.s);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B2448), Color(0xFF0E1330)]).createShader(Offset.zero & size));
    final ground = size.height * 0.88;
    canvas.drawRect(Rect.fromLTWH(0, ground, size.width, size.height - ground), Paint()..color = const Color(0xFF1C2140));
    final L = s._len();
    canvas.save();
    canvas.translate(s._originX(L), ground);
    VehiclePainter.paint(canvas, s.widget.look, L, t: s.t, wheelAngle: s.t * 14);
    if (s.widget.mode == EffectMode.flame) Effects.flame(canvas, s.widget.look, L, 1, 0, s.t);
    canvas.restore();
    s.ps.render(canvas);
  }

  @override
  bool shouldRepaint(covariant _EffectPainter old) => true;
}
