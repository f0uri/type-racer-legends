import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../ai/ai_driver.dart';
import '../../garage/look.dart';
import '../../garage/vehicle_painter.dart';
import '../engine/race_models.dart';

/// The pre-race room: instead of dropping the player straight onto the track, the game shows who
/// they are about to race. Your own car drives into frame, the opponents slide in one after
/// another, and then the glowing countdown takes over. A tap skips it.
class MatchIntro extends StatefulWidget {
  const MatchIntro({
    super.key,
    required this.look,
    required this.playerName,
    required this.modeTitle,
    required this.biomeName,
    required this.opponents,
    required this.ghosts,
    required this.onTap,
    this.duration = defaultDuration,
  });

  /// How long the room stays on screen before the lights. The race screen waits on this same
  /// constant (as a compile-time const), so the room can never be cut short by a timer that
  /// drifted from it.
  static const Duration defaultDuration = Duration(milliseconds: 1400);

  final Look look;
  final String playerName, modeTitle, biomeName;
  final List<AiSpec> opponents;
  final List<GhostSpec> ghosts;
  final VoidCallback onTap;
  final Duration duration;

  @override
  State<MatchIntro> createState() => _MatchIntroState();
}

class _MatchIntroState extends State<MatchIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// One curve per element of the intro; every value is 0 before its own cue.
  double _step(double from, double to) => ((_c.value - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    // every rival that will be on the grid, AI first then personal ghosts
    final rivals = <(String, String, bool)>[
      for (final o in widget.opponents) (o.name, '${o.baseWpm.round()} WPM', o.isBoss),
      for (final g in widget.ghosts) (g.name, '${g.wpm.round()} WPM', false),
    ];
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final veil = Curves.easeOut.transform(_step(0, 0.16));
            final chips = Curves.easeOutBack.transform(_step(0.02, 0.30));
            final car = Curves.easeOutCubic.transform(_step(0.06, 0.55));
            return Stack(children: [
              Container(color: Colors.black.withValues(alpha: 0.72 * veil)),
              // top chips: where and what the player is about to race
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 64),
                  child: Opacity(
                    opacity: veil,
                    child: Transform.translate(
                      offset: Offset(0, -18 * (1 - chips)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(widget.modeTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.public, size: 14, color: C.cyan),
                          const SizedBox(width: 5),
                          Text(widget.biomeName, style: const TextStyle(color: C.cyan, fontWeight: FontWeight.w800, fontSize: 13)),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ),
              // the player's own car, driving in
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: Opacity(
                    opacity: Curves.easeOut.transform(_step(0.02, 0.22)),
                    child: Transform.translate(
                      offset: Offset(-260 * (1 - car), 8 * (1 - car)),
                      child: CustomPaint(painter: _IntroCarPainter(widget.look, _c.value * widget.duration.inMilliseconds / 1000)),
                    ),
                  ),
                ),
              ),
              // player badge under the car
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Opacity(
                    opacity: Curves.easeOut.transform(_step(0.22, 0.42)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: C.cyan.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.cyan),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.person, size: 14, color: C.cyan),
                        const SizedBox(width: 6),
                        Text(widget.playerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                      ]),
                    ),
                  ),
                ),
              ),
              // rivals, one row per cue
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < rivals.length && i < 5; i++) _rivalRow(rivals[i], i),
                    ],
                  ),
                ),
              ),
              // bottom hint: the intro is skippable, like every game intro
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 44),
                  child: Opacity(
                    opacity: 0.55 * Curves.easeOut.transform(_step(0.4, 0.7)),
                    child: const Text('اضغط للتخطي', style: TextStyle(fontSize: 11, color: C.textDim)),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _rivalRow((String, String, bool) r, int i) {
    // cue: first rival right after the car, then one every 70 ms
    final t = Curves.easeOutCubic.transform(_step(0.30 + i * 0.075, 0.30 + i * 0.075 + 0.26));
    if (t <= 0) return const SizedBox(height: 30);
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset((1 - t) * 90, 0),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (r.$3 ? C.gold : C.magenta).withValues(alpha: 0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (r.$3) ...[const Icon(Icons.workspace_premium, size: 13, color: C.gold), const SizedBox(width: 4)],
              Text(r.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(width: 7),
              Text(r.$2, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10.5, color: (r.$3 ? C.gold : C.magenta), fontFamily: 'FiraMono')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Side view of the player's car used inside the intro (the real painter, so it is their car).
class _IntroCarPainter extends CustomPainter {
  _IntroCarPainter(this.look, this.t);
  final Look look;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // ground glow under the car
    final gy = size.height * 0.86;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width / 2, gy + 2), width: size.width * 0.42, height: 12),
      Paint()..color = (look.neon ?? C.cyan).withValues(alpha: 0.28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final l = size.width * 0.66;
    canvas.save();
    canvas.translate(size.width / 2, gy);
    canvas.translate(-l / 2, 0);
    VehiclePainter.paint(canvas, look, l, t: t, wheelAngle: t * 6, showRider: true);
    canvas.restore();
    // speed lines behind the car, so it reads as driving in rather than floating
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.16);
    for (var i = 0; i < 5; i++) {
      final y = gy - 20 - i * 16;
      final w = 40.0 + i * 22;
      canvas.drawRect(Rect.fromLTWH(size.width * 0.5 - l * 0.5 - w, y, w, 1.4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _IntroCarPainter old) => old.t != t || old.look != look;
}

/// The glowing countdown: 3 / 2 / 1 with a halo and a shockwave ring per tick, then «انطلق!»
/// with a white flash. Numbers in a game never just appear — they hit the screen.
class GlowCountdown extends StatefulWidget {
  const GlowCountdown({super.key, required this.value, this.size = 108});
  final int value; // 3, 2, 1 — and 0 means «انطلق!»
  final double size;

  @override
  State<GlowCountdown> createState() => _GlowCountdownState();
}

class _GlowCountdownState extends State<GlowCountdown> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final go = widget.value == 0;
    final label = go ? 'انطلق!' : '${widget.value}';
    final color = go ? C.green : C.gold;
    final glow = go ? const Color(0xFF7BFFB0) : const Color(0xFFFFD166);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final punch = Curves.easeOutBack.transform(t.clamp(0.0, 0.55) / 0.55);
        final ring = Curves.easeOutCubic.transform(t);
        // the halo breathes while the number is on screen
        final breathe = 0.75 + 0.25 * math.sin(t * math.pi * 3);
        final flash = go ? (1 - Curves.easeOut.transform((t / 0.45).clamp(0.0, 1.0))) : 0.0;
        return Stack(alignment: Alignment.center, children: [
          // bloom (not a hard rectangle): a soft white burst that expands and dies in ~280 ms
          if (flash > 0)
            Container(
              width: widget.size * (2.2 + 2.4 * (1 - flash)),
              height: widget.size * (2.2 + 2.4 * (1 - flash)),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.5 * flash), Colors.white.withValues(alpha: 0.0)]),
              ),
            ),
          // halo behind the number
          Container(
            width: widget.size * 2.6,
            height: widget.size * 2.6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [glow.withValues(alpha: 0.30 * breathe), glow.withValues(alpha: 0.0)]),
            ),
          ),
          // two shockwave rings, the second one late
          for (final d in const [0.0, 0.18])
            if (t > d)
              Container(
                width: widget.size * (1 + 1.9 * ((ring - d) / (1 - d)).clamp(0.0, 1.0)),
                height: widget.size * (1 + 1.9 * ((ring - d) / (1 - d)).clamp(0.0, 1.0)),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.75 * (1 - ((ring - d) / (1 - d)).clamp(0.0, 1.0))), width: 3),
                ),
              ),
          Transform.scale(
            scale: punch * (go ? 1.12 : 1.0),
            child: Stack(alignment: Alignment.center, children: [
              // outline pass: reads as a neon tube before the fill
              Text(
                label,
                style: TextStyle(
                  fontSize: widget.size,
                  fontWeight: FontWeight.w900,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = Colors.white.withValues(alpha: 0.85),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: widget.size,
                  fontWeight: FontWeight.w900,
                  color: color,
                  shadows: [
                    Shadow(color: glow, blurRadius: 26),
                    Shadow(color: glow.withValues(alpha: 0.75), blurRadius: 60),
                    Shadow(color: glow.withValues(alpha: 0.4), blurRadius: 110),
                  ],
                ),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
