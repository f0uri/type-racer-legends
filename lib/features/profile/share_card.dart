import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../garage/look.dart';
import '../garage/vehicle_painter.dart';

class CardData {
  final String name, title, rankLabel, rankIcon, flag, avatar, footer;
  final int level;
  final List<(String, String)> stats; // label -> value
  final Look? look;
  final String headline; // e.g. "فوز!" or "بطاقة اللاعب"
  final Color accent;
  const CardData({required this.name, required this.title, required this.rankLabel, required this.rankIcon, required this.flag, required this.avatar, required this.level, required this.stats, this.look, this.headline = 'بطاقة اللاعب', this.accent = const Color(0xFF00E5FF), this.footer = 'Type Racer Legends'});
}

/// Renders the shareable player card / post-race card as a PNG (Flutter text engine: proper Arabic shaping).
class ShareCardRenderer {
  static const w = 1080.0, h = 1350.0;

  static TextPainter _tp(String t, double size, Color c, {FontWeight weight = FontWeight.w600, String family = 'Tajawal', double maxWidth = w - 120}) =>
      TextPainter(text: TextSpan(text: t, style: TextStyle(fontFamily: family, fontSize: size, color: c, fontWeight: weight, height: 1.2)), textDirection: TextDirection.rtl, textAlign: TextAlign.center)..layout(maxWidth: maxWidth);

  static void _c(Canvas c, TextPainter tp, double y, {double cx = w / 2}) => tp.paint(c, Offset(cx - tp.width / 2, y));

  static Future<Uint8List> png(CardData d) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, h), const [Color(0xFF1A2150), Color(0xFF0B0F1E), Color(0xFF05070F)], const [0, 0.6, 1]));
    c.drawCircle(const Offset(w * 0.85, 120), 320, Paint()..shader = ui.Gradient.radial(const Offset(w * 0.85, 120), 320, [d.accent.withValues(alpha: 0.35), d.accent.withValues(alpha: 0)]));
    c.drawCircle(const Offset(w * 0.1, h * 0.75), 380, Paint()..shader = ui.Gradient.radial(const Offset(w * 0.1, h * 0.75), 380, [const Color(0xFFFF2BD6).withValues(alpha: 0.25), const Color(0x00FF2BD6)]));
    // frame
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(36, 36, w - 72, h - 72), const Radius.circular(48)), Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = d.accent.withValues(alpha: 0.7));
    _c(c, _tp('TYPE RACER LEGENDS', 38, d.accent, weight: FontWeight.w800, family: 'FiraMono'), 78);
    _c(c, _tp(d.headline, 92, Colors.white, weight: FontWeight.w800), 140);
    // avatar + name
    c.drawCircle(const Offset(w / 2, 420), 110, Paint()..color = const Color(0xFF1D2547));
    c.drawCircle(const Offset(w / 2, 420), 110, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = d.accent);
    _c(c, _tp(d.avatar, 120, Colors.white), 350);
    _c(c, _tp('${d.flag} ${d.name}', 76, Colors.white, weight: FontWeight.w800), 550);
    _c(c, _tp('${d.title}  •  المستوى ${d.level}', 40, const Color(0xFF9AA4C7)), 650);
    _c(c, _tp('${d.rankIcon} ${d.rankLabel}', 52, const Color(0xFFFFD166), weight: FontWeight.w800), 716);
    // vehicle
    if (d.look != null) {
      c.save();
      final L = d.look!.vehicle.isBike ? 330.0 : 420.0;
      c.translate(w / 2 - L / 2, 960);
      VehiclePainter.paint(c, d.look!, L, t: 0.4, showRider: true);
      c.restore();
      c.drawOval(const Rect.fromLTWH(w / 2 - 260, 945, 520, 36), Paint()..color = Colors.black.withValues(alpha: 0.35));
    }
    // stats
    final n = d.stats.length;
    for (var i = 0; i < n; i++) {
      final cx = w * (i + 0.5) / n;
      final box = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, 1120), width: w / n - 28, height: 150), const Radius.circular(24));
      c.drawRRect(box, Paint()..color = const Color(0xFF151B33));
      c.drawRRect(box, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white12);
      _c(c, _tp(d.stats[i].$2, 54, d.accent, weight: FontWeight.w800, family: 'FiraMono', maxWidth: w / n - 50), 1070, cx: cx);
      _c(c, _tp(d.stats[i].$1, 30, const Color(0xFF9AA4C7), maxWidth: w / n - 50), 1140, cx: cx);
    }
    _c(c, _tp(d.footer, 34, const Color(0xFF7C86A8)), 1240);
    _c(c, _tp('جميع المنافسين في اللعبة ذكاء اصطناعي', 26, const Color(0xFF5E688A)), 1286);
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bytes!.buffer.asUint8List();
  }

  static Future<void> share(CardData d, {String text = ''}) async {
    final bytes = await png(d);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/trl-card-${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: text.isEmpty ? 'Type Racer Legends 🏁' : text));
  }
}
