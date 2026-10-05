import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

void toast(BuildContext c, String msg) {
  final m = ScaffoldMessenger.maybeOf(c);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(msg, textAlign: TextAlign.center), duration: const Duration(seconds: 3)));
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? border;
  final VoidCallback? onTap;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.border, this.onTap});
  @override
  Widget build(BuildContext context) {
    final w = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? C.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border ?? Colors.white10),
      ),
      child: child,
    );
    return onTap == null ? w : GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: w);
  }
}

/// زر عائم بأسلوب iOS — زجاج ضبابي + ظل ناعم + حواف كبيرة
class NeonButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;
  final bool busy;
  final double height;
  const NeonButton({super.key, required this.label, this.icon, this.onPressed, this.color = C.cyan, this.filled = true, this.busy = false, this.height = 52});
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final bg = filled ? color : Colors.white.withValues(alpha: 0.12);
    final fg = filled ? Colors.white : color;
    final borderCol = filled ? Colors.white.withValues(alpha: 0.18) : color.withValues(alpha: 0.35);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 8)),
            BoxShadow(color: color.withValues(alpha: filled ? 0.25 : 0.12), blurRadius: 20, offset: const Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: bg,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderCol, width: 1.2),
                  gradient: filled
                      ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, 0.18)!, color, Color.lerp(color, Colors.black, 0.12)!])
                      : null,
                ),
                child: Center(
                  child: busy
                      ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          if (icon != null) ...[Icon(icon, color: fg, size: 22), const SizedBox(width: 8)],
                          Flexible(child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.2), overflow: TextOverflow.ellipsis)),
                        ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زر دائري عائم (FAB) بأسلوب iPhone
class FloatingCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final double size;
  const FloatingCircleButton({super.key, required this.icon, this.onPressed, this.color = C.cyan, this.size = 56});
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 6)), BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 3))]),
        child: ClipOval(
          child: Material(
            color: color,
            child: InkWell(onTap: onPressed, child: Icon(icon, color: Colors.white, size: size * 0.48)),
          ),
        ),
      );
}

class CurrencyChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final VoidCallback? onTap;
  const CurrencyChip({super.key, required this.icon, required this.color, required this.value, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: .5))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        ),
      );
}

class NewBadge extends StatelessWidget {
  final String text;
  const NewBadge({super.key, this.text = 'جديد'});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
      );
}

class RedDot extends StatelessWidget {
  final Widget child;
  final bool show;
  const RedDot({super.key, required this.child, this.show = true});
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        child,
        if (show) Positioned(top: -2, right: -2, child: Container(width: 11, height: 11, decoration: BoxDecoration(color: C.red, shape: BoxShape.circle, border: Border.all(color: C.bg, width: 1.5)))),
      ]);
}

class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const ProgressBar({super.key, required this.value, this.color = C.cyan, this.height = 10});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(value: value.clamp(0, 1).toDouble(), minHeight: height, backgroundColor: Colors.white12, color: color),
      );
}

class GradientBg extends StatelessWidget {
  final Widget child;
  const GradientBg({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF131A3A), C.bg, Color(0xFF070A14)]),
        ),
        child: child,
      );
}

Widget starRow(int stars, {int max = 3, double size = 18}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(max, (i) => Icon(i < stars ? Icons.star_rounded : Icons.star_border_rounded, size: size, color: i < stars ? C.gold : Colors.white24)),
    );

Future<bool> confirmDialog(BuildContext c, String title, String body, {String ok = 'تأكيد', String cancel = 'إلغاء', Color okColor = C.cyan}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel, style: const TextStyle(color: C.textDim))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok, style: TextStyle(color: okColor, fontWeight: FontWeight.w800))),
      ],
    ),
  );
  return r ?? false;
}

class AppBarTitle extends StatelessWidget {
  final String text;
  const AppBarTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20));
}

double degToRad(double d) => d * math.pi / 180;
