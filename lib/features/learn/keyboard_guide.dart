import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// QWERTY finger map: which finger presses which key.
class Fingers {
  static const rows = [
    ['`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '='],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\\'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'"],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/'],
  ];
  // 0 left pinky, 1 left ring, 2 left middle, 3 left index, 4 thumbs, 5 right index, 6 right middle, 7 right ring, 8 right pinky
  static const _cols = [
    [0, 0, 1, 2, 3, 3, 5, 5, 6, 7, 8, 8, 8],
    [0, 1, 2, 3, 3, 5, 5, 6, 7, 8, 8, 8, 8],
    [0, 1, 2, 3, 3, 5, 5, 6, 7, 8, 8],
    [0, 1, 2, 3, 3, 5, 5, 6, 7, 8],
  ];
  static const names = ['الخنصر الأيسر', 'البنصر الأيسر', 'الوسطى اليسرى', 'السبابة اليسرى', 'الإبهام', 'السبابة اليمنى', 'الوسطى اليمنى', 'البنصر الأيمن', 'الخنصر الأيمن'];
  static const colors = [Color(0xFFFF6B6B), Color(0xFFFFA94D), Color(0xFFFFE066), Color(0xFF69DB7C), Color(0xFF9AA4C7), Color(0xFF4DD4E8), Color(0xFF6C8CFF), Color(0xFFB388FF), Color(0xFFFF8AD8)];
  static const shifted = {'~': '`', '!': '1', '@': '2', '#': '3', r'$': '4', '%': '5', '^': '6', '&': '7', '*': '8', '(': '9', ')': '0', '_': '-', '+': '=', '{': '[', '}': ']', '|': '\\', ':': ';', '"': "'", '<': ',', '>': '.', '?': '/'};

  /// Base key (unshifted) that produces [ch], and whether Shift is needed.
  static ({String key, bool shift})? keyFor(String ch) {
    if (ch == ' ') return (key: ' ', shift: false);
    if (RegExp(r'^[a-z]$').hasMatch(ch)) return (key: ch, shift: false);
    if (RegExp(r'^[A-Z]$').hasMatch(ch)) return (key: ch.toLowerCase(), shift: true);
    if (shifted.containsKey(ch)) return (key: shifted[ch]!, shift: true);
    for (final r in rows) {
      if (r.contains(ch)) return (key: ch, shift: false);
    }
    return null;
  }

  static int? fingerOfKey(String key) {
    if (key == ' ') return 4;
    for (var r = 0; r < rows.length; r++) {
      final i = rows[r].indexOf(key);
      if (i >= 0) return _cols[r][i];
    }
    return null;
  }

  /// Finger for [ch]; Shift is pressed by the pinky of the hand that is not typing the key.
  static int? fingerOf(String ch) => keyFor(ch) == null ? null : fingerOfKey(keyFor(ch)!.key);

  static String describe(String ch) {
    final k = keyFor(ch);
    if (k == null) return '';
    final f = fingerOfKey(k.key);
    if (f == null) return '';
    if (k.key == ' ') return 'الإبهام — مسافة';
    final hand = f <= 3 ? 'الأيمن' : 'الأيسر';
    return '${names[f]}${k.shift ? ' + Shift بالخنصر $hand' : ''}';
  }
}

/// Keyboard drawing with finger colours, the next key highlighted, learned keys and optional heat values.
class KeyboardGuide extends StatelessWidget {
  const KeyboardGuide({super.key, this.next, this.learned = const {}, this.heat, this.showFingers = true, this.compact = false});
  final String? next;
  final Set<String> learned;
  final Map<String, double>? heat; // key -> 0..1 (1 = worst)
  final bool showFingers;
  final bool compact;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: compact ? 3.2 : 2.6,
        child: CustomPaint(painter: _KbPainter(next, learned, heat, showFingers)),
      );
}

class _KbPainter extends CustomPainter {
  final String? next;
  final Set<String> learned;
  final Map<String, double>? heat;
  final bool showFingers;
  _KbPainter(this.next, this.learned, this.heat, this.showFingers);

  @override
  void paint(Canvas canvas, Size size) {
    final nk = next == null ? null : Fingers.keyFor(next!);
    const offsets = [0.0, 0.5, 0.75, 1.25];
    final unit = size.width / 14.6;
    final rowH = size.height / 5.2;
    final p = Paint();
    for (var r = 0; r < Fingers.rows.length; r++) {
      final row = Fingers.rows[r];
      for (var c = 0; c < row.length; c++) {
        final key = row[c];
        final rect = Rect.fromLTWH(offsets[r] * unit + c * unit + 1.5, r * rowH + 2, unit - 3, rowH - 3);
        final f = Fingers.fingerOfKey(key)!;
        var fill = showFingers ? Fingers.colors[f].withValues(alpha: learned.isEmpty || learned.contains(key) ? 0.30 : 0.10) : C.surface2;
        if (heat != null) {
          final h = heat![key] ?? 0;
          fill = Color.lerp(const Color(0xFF1F6F4A), const Color(0xFFE5383B), h.clamp(0.0, 1.0))!.withValues(alpha: heat!.containsKey(key) ? 0.85 : 0.18);
        }
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
        canvas.drawRRect(rr, p..color = fill);
        final isNext = nk != null && nk.key == key;
        final isShiftNeeded = nk != null && nk.shift;
        if (isNext) {
          canvas.drawRRect(rr.inflate(1.5), p..color = C.cyan.withValues(alpha: 0.35));
          canvas.drawRRect(rr, p..color = Fingers.colors[f]);
        }
        canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = isNext ? 2 : 1..color = isNext ? Colors.white : Colors.white24);
        final tp = TextPainter(text: TextSpan(text: key.toUpperCase(), style: TextStyle(fontSize: unit * 0.42, fontWeight: isNext ? FontWeight.w900 : FontWeight.w600, color: isNext ? Colors.black : Colors.white70, fontFamily: 'FiraMono')), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
        // home-row bumps
        if ((key == 'f' || key == 'j') && r == 2) canvas.drawRect(Rect.fromCenter(center: Offset(rect.center.dx, rect.bottom - 4), width: unit * 0.3, height: 2), p..color = Colors.white70);
        if (isShiftNeeded && isNext) {
          // light the opposite shift key
          final left = Fingers.fingerOfKey(key)! > 3;
          final sr = Rect.fromLTWH(left ? 0.0 : size.width - unit * 2.4, 3 * rowH + 2, unit * 2.4, rowH - 3);
          canvas.drawRRect(RRect.fromRectAndRadius(sr, const Radius.circular(5)), p..color = C.gold);
        }
      }
    }
    // shift keys + space
    final spaceRect = Rect.fromLTWH(unit * 3.5, 4 * rowH + 2, unit * 7, rowH - 3);
    final spaceNext = nk != null && nk.key == ' ';
    canvas.drawRRect(RRect.fromRectAndRadius(spaceRect, const Radius.circular(6)), p..color = spaceNext ? Fingers.colors[4] : (showFingers ? Fingers.colors[4].withValues(alpha: 0.25) : C.surface2));
    canvas.drawRRect(RRect.fromRectAndRadius(spaceRect, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..strokeWidth = spaceNext ? 2 : 1..color = spaceNext ? Colors.white : Colors.white24);
    final shiftOn = nk != null && nk.shift;
    for (final left in [true, false]) {
      final sr = Rect.fromLTWH(left ? 0.0 : size.width - unit * 2.4, 3 * rowH + 2, unit * 2.4, rowH - 3);
      if (!shiftOn) {
        canvas.drawRRect(RRect.fromRectAndRadius(sr, const Radius.circular(5)), p..color = C.surface2);
      }
      final tp = TextPainter(text: TextSpan(text: 'SHIFT', style: TextStyle(fontSize: unit * 0.3, color: shiftOn ? Colors.black : Colors.white54, fontWeight: FontWeight.w800)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, sr.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _KbPainter old) => old.next != next || old.learned != learned || old.heat != heat;
}
