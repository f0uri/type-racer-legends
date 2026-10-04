import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../engine/typing_engine.dart';

/// Renders the text being typed: green = typed, red = wrong, highlighted = current char.
/// Supports the environment modifiers (fog / ice / blackout) purely as a display effect.
class TypingTextPanel extends StatefulWidget {
  const TypingTextPanel({super.key, required this.engine, required this.palette, this.mod = 'none', this.fontScale = 1, this.dyslexia = false, this.hint = true, required this.nowMs, required this.wordStartMs, this.hideAll = false, this.tick = 0});
  final TypingEngine engine;
  final TypingPalette palette;
  final String mod;
  final double fontScale;
  final bool dyslexia;
  final bool hint;
  final int nowMs;
  final int wordStartMs;
  final bool hideAll;
  final int tick; // forces repaint when the parent ticks

  @override
  State<TypingTextPanel> createState() => _TypingTextPanelState();
}

class _TypingTextPanelState extends State<TypingTextPanel> with SingleTickerProviderStateMixin {
  double _scroll = 0;
  double _target = 0;
  String? _cacheKey;
  TextPainter? _cached;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(days: 1))..addListener(_step);
  }

  void _step() {
    if ((_target - _scroll).abs() < 0.4) {
      if (_scroll != _target) setState(() => _scroll = _target);
      _anim.stop();
      return;
    }
    setState(() => _scroll += (_target - _scroll) * 0.25);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  String _shown(TypingEngine e) {
    final text = e.text;
    if (widget.mod != 'ice' && widget.mod != 'blackout') return text;
    final chars = text.split('');
    final ws = e.wordStart, we = e.wordEnd;
    final cur = e.pos + e.wrongBuffer;
    final since = widget.nowMs - widget.wordStartMs;
    if (widget.mod == 'ice') {
      // two neighbouring letters of the current word swap places for a moment, every 1.8 s
      final window = (widget.nowMs ~/ 1800);
      final phase = widget.nowMs % 1800;
      if (phase < 900 && we - ws >= 3) {
        final r = Random(window * 31 + ws);
        final i = cur + r.nextInt(max(1, we - cur - 1));
        if (i + 1 < we && i >= cur) {
          final t = chars[i];
          chars[i] = chars[i + 1];
          chars[i + 1] = t;
        }
      }
    } else if (since > 1000) {
      for (var i = max(cur, ws); i < we; i++) {
        chars[i] = '·';
      }
    }
    return chars.join();
  }

  double _wordAlpha(int wordIndex, int curWord) {
    switch (widget.mod) {
      case 'fog':
        final d = wordIndex - curWord;
        if (d <= 1) return 0.75;
        final h = ((wordIndex * 2654435761) ^ (widget.nowMs ~/ 2200)) & 0xFF;
        return h % 100 < 38 ? 0.12 : 0.55;
      case 'blackout':
        return wordIndex == curWord ? 1 : 0.22;
      default:
        return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    final pal = widget.palette;
    final fam = widget.dyslexia ? 'OpenDyslexic' : 'FiraMono';
    final size = 21.0 * widget.fontScale;
    final base = TextStyle(fontFamily: fam, fontSize: size, height: 1.55, letterSpacing: widget.dyslexia ? 0.8 : 0.3, fontWeight: FontWeight.w500);
    final shown = widget.hideAll ? e.text.replaceAll(RegExp(r'\S'), '·') : _shown(e);
    final pos = e.pos, wrong = e.wrongBuffer;
    final curIdx = pos + wrong;
    final spans = <InlineSpan>[];
    if (pos > 0) spans.add(TextSpan(text: shown.substring(0, pos), style: base.copyWith(color: pal.correct.withValues(alpha: 0.85))));
    if (wrong > 0) {
      spans.add(TextSpan(text: shown.substring(pos, min(shown.length, pos + wrong)), style: base.copyWith(color: Colors.white, backgroundColor: pal.wrong.withValues(alpha: 0.75))));
    }
    if (curIdx < shown.length) {
      spans.add(TextSpan(text: shown[curIdx], style: base.copyWith(color: pal.current, fontWeight: FontWeight.w800, backgroundColor: widget.hint ? C.cyan.withValues(alpha: 0.28) : null, decoration: TextDecoration.underline, decorationColor: C.cyan, decorationThickness: 2.5)));
      final rest = shown.substring(curIdx + 1);
      if (widget.mod == 'none' || widget.mod == 'storm' || widget.mod == 'ice') {
        spans.add(TextSpan(text: rest, style: base.copyWith(color: pal.pending)));
      } else {
        // per-word alpha for fog / blackout
        var wi = _wordIndexAt(e.text, curIdx);
        final cw = wi;
        final buf = StringBuffer();
        final words = rest.split(' ');
        for (var i = 0; i < words.length; i++) {
          if (i == 0) {
            spans.add(TextSpan(text: words[0], style: base.copyWith(color: pal.pending.withValues(alpha: _wordAlpha(wi, cw)))));
          } else {
            wi++;
            spans.add(TextSpan(text: ' ${words[i]}', style: base.copyWith(color: pal.pending.withValues(alpha: _wordAlpha(wi, cw)))));
          }
        }
        buf.clear();
      }
    }
    final span = TextSpan(children: spans);
    return LayoutBuilder(builder: (context, cons) {
      // The panel is repainted up to 10 times a second: lay the text out only when something
      // actually changed (position, wrong buffer, effect phase, size or font).
      final key = '${e.text.hashCode}|$pos|$wrong|$curIdx|${widget.nowMs ~/ 250}|${widget.mod}|'
          '${widget.hint ? 1 : 0}|${widget.fontScale}|${widget.dyslexia ? 1 : 0}|${cons.maxWidth.round()}|${shown.hashCode}';
      final TextPainter tp;
      if (_cacheKey == key && _cached != null) {
        tp = _cached!;
      } else {
        tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout(maxWidth: cons.maxWidth - 4);
        _cacheKey = key;
        _cached = tp;
      }
      final caret = tp.getOffsetForCaret(TextPosition(offset: min(curIdx, shown.length)), Rect.zero);
      final lineH = size * 1.55;
      final want = max(0.0, caret.dy - lineH * 0.9);
      final maxScroll = max(0.0, tp.height - cons.maxHeight);
      final tgt = min(want, maxScroll);
      if ((tgt - _target).abs() > 0.1) {
        _target = tgt;
        if (!_anim.isAnimating) _anim.forward();
      }
      return ClipRect(
        child: CustomPaint(
          size: Size(cons.maxWidth, cons.maxHeight),
          painter: _PanelPainter(tp, _scroll),
        ),
      );
    });
  }

  int _wordIndexAt(String text, int idx) {
    var n = 0;
    for (var i = 0; i < idx && i < text.length; i++) {
      if (text[i] == ' ') n++;
    }
    return n;
  }
}

class _PanelPainter extends CustomPainter {
  final TextPainter tp;
  final double scroll;
  _PanelPainter(this.tp, this.scroll);
  @override
  void paint(Canvas canvas, Size size) => tp.paint(canvas, Offset(2, -scroll));
  @override
  bool shouldRepaint(covariant _PanelPainter old) => true;
}
