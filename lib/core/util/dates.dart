String _two(int n) => n.toString().padLeft(2, '0');

String dayKey([DateTime? t]) {
  final d = t ?? DateTime.now();
  return '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

DateTime parseDayKey(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Monday of the ISO week as key.
String weekKey([DateTime? t]) {
  final d = t ?? DateTime.now();
  final m = DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  return dayKey(m);
}

int daysBetween(String a, String b) {
  final da = parseDayKey(a), db = parseDayKey(b);
  return DateTime.utc(db.year, db.month, db.day).difference(DateTime.utc(da.year, da.month, da.day)).inDays;
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

DateTime? parseIso(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return DateTime.parse(s).toLocal();
  } catch (_) {
    return null;
  }
}

String formatDuration(Duration d) {
  if (d.isNegative) return '0:00';
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return '$h:${_two(m)}:${_two(s)}';
  return '$m:${_two(s)}';
}

String arabicRemaining(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} يوم';
  if (d.inHours >= 1) return '${d.inHours} ساعة';
  return '${d.inMinutes.clamp(0, 59)} دقيقة';
}
