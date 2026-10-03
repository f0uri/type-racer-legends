import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../garage/garage_widgets.dart';
import '../garage/look.dart';
import '../race/game/particles.dart';
import 'economy.dart';

/// Animated chest opening: shake -> lid bursts open with light rays -> loot is revealed.
class ChestOpenScreen extends ConsumerStatefulWidget {
  const ChestOpenScreen({super.key, required this.def, required this.reward});
  final Map<String, dynamic> def;
  final ChestReward reward;
  @override
  ConsumerState<ChestOpenScreen> createState() => _ChestOpenScreenState();
}

class _ChestOpenScreenState extends ConsumerState<ChestOpenScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ParticleSystem ps = ParticleSystem(260);
  final Random rnd = Random();
  double t = 0;
  Duration _last = Duration.zero;
  bool opened = false;
  double openT = 0;

  static const shakeTime = 1.7;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration d) {
    final dt = min(0.05, _last == Duration.zero ? 0.016 : (d - _last).inMicroseconds / 1e6);
    _last = d;
    t += dt;
    if (!opened && t >= shakeTime) _open();
    if (opened) openT += dt;
    if (!opened && t > 0.4 && rnd.nextDouble() < dt * 14) {
      ps.emit(PKind.star, 160 + (rnd.nextDouble() - 0.5) * 120, 210, (rnd.nextDouble() - 0.5) * 40, -40 - rnd.nextDouble() * 40, 0.8, 2.5, hexColor(widget.def['color'] as String?, C.gold));
    }
    ps.update(dt);
    setState(() {});
  }

  void _open() {
    opened = true;
    final a = ref.read(audioProvider);
    a.play(Sfx.chest);
    final cols = [C.gold, Colors.white, hexColor(widget.def['color'] as String?, C.gold), C.cyan];
    ps.burst(PKind.star, 160, 200, 40, speed: 240, colors: cols, life: 1.4, size: 5, g: 120);
    ps.burst(PKind.confetti, 160, 190, 50, speed: 280, colors: cols, life: 2.2, size: 5, g: 260, spread: 3.3, angle: -1.57);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reward;
    final db = ref.watch(contentProvider);
    final skin = r.skinId == null ? null : db.skin(r.skinId!);
    final reveal = Curves.easeOutBack.transform((openT / 0.7).clamp(0.0, 1.0));
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerRight, child: Text(loc(widget.def['name']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))),
            SizedBox(
              height: 330,
              width: 320,
              child: CustomPaint(painter: _ChestPainter(t: t, openT: opened ? openT : -1, color: hexColor(widget.def['color'] as String?, C.gold), ps: ps)),
            ),
            Expanded(
              child: Opacity(
                opacity: opened ? reveal.clamp(0.0, 1.0) : 0,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * reveal.clamp(0.0, 1.2),
                  child: Column(children: [
                    if (skin != null) ...[
                      const Text('عنصر جديد!', style: TextStyle(fontSize: 18, color: C.gold, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Panel(border: C.rarity(skin.rarity), child: Column(children: [SkinDisplay(skinName: loc(skin.name)), RarityBadge(skin.rarity)])),
                    ],
                    if (r.coins > 0) _line(Icons.monetization_on, '+${fmtInt(r.coins)} عملة${r.duplicateCoins > 0 ? '  (بدل عنصر مكرر)' : ''}', C.gold),
                    if (r.gems > 0) _line(Icons.diamond, '+${r.gems} جوهرة', C.cyan),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: NeonButton(label: opened && openT > 0.8 ? 'رائع!' : 'اضغط للتخطي', onPressed: () => opened && openT > 0.8 ? Navigator.of(context).pop() : setState(() => t = max(t, shakeTime))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24, color: c),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c)),
        ]),
      );
}

class SkinDisplay extends StatelessWidget {
  const SkinDisplay({super.key, required this.skinName});
  final String skinName;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(8), child: Text(skinName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)));
}

class _ChestPainter extends CustomPainter {
  final double t, openT;
  final Color color;
  final ParticleSystem ps;
  _ChestPainter({required this.t, required this.openT, required this.color, required this.ps});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, base = size.height * 0.78;
    final open = openT >= 0;
    // light rays
    if (open) {
      final a = (1 - (openT / 2.5)).clamp(0.25, 1.0);
      canvas.save();
      canvas.translate(cx, base - 70);
      canvas.rotate(openT * 0.4);
      for (var i = 0; i < 12; i++) {
        canvas.rotate(pi / 6);
        final path = Path()
          ..moveTo(0, 0)
          ..lineTo(-18, -size.height * 0.9)
          ..lineTo(18, -size.height * 0.9)
          ..close();
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.16 * a));
      }
      canvas.restore();
      canvas.drawCircle(Offset(cx, base - 80), 90, Paint()..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.8 * a), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: Offset(cx, base - 80), radius: 90)));
    }
    // shake while closed
    final shake = open ? 0.0 : sin(t * 38) * min(1.0, t / 0.6) * (2 + t * 2.5);
    canvas.save();
    canvas.translate(cx + shake, base);
    final w = 150.0, h = 84.0;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(-w / 2, -h, w, h), const Radius.circular(10));
    canvas.drawRRect(body, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color, Color.lerp(color, Colors.black, 0.5)!]).createShader(body.outerRect));
    canvas.drawRect(Rect.fromLTWH(-w / 2, -h * 0.55, w, 9), Paint()..color = Colors.black.withValues(alpha: 0.35));
    for (final x in [-w * 0.36, w * 0.36]) {
      canvas.drawRect(Rect.fromLTWH(x - 6, -h, 12, h), Paint()..color = Colors.black.withValues(alpha: 0.3));
    }
    // lid (hinged at the back)
    final lidAngle = open ? -min(1.15, openT * 4) : -sin(t * 38 + 1) * 0.03 * min(1.0, t / 0.6);
    canvas.save();
    canvas.translate(0, -h);
    canvas.translate(0, 0);
    canvas.rotate(lidAngle);
    final lid = RRect.fromRectAndCorners(Rect.fromLTWH(-w / 2, -34, w, 34), topLeft: const Radius.circular(40), topRight: const Radius.circular(40), bottomLeft: const Radius.circular(4), bottomRight: const Radius.circular(4));
    canvas.drawRRect(lid, Paint()..color = Color.lerp(color, Colors.white, 0.15)!);
    canvas.drawRect(Rect.fromLTWH(-w / 2, -8, w, 8), Paint()..color = Colors.black.withValues(alpha: 0.3));
    canvas.restore();
    // lock
    if (!open) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -h), width: 26, height: 26), const Radius.circular(6)), Paint()..color = C.gold);
      canvas.drawCircle(Offset(0, -h), 4, Paint()..color = Colors.black87);
    }
    canvas.restore();
    // particles are in a 320x330 space
    ps.render(canvas);
  }

  @override
  bool shouldRepaint(covariant _ChestPainter old) => true;
}
