import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/remote/firebase_boot.dart';
import '../../data/remote/progress_sync.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  String? _error;

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  Future<void> _google() async {
    setState(() => _error = null);
    final err = await ref.read(authProvider.notifier).signInWithGoogle();
    if (mounted && err != null) setState(() => _error = err);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(flex: 2),
              SizedBox(
                height: 150,
                width: double.infinity,
                child: AnimatedBuilder(animation: _ac, builder: (_, _) => CustomPaint(painter: _LogoPainter(_ac.value))),
              ),
              const SizedBox(height: 16),
              const Text('TYPE RACER', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 3, color: C.cyan)),
              const Text('LEGENDS', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 8, color: C.magenta)),
              const SizedBox(height: 10),
              const Text('اكتب أسرع... وتسابق مع الأساطير', style: TextStyle(color: C.textDim, fontSize: 15)),
              if (googleWebClientId.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('سجّل بحساب جوجل ليُحفظ تقدمك (المستوى، العملات، الكراج) في حسابك نفسه وتستعيده على أي جهاز.', textAlign: TextAlign.center, style: TextStyle(color: C.textDim, fontSize: 12)),
                ),
              ],
              const Spacer(flex: 2),
              if (_error != null)
                Panel(color: C.red.withValues(alpha: .15), border: C.red, child: Row(children: [
                  const Icon(Icons.error_outline, color: C.red),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13))),
                ])),
              const SizedBox(height: 14),
              NeonButton(label: 'متابعة كزائر', icon: Icons.person_outline, onPressed: auth.busy ? null : () => ref.read(authProvider.notifier).continueAsGuest()),
              const SizedBox(height: 12),
              NeonButton(label: 'تسجيل الدخول بجوجل', icon: Icons.account_circle, color: C.magenta, filled: false, busy: auth.busy, onPressed: _google),
              const SizedBox(height: 14),
              Text(
                FirebaseBoot.available
                    ? 'سجّل بجوجل لحفظ تقدمك سحابياً واللعب على أكثر من جهاز. الزائر يحفظ محلياً ويمكنه الربط لاحقاً دون فقدان أي تقدم.'
                    : 'وضع الزائر: يُحفظ تقدمك على هذا الجهاز، وتعمل اللعبة بدون إنترنت.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: C.textDim, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double t;
  _LogoPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    // speed lines
    for (var i = 0; i < 9; i++) {
      final y = size.height * (0.15 + i * 0.09);
      final off = ((t * 2 + i * 0.37) % 1.0);
      final x0 = size.width * (1 - off);
      p..color = (i.isEven ? C.cyan : C.magenta).withValues(alpha: 0.15 + 0.5 * (1 - off))..strokeWidth = 2.5;
      canvas.drawLine(Offset(x0, y), Offset(x0 + 60 + i * 6, y), p);
    }
    // car silhouette
    final cx = size.width / 2, cy = size.height * 0.62;
    final body = Path()
      ..moveTo(cx - 80, cy)
      ..quadraticBezierTo(cx - 78, cy - 22, cx - 40, cy - 26)
      ..lineTo(cx - 22, cy - 46)
      ..quadraticBezierTo(cx, cy - 52, cx + 26, cy - 44)
      ..lineTo(cx + 46, cy - 26)
      ..quadraticBezierTo(cx + 86, cy - 22, cx + 84, cy)
      ..close();
    canvas.drawPath(body, Paint()..shader = const LinearGradient(colors: [C.cyan, C.magenta]).createShader(Rect.fromLTWH(cx - 80, cy - 52, 170, 52)));
    final wheel = Paint()..color = Colors.black;
    final rim = Paint()..color = Colors.white70..style = PaintingStyle.stroke..strokeWidth = 3;
    for (final dx in [-46.0, 50.0]) {
      canvas.drawCircle(Offset(cx + dx, cy + 2), 17, wheel);
      canvas.save();
      canvas.translate(cx + dx, cy + 2);
      canvas.rotate(t * 12.56);
      for (var k = 0; k < 5; k++) {
        canvas.drawLine(Offset.zero, const Offset(12, 0), rim);
        canvas.rotate(1.2566);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.t != t;
}
