import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/anticheat/replay.dart';
import 'package:type_racer_legends/data/models/content_models.dart';
import 'package:type_racer_legends/features/race/engine/race_models.dart';
import 'package:type_racer_legends/features/race/engine/typing_engine.dart';

/// The keystroke log is what turns "trust me" into "check me". These tests replay logs produced by
/// the real engine — which pins the engine's log format too — and then try to lie with one.
const text = 'the quick brown fox jumps over the lazy dog again and again';

void main() {
  test('an honest log from the real engine replays as verified', () {
    final e = TypingEngine(text);
    var t = 500;
    for (var i = 0; i < text.length; i++) {
      e.type(text[i], t);
      t += 180;
    }
    final span = t - 180 - 500;
    final report = replayLog(
      keys: e.keyLog(),
      text: text,
      claimedChars: e.correctKeys,
      claimedAccuracy: e.accuracy,
      claimedTypingMs: span + 1500, // the clock also holds the time before the first key
      claimedWpm: 60,
    );
    expect(report.verdict, ReplayVerdict.verified, reason: report.reason);
    expect(report.correctChars, text.length);
    expect(report.wrongKeys, 0);
    expect(report.textChecked, isTrue);
  });

  test('a log that claims more characters than it contains is contradicted', () {
    final e = TypingEngine(text);
    for (var i = 0; i < 10; i++) {
      e.type(text[i], 500 + i * 150);
    }
    final report = replayLog(keys: e.keyLog(), text: text, claimedChars: 40, claimedAccuracy: 100, claimedTypingMs: 5000, claimedWpm: 0);
    expect(report.rejected, isTrue);
    expect(report.reason, 'chars-mismatch');
  });

  test('accepted keys that are not the next characters are contradicted', () {
    final keys = <int>[];
    for (var i = 0; i < 20; i++) {
      keys.addAll([150, 'a'.codeUnitAt(0), 1]); // twenty "accepted" a's against "the quick…"
    }
    final report = replayLog(keys: keys, text: text, claimedChars: 20, claimedAccuracy: 100, claimedTypingMs: 4000, claimedWpm: 0);
    expect(report.verdict, ReplayVerdict.contradicted);
    expect(report.reason, 'accepted-wrong-char');
  });

  test('a mistake that would have been the right character is contradicted', () {
    final keys = <int>[150, 't'.codeUnitAt(0), 0]; // flagged wrong, but 't' is the next character
    final report = replayLog(keys: keys, text: text, claimedChars: 0, claimedAccuracy: 0, claimedTypingMs: 2000, claimedWpm: 0);
    expect(report.reason, 'wrong-key-would-have-matched');
  });

  test('a claim the keys cannot support is contradicted', () {
    final e = TypingEngine(text);
    var t = 300;
    for (var i = 0; i < text.length; i++) {
      e.type(text[i], t);
      t += 250;
    }
    // ~54 chars in ~13.5 s is 48 WPM; 300 WPM cannot come out of these keys
    final report = replayLog(keys: e.keyLog(), text: text, claimedChars: e.correctKeys, claimedAccuracy: 100, claimedTypingMs: 14000, claimedWpm: 300);
    expect(report.reason, 'wpm-above-log');
  });

  test('a truncated log is partial, never proof', () {
    final e = TypingEngine(text);
    for (var i = 0; i < text.length; i++) {
      e.type(text[i], 400 + i * 200);
    }
    final report = replayLog(
      keys: e.keyLog().sublist(0, 30),
      text: text,
      claimedChars: e.correctKeys,
      claimedAccuracy: e.accuracy,
      claimedTypingMs: 12000,
      claimedWpm: 60,
      full: false,
    );
    expect(report.verdict, ReplayVerdict.partial);
  });

  test('a client with no log is inconclusive, not rejected', () {
    expect(replayLog(keys: const [], claimedChars: 100, claimedAccuracy: 98, claimedTypingMs: 30000, claimedWpm: 70).verdict, ReplayVerdict.inconclusive);
  });

  test('a malformed log is a contradiction, in every shape', () {
    expect(replayLog(keys: const [100, 97], claimedChars: 1, claimedAccuracy: 100, claimedTypingMs: 1000, claimedWpm: 0).reason, 'log-shape');
    expect(replayLog(keys: const [-4, 97, 1], claimedChars: 1, claimedAccuracy: 100, claimedTypingMs: 1000, claimedWpm: 0).reason, 'log-timing');
    expect(replayLog(keys: const [100, 97, 7], claimedChars: 1, claimedAccuracy: 100, claimedTypingMs: 1000, claimedWpm: 0).reason, 'log-flag');
    expect(replayLog(keys: const [100, 99999, 1], claimedChars: 1, claimedAccuracy: 100, claimedTypingMs: 1000, claimedWpm: 0).reason, 'log-code');
  });

  test('with backspace off a long error run is legitimate, and says why it needs the flag', () {
    final e = TypingEngine(text, allowBackspace: false);
    for (var i = 0; i < 12; i++) {
      e.type('x', 400 + i * 200); // twelve mistakes in a row: with no erase, they do not stack
    }
    expect(e.wrongKeys, 12);
    final keys = e.keyLog();
    final withFlag = replayLog(keys: keys, text: text, claimedChars: 0, claimedAccuracy: 0, claimedTypingMs: 4000, claimedWpm: 0, maxWrongBuffer: 0);
    expect(withFlag.verdict, ReplayVerdict.verified, reason: withFlag.reason);
    // the same log read as a backspace run looks impossible — which is exactly why the flag travels
    final withoutFlag = replayLog(keys: keys, text: text, claimedChars: 0, claimedAccuracy: 0, claimedTypingMs: 4000, claimedWpm: 0);
    expect(withoutFlag.reason, 'error-buffer-overflow');
  });

  test('the engine packs the log as dt/code/flag triples with a zero first delta', () {
    final e = TypingEngine('abc');
    e.type('a', 900);
    e.type('b', 1300);
    e.type('x', 1500);
    final log = e.keyLog();
    expect(log.length, 9);
    expect(log.sublist(0, 3), [0, 'a'.codeUnitAt(0), 1]);
    expect(log.sublist(3, 6), [400, 'b'.codeUnitAt(0), 1]);
    expect(log.sublist(6, 9), [200, 'x'.codeUnitAt(0), 0]);
  });

  test('RaceResult.copyWith and flagged() keep the log', () {
    final e = TypingEngine('hello world');
    for (var i = 0; i < 5; i++) {
      e.type('hello world'[i], 100 + i * 100);
    }
    final cfg = RaceConfig(modeId: 'daily', title: 'x', text: TextItem(const {'id': 't1', 't': 'hello world'}));
    RaceResult build({List<int>? keys}) => RaceResult(
          config: cfg,
          standings: const [],
          playerRank: 1,
          wpm: 60,
          rawWpm: 70,
          accuracy: 100,
          time: 12,
          maxCombo: 5,
          errors: 0,
          chars: 5,
          nitroUses: 0,
          perfectWords: 0,
          powerupsUsed: 0,
          pitPerfect: false,
          photoFinish: false,
          timeUp: false,
          suspicious: false,
          intervals: const [],
          samples: const [],
          charStats: const {},
          keys: keys ?? e.keyLog(),
        );
    final r = build();
    expect(r.keys.length, 15);
    expect(r.flagged().keys, r.keys);
    expect(r.copyWith(suspicious: false).keys, r.keys);
    expect(build(keys: const []).keys, isEmpty);
  });
}
