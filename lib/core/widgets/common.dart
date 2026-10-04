import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A short message, in the game's own language: a floating pill that sits *above* the dock.
///
/// A default SnackBar is a full-width bar pinned to the bottom edge — it covers the dock and
/// eats the next press (that is exactly what broke the progress-tab test: the tap aimed at
/// «التقدم» landed on the snackbar's action surface instead).
void toast(BuildContext c, String msg) {
  final m = ScaffoldMessenger.maybeOf(c);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg, textAlign: TextAlign.center),
    duration: const Duration(seconds: 3),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 92),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    backgroundColor: C.surface,
  ));
}

/// The 100 ms a web page does not have: whatever the player presses squashes under the finger
/// and springs back. Wrapped around every tappable surface in the game so a tap is *felt* even
/// before the action happens.
class PressFx extends StatefulWidget {
  const PressFx({super.key, required this.child, this.onTap, this.scale = 0.955});
  final Widget child;
  final VoidCallback? onTap;

  /// How far the surface shrinks while held. Cards ~0.955, small chips ~0.92.
  final double scale;

  @override
  State<PressFx> createState() => _PressFxState();
}

class _PressFxState extends State<PressFx> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => _set(true),
        onTapUp: widget.onTap == null ? null : (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
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
      decoration: BoxDecoration(
        color: color ?? C.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border ?? Colors.white10),
      ),
      // The transparent Material gives every ListTile/SwitchListTile/InkWell inside a panel a
      // paint target *within* the panel. Without it their background and ink splashes are painted
      // on the Scaffold's Material, i.e. behind this opaque colour: invisible on screen, and a
      // debug assertion ("ListTile background color or ink splashes may be invisible") in tests.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    return onTap == null ? w : PressFx(onTap: onTap, child: w);
  }
}

class NeonButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;
  final bool busy;
  final double height;
  const NeonButton({super.key, required this.label, this.icon, this.onPressed, this.color = C.cyan, this.filled = true, this.busy = false, this.height = 52});

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final fg = widget.filled ? Colors.black : widget.color;
    return AnimatedScale(
      scale: _down ? 0.965 : 1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: widget.filled ? widget.color : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: widget.color, width: 1.6)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: enabled ? (_) => _set(false) : null,
          onTapCancel: () => _set(false),
          onTap: enabled ? widget.onPressed : null,
          child: SizedBox(
            height: widget.height,
            child: Center(
              child: widget.busy
                  ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.icon != null) ...[Icon(widget.icon, color: fg, size: 22), const SizedBox(width: 8)],
                      Flexible(child: Text(widget.label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16), overflow: TextOverflow.ellipsis)),
                    ]),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class CurrencyChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final VoidCallback? onTap;
  const CurrencyChip({super.key, required this.icon, required this.color, required this.value, this.onTap});
  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: .5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      ]),
    );
    return onTap == null ? chip : PressFx(onTap: onTap, scale: 0.92, child: chip);
  }
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
  Widget build(BuildContext context) => Text(text, style: displayStyle(size: 21));
}

double degToRad(double d) => d * math.pi / 180;
