import 'dart:math';

final _rng = Random.secure();

String newId([int len = 16]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(len, (_) => chars[_rng.nextInt(chars.length)]).join();
}

/// Localized text lookup for content maps {ar,en,fr}. UI is Arabic-first.
String loc(dynamic m, [String lang = 'ar']) {
  if (m is String) return m;
  if (m is Map) {
    final v = m[lang] ?? m['ar'] ?? m['en'] ?? (m.values.isNotEmpty ? m.values.first : '');
    return v.toString();
  }
  return '';
}

String flagEmoji(String cc) {
  if (cc.length != 2) return '🏳️';
  final a = cc.toUpperCase().codeUnits;
  return String.fromCharCodes([0x1F1E6 + a[0] - 65, 0x1F1E6 + a[1] - 65]);
}

String fmtInt(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

/// 1.2K / 3.4M style numbers for tight spaces (currency chips).
String fmtCompact(num n) {
  final a = n.abs();
  if (a < 10000) return fmtInt(n);
  if (a < 1000000) return '${(n / 1000).toStringAsFixed(a < 100000 ? 1 : 0).replaceAll('.0', '')}K';
  return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
}

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Deterministic hash (FNV-1a) used for daily seeds; stable across platforms.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

T? firstWhereOrNull<T>(Iterable<T> it, bool Function(T) test) {
  for (final e in it) {
    if (test(e)) return e;
  }
  return null;
}
