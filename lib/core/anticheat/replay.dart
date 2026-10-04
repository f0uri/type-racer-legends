import 'dart:math' as math;

import '../../features/race/engine/metrics.dart';

/// What a replayed keystroke log says about a submitted result.
enum ReplayVerdict {
  /// The log replays, and every headline number follows from the keys themselves.
  verified,

  /// The log is consistent as far as it goes, but it was truncated before the end of the run, so
  /// the totals cannot be confirmed from it.
  partial,

  /// The log contradicts the claim: these keystrokes cannot produce those numbers.
  contradicted,

  /// There is nothing to replay (no log — an older client, or a mode that does not log).
  inconclusive,
}

class ReplayReport {
  const ReplayReport(this.verdict, this.reason, {this.correctChars = 0, this.wrongKeys = 0, this.typingMs = 0, this.textChecked = false});
  final ReplayVerdict verdict;
  final String reason;
  final int correctChars, wrongKeys, typingMs;
  final bool textChecked;

  /// True when the submitted numbers must not be trusted (let alone published).
  bool get rejected => verdict == ReplayVerdict.contradicted;
  bool get trusted => verdict == ReplayVerdict.verified;
}

/// Replays a raw keystroke log and re-derives the result instead of believing it.
///
/// [keys] is the flat log the client sends: triples of [dtMs, codeUnit, okFlag]. When [text] is
/// known the replay is exact — every accepted key has to be the next character of that text, and a
/// wrong key has to be a real mistake — because that is the part a fabricated summary cannot fake.
/// Without the text only the arithmetic can be checked, which still catches inflated numbers.
///
/// This is the reference implementation. `functions/antiCheat.js` mirrors it so the same log is
/// judged the same way on the device and on the server.
ReplayReport replayLog({
  required List<int> keys,
  String? text,
  required int claimedChars,
  required double claimedAccuracy,
  required int claimedTypingMs,
  required double claimedWpm,
  /// How many consecutive wrong keys the engine could log. Zero or less means backspace is off:
  /// then every wrong key is logged on its own and any run length is possible.
  int maxWrongBuffer = 8,
  bool full = true,
  bool foldAccents = true,
}) {
  if (keys.isEmpty) return const ReplayReport(ReplayVerdict.inconclusive, 'no-log');
  if (keys.length % 3 != 0) return const ReplayReport(ReplayVerdict.contradicted, 'log-shape');
  final n = keys.length ~/ 3;
  var correct = 0, wrong = 0, span = 0;
  var p = 0; // how far into the text the accepted keys have carried the run
  var buffer = 0; // wrong characters waiting to be erased, exactly as the engine models them
  var textChecked = false;
  final hasText = text != null && text.isNotEmpty;
  for (var i = 0; i < n; i++) {
    final dt = keys[i * 3], code = keys[i * 3 + 1], flag = keys[i * 3 + 2];
    if (dt < 0 || dt > 1800000) return const ReplayReport(ReplayVerdict.contradicted, 'log-timing');
    if (flag != 0 && flag != 1) return const ReplayReport(ReplayVerdict.contradicted, 'log-flag');
    if (code < 0 || code > 0xFFFF) return const ReplayReport(ReplayVerdict.contradicted, 'log-code');
    span += dt;
    if (flag == 1) {
      // A pending error must have been erased for the run to move on. Backspace is not logged (it
      // types nothing), so an accepted key after an error *is* the erase.
      buffer = 0;
      if (hasText) {
        if (p >= text.length) return const ReplayReport(ReplayVerdict.contradicted, 'accepted-past-end');
        final expected = text[p];
        final typed = String.fromCharCode(code);
        if (!_matches(typed, expected, foldAccents)) return const ReplayReport(ReplayVerdict.contradicted, 'accepted-wrong-char');
      }
      p++;
      correct++;
    } else {
      if (maxWrongBuffer > 0 && buffer >= maxWrongBuffer) return const ReplayReport(ReplayVerdict.contradicted, 'error-buffer-overflow');
      // With no pending error the engine compares this character to the text: a mistake that would
      // in fact have been the right character is impossible.
      if (hasText && buffer == 0 && p < text.length && _matches(String.fromCharCode(code), text[p], foldAccents)) {
        return const ReplayReport(ReplayVerdict.contradicted, 'wrong-key-would-have-matched');
      }
      buffer++;
      wrong++;
    }
    textChecked = textChecked || (hasText && flag == 1);
  }
  final typingMs = n > 1 ? span : 0;
  if (!full) {
    return ReplayReport(ReplayVerdict.partial, 'log-truncated', correctChars: correct, wrongKeys: wrong, typingMs: typingMs, textChecked: textChecked);
  }
  if (correct != claimedChars) return const ReplayReport(ReplayVerdict.contradicted, 'chars-mismatch');
  final totalKeys = correct + wrong;
  if (totalKeys > 0) {
    final acc = 100.0 * correct / totalKeys;
    if ((acc - claimedAccuracy).abs() > 0.6) return const ReplayReport(ReplayVerdict.contradicted, 'accuracy-mismatch');
  }
  // The claimed span is the race clock, which also contains the reading time before the first key,
  // so the keys can only ever span *less* than it. Keys spanning more than the clock allowed is a
  // contradiction; keys spanning less is simply a player who read the text first.
  if (claimedTypingMs > 0 && typingMs > claimedTypingMs * 1.05 + 1500) {
    return const ReplayReport(ReplayVerdict.contradicted, 'typing-span-mismatch');
  }
  // The claimed WPM is an average over the whole race, so it can only be *slower* than the speed of
  // the keys themselves (the clock also contains the reading time). Faster than the keys allow is
  // the one impossible direction, and that is exactly what a score inflator does.
  if (typingMs > 0 && claimedWpm > 0) {
    final typingWpm = wpmFrom(correct, typingMs);
    if (claimedWpm > typingWpm * 1.05 + 2) return const ReplayReport(ReplayVerdict.contradicted, 'wpm-above-log');
  }
  return ReplayReport(ReplayVerdict.verified, 'ok', correctChars: correct, wrongKeys: wrong, typingMs: typingMs, textChecked: textChecked);
}

/// Mirrors `TypingEngine._matches`: the typed character equals the expected one, or accent folding
/// maps the expected one onto what was typed.
bool _matches(String typed, String expected, bool foldAccents) {
  if (typed == expected) return true;
  return foldAccents && foldChar(expected) == typed;
}
