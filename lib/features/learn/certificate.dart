import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'learn_logic.dart';

/// WPM certificate. Arabic text cannot be shaped by the `pdf` package, so the page is drawn with Flutter's text engine
/// (full Arabic shaping, bundled Tajawal font), encoded as PNG and embedded in a PDF page.
class CertificateRenderer {
  static const w = 1754.0, h = 1240.0; // A4 landscape at 150 dpi

  static TextPainter _tp(String t, double size, Color c, {FontWeight weight = FontWeight.w500, String family = 'Tajawal', double? letterSpacing, TextAlign align = TextAlign.center, double maxWidth = w}) =>
      TextPainter(text: TextSpan(text: t, style: TextStyle(fontFamily: family, fontSize: size, color: c, fontWeight: weight, letterSpacing: letterSpacing, height: 1.25)), textDirection: TextDirection.rtl, textAlign: align)..layout(maxWidth: maxWidth);

  static void _center(Canvas c, TextPainter tp, double y, {double cx = w / 2}) => tp.paint(c, Offset(cx - tp.width / 2, y));

  static Future<Uint8List> png(CertificateData d) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const gold = Color(0xFFD4A63A), ink = Color(0xFF1B2242), paper = Color(0xFFFFFBF0);
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = paper);
    // ornamental border
    c.drawRect(const Rect.fromLTWH(40, 40, w - 80, h - 80), Paint()..style = PaintingStyle.stroke..strokeWidth = 10..color = gold);
    c.drawRect(const Rect.fromLTWH(62, 62, w - 124, h - 124), Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = ink);
    for (final o in [const Offset(62, 62), const Offset(w - 62, 62), const Offset(62, h - 62), const Offset(w - 62, h - 62)]) {
      c.drawCircle(o, 26, Paint()..color = gold);
      c.drawCircle(o, 12, Paint()..color = paper);
    }
    // header band
    c.drawRect(const Rect.fromLTWH(62, 62, w - 124, 190), Paint()..color = ink);
    _center(c, _tp('TYPE RACER LEGENDS', 54, gold, weight: FontWeight.w800, family: 'FiraMono', letterSpacing: 8), 92);
    _center(c, _tp('شهادة سرعة الكتابة', 92, Colors.white, weight: FontWeight.w800), 150);
    _center(c, _tp('تشهد لعبة Type Racer Legends بأن', 46, ink), 300);
    // name
    final name = _tp(d.name, 120, const Color(0xFF8A5A00), weight: FontWeight.w800, maxWidth: w - 400);
    _center(c, name, 370);
    c.drawLine(Offset(w / 2 - 420, 370 + name.height + 14), Offset(w / 2 + 420, 370 + name.height + 14), Paint()..color = gold..strokeWidth = 3);
    _center(c, _tp('قد حقق في اختبار الكتابة الرسمي (${d.seconds} ثانية) سرعة', 46, ink), 560);
    // big wpm
    _center(c, _tp(d.wpm.toStringAsFixed(0), 250, ink, weight: FontWeight.w800, family: 'FiraMono', maxWidth: 700), 620);
    _center(c, _tp('كلمة في الدقيقة (WPM)', 52, const Color(0xFF4A5170), weight: FontWeight.w700), 890);
    // stats row
    Widget3(c, 'الدقة', '${d.accuracy.toStringAsFixed(1)}%', w * 0.22);
    Widget3(c, 'المستوى', d.level, w * 0.5);
    Widget3(c, 'الأحرف', '${d.chars}', w * 0.78);
    // footer
    final date = '${d.date.year}/${d.date.month.toString().padLeft(2, '0')}/${d.date.day.toString().padLeft(2, '0')}';
    _center(c, _tp('التاريخ: $date', 38, ink), 1085, cx: w * 0.25);
    _center(c, _tp('رمز التحقق: ${d.code}', 38, ink, family: 'FiraMono', weight: FontWeight.w700), 1085, cx: w * 0.75);
    _center(c, _tp('اختبار بدون مكافآت أو معززات اللعبة — لعب نقي', 28, const Color(0xFF6A7193)), 1150);
    // seal
    c.drawCircle(const Offset(w / 2, 1060), 70, Paint()..color = gold);
    c.drawCircle(const Offset(w / 2, 1060), 58, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = paper);
    _center(c, _tp('★', 70, paper, weight: FontWeight.w800), 1020);
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bytes!.buffer.asUint8List();
  }

  // ignore: non_constant_identifier_names
  static void Widget3(Canvas c, String label, String value, double cx) {
    const ink = Color(0xFF1B2242);
    final box = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, 1010 - 40), width: 400, height: 150), const Radius.circular(24));
    c.drawRRect(box, Paint()..color = const Color(0xFFF3E8C8));
    _center(c, _tp(label, 34, const Color(0xFF6A5A2A)), 1010 - 40 - 62, cx: cx);
    _center(c, _tp(value, 56, ink, weight: FontWeight.w800, maxWidth: 380), 1010 - 40 - 18, cx: cx);
  }

  static Future<Uint8List> pdf(CertificateData d) async {
    final image = pw.MemoryImage(await png(d));
    final doc = pw.Document(title: 'Type Racer Legends - WPM Certificate', author: 'Type Racer Legends');
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4.landscape, margin: pw.EdgeInsets.zero, build: (_) => pw.FullPage(ignoreMargins: true, child: pw.Image(image, fit: pw.BoxFit.cover))));
    return doc.save();
  }

  /// Writes the PDF to the temp folder and opens the share sheet.
  static Future<void> share(CertificateData d) async {
    final bytes = await pdf(d);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/WPM-Certificate-${d.code}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], text: 'شهادة سرعة الكتابة: ${d.wpm.round()} WPM — ${d.code}'));
  }

  static double jitter(int seed) => Random(seed).nextDouble();
}
