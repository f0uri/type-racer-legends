import 'dart:math';

/// Standard typing metrics (5 characters = 1 word).
double wpmFrom(int correctChars, num elapsedMs) {
  if (elapsedMs <= 0 || correctChars <= 0) return 0;
  return (correctChars / 5.0) / (elapsedMs / 60000.0);
}

double accuracyFrom(int correctKeys, int wrongKeys) {
  final t = correctKeys + wrongKeys;
  if (t <= 0) return 100;
  return correctKeys * 100.0 / t;
}

/// Combo multiplier tiers: x1 <10, x2 >=10, x3 >=25, x4 >=50, x5 >=100, x6 >=200.
int comboMultiplier(int combo) {
  if (combo >= 200) return 6;
  if (combo >= 100) return 5;
  if (combo >= 50) return 4;
  if (combo >= 25) return 3;
  if (combo >= 10) return 2;
  return 1;
}

double meanOf(Iterable<num> v) => v.isEmpty ? 0 : v.fold<double>(0, (a, b) => a + b) / v.length;

double stdDevOf(List<num> v) {
  if (v.length < 2) return 0;
  final m = meanOf(v);
  return sqrt(v.fold<double>(0, (a, b) => a + (b - m) * (b - m)) / v.length);
}

String foldChar(String c) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoaAAAAAACEEEEIIIINOOOOOUUUUY';
  final i = from.indexOf(c);
  return i >= 0 ? to[i] : c;
}
