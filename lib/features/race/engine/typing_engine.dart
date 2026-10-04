import 'metrics.dart';

enum KeyResult { correct, wrong, ignored }

/// True for characters coming from a non-Latin keyboard (Arabic, Cyrillic, Greek, CJK, emoji).
/// The game never punishes these as typing mistakes: the player simply has the wrong keyboard
/// layout active, and the UI shows a one-time hint instead of breaking the combo.
bool isForeignScript(String ch) {
  if (ch.isEmpty) return false;
  final c = ch.runes.first;
  if (c < 128) return false;
  if (c <= 0x02AF) return false; // Latin + Latin Extended (é, ç, ø, đ…) are part of the texts
  if (c >= 0x0370 && c <= 0x03FF) return true; // Greek
  if (c >= 0x0400 && c <= 0x052F) return true; // Cyrillic
  if (c >= 0x0590 && c <= 0x08FF) return true; // Hebrew + Arabic + Syriac
  if (c >= 0x3000) return true; // CJK, Hangul, emoji, exotic symbols
  return false; // general punctuation, arrows, maths (used by the 'symbols' texts)
}

class Keystroke {
  final int t; // ms since race start
  final bool ok;
  /// The character the player actually pressed. Kept because a result can be re-simulated from the
  /// raw log: a verifier that knows the text can confirm each accepted key really was the next
  /// character of that text instead of trusting a summary.
  final String ch;
  const Keystroke(this.t, this.ok, this.ch);
}

/// Pure typing state machine. No Flutter dependencies, fully unit-tested.
class TypingEngine {
  TypingEngine(this.text, {this.allowBackspace = true, this.foldAccents = true, this.maxWrongBuffer = 8});

  final String text;
  final bool allowBackspace;
  final bool foldAccents;
  final int maxWrongBuffer;

  int _pos = 0; // number of correct leading chars
  int _wrongBuf = 0; // wrong chars currently in buffer after pos
  int correctKeys = 0, wrongKeys = 0;
  int combo = 0, maxCombo = 0;
  int wordErrors = 0; // errors in the current word
  bool _lastWordClean = true; // verdict for the word that was just completed
  final List<Keystroke> keystrokes = [];
  final List<int> correctTimes = []; // t (ms) for each correct char in order
  final List<int> errorPositions = [];
  final Map<String, List<int>> charStats = {}; // char -> [attempts, errors, totalMs]
  int _lastCorrectMs = 0;
  int? firstKeyMs;
  int lastKeyMs = 0;

  int get pos => _pos;
  int get wrongBuffer => _wrongBuf;
  int get length => text.length;
  bool get finished => _pos >= text.length;
  double get fraction => text.isEmpty ? 1 : _pos / text.length;
  String get typedBuffer => text.substring(0, _pos) + (_wrongBuf > 0 ? '\u2063' * _wrongBuf : '');
  String? get nextChar => finished ? null : text[_pos];
  int get totalKeys => correctKeys + wrongKeys;
  double get accuracy => accuracyFrom(correctKeys, wrongKeys);

  int get wordStart {
    var i = _pos;
    while (i > 0 && text[i - 1] != ' ') {
      i--;
    }
    return i;
  }

  int get wordEnd {
    var i = _pos;
    while (i < text.length && text[i] != ' ') {
      i++;
    }
    return i;
  }

  bool _matches(String typed, String expected) {
    if (typed == expected) return true;
    return foldAccents && foldChar(expected) == typed;
  }

  /// Types a single character at [tMs] (ms since race start).
  KeyResult type(String ch, int tMs) {
    if (finished || ch.isEmpty) return KeyResult.ignored;
    // Wrong keyboard layout / control characters: never a typing error, never a lost combo.
    if (isForeignScript(ch) || ch.codeUnitAt(0) < 32) return KeyResult.ignored;
    firstKeyMs ??= tMs;
    lastKeyMs = tMs;
    if (_wrongBuf > 0) {
      // Must erase first (only possible with Backspace).
      if (_wrongBuf < maxWrongBuffer) {
        _wrongBuf++;
        wrongKeys++;
        keystrokes.add(Keystroke(tMs, false, ch));
        _breakCombo();
        return KeyResult.wrong;
      }
      return KeyResult.ignored;
    }
    final expected = text[_pos];
    final st = charStats.putIfAbsent(foldChar(expected).toLowerCase(), () => [0, 0, 0]);
    st[0]++;
    if (_matches(ch, expected)) {
      st[2] += (tMs - _lastCorrectMs).clamp(0, 5000);
      _lastCorrectMs = tMs;
      _pos++;
      correctKeys++;
      combo++;
      if (combo > maxCombo) maxCombo = combo;
      keystrokes.add(Keystroke(tMs, true, ch));
      correctTimes.add(tMs);
      if (expected == ' ') {
        // Snapshot the word verdict *before* resetting the counter, otherwise every
        // spaced word would look clean and the "perfect word" bonus would always fire.
        _lastWordClean = wordErrors == 0;
        wordErrors = 0;
      }
      return KeyResult.correct;
    }
    st[1]++;
    wrongKeys++;
    wordErrors++;
    _lastWordClean = false;
    errorPositions.add(_pos);
    keystrokes.add(Keystroke(tMs, false, ch));
    _breakCombo();
    if (allowBackspace) _wrongBuf = 1; // wrong char is shown in red and must be deleted
    return KeyResult.wrong;
  }

  void _breakCombo() => combo = 0;

  /// Returns true if the backspace was honoured.
  bool backspace() {
    if (!allowBackspace) return false;
    if (_wrongBuf > 0) {
      _wrongBuf--;
      return true;
    }
    // Deleting already-correct characters is allowed inside the current word only.
    if (_pos > wordStartOfPos) {
      _pos--;
      return true;
    }
    return false;
  }

  int get wordStartOfPos => wordStart;

  /// True if the word that just completed at the last correct key was typed without errors.
  bool get lastWordClean => _lastWordClean;

  /// True when the buffer is full of wrong characters and further keys are refused
  /// (the UI shows a "press backspace" prompt instead of silently swallowing input).
  bool get stuckBackspace => _wrongBuf >= maxWrongBuffer;

  double wpmAt(int nowMs) {
    final s = firstKeyMs;
    if (s == null) return 0;
    return wpmFrom(correctKeys, (nowMs - s).clamp(500, 1 << 30));
  }

  /// Rolling WPM over the last [windowMs].
  double rollingWpm(int nowMs, {int windowMs = 4000}) {
    var n = 0;
    final from = nowMs - windowMs;
    for (var i = correctTimes.length - 1; i >= 0; i--) {
      if (correctTimes[i] < from) break;
      n++;
    }
    if (n == 0) return 0;
    final span = (nowMs - (firstKeyMs ?? nowMs)).clamp(1000, windowMs);
    return wpmFrom(n, span);
  }

  /// Inter-key intervals in ms for correct keys (used by server anti-cheat).
  List<int> intervals() {
    final out = <int>[];
    for (var i = 1; i < keystrokes.length; i++) {
      out.add(keystrokes[i].t - keystrokes[i - 1].t);
    }
    return out;
  }

  /// The raw keystroke log as flat triples: [dtMs, codeUnit, okFlag, ...]. The first dt is 0.
  /// This is what a verifier replays: it re-derives WPM, accuracy and the typing span from the
  /// keys themselves, and (when it has the text) checks that every accepted key was the next
  /// character of that text.
  List<int> keyLog() {
    final out = <int>[];
    var prev = keystrokes.isEmpty ? 0 : keystrokes.first.t;
    for (final k in keystrokes) {
      final dt = (k.t - prev).clamp(0, 1800000);
      prev = k.t;
      out.add(dt);
      out.add(k.ch.isEmpty ? 0 : k.ch.codeUnitAt(0));
      out.add(k.ok ? 1 : 0);
    }
    return out;
  }
}
