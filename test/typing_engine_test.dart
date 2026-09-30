import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/features/race/engine/metrics.dart';
import 'package:type_racer_legends/features/race/engine/typing_engine.dart';

void main() {
  group('metrics', () {
    test('WPM uses 5 chars per word', () {
      expect(wpmFrom(50, 60000), closeTo(10, 1e-9));
      expect(wpmFrom(300, 60000), closeTo(60, 1e-9));
      expect(wpmFrom(0, 1000), 0);
      expect(wpmFrom(10, 0), 0);
    });
    test('accuracy', () {
      expect(accuracyFrom(0, 0), 100);
      expect(accuracyFrom(95, 5), 95);
      expect(accuracyFrom(0, 4), 0);
    });
    test('combo multiplier tiers', () {
      expect(comboMultiplier(0), 1);
      expect(comboMultiplier(9), 1);
      expect(comboMultiplier(10), 2);
      expect(comboMultiplier(25), 3);
      expect(comboMultiplier(50), 4);
      expect(comboMultiplier(100), 5);
      expect(comboMultiplier(500), 6);
    });
    test('accent folding', () {
      expect(foldChar('é'), 'e');
      expect(foldChar('ç'), 'c');
      expect(foldChar('a'), 'a');
    });
    test('std dev', () {
      expect(stdDevOf([2, 4, 4, 4, 5, 5, 7, 9]), closeTo(2, 1e-9));
    });
  });

  group('TypingEngine', () {
    test('types a whole text, tracks combo and accuracy', () {
      final e = TypingEngine('hi there');
      var t = 0;
      for (final c in 'hi there'.split('')) {
        expect(e.type(c, t += 100), KeyResult.correct);
      }
      expect(e.finished, isTrue);
      expect(e.accuracy, 100);
      expect(e.maxCombo, 8);
      expect(e.correctKeys, 8);
    });

    test('wrong key resets combo and must be erased with backspace', () {
      final e = TypingEngine('abc');
      e.type('a', 100);
      expect(e.type('x', 200), KeyResult.wrong);
      expect(e.combo, 0);
      expect(e.type('b', 300), KeyResult.wrong); // still blocked by the wrong char
      expect(e.pos, 1);
      expect(e.backspace(), isTrue);
      expect(e.backspace(), isTrue);
      expect(e.type('b', 400), KeyResult.correct);
      expect(e.type('c', 500), KeyResult.correct);
      expect(e.finished, isTrue);
      expect(e.wrongKeys, 2);
      expect(e.accuracy, closeTo(3 / 5 * 100, 1e-9));
    });

    test('without backspace the wrong key does not block', () {
      final e = TypingEngine('abc', allowBackspace: false);
      expect(e.type('x', 10), KeyResult.wrong);
      expect(e.backspace(), isFalse);
      expect(e.type('a', 20), KeyResult.correct);
      expect(e.pos, 1);
    });

    test('backspace never crosses into a previous word', () {
      final e = TypingEngine('ab cd');
      for (final c in 'ab c'.split('')) {
        e.type(c, 10);
      }
      expect(e.backspace(), isTrue); // remove c (same word)
      expect(e.backspace(), isFalse); // at word start
      expect(e.pos, 3);
    });

    test('accent folding accepts unaccented input in French mode', () {
      final a = TypingEngine('été');
      expect(a.type('e', 1), KeyResult.correct);
      final b = TypingEngine('été', foldAccents: false);
      expect(b.type('e', 1), KeyResult.wrong);
      expect(TypingEngine('été', foldAccents: false).type('é', 1), KeyResult.correct);
    });

    test('rolling wpm and intervals', () {
      final e = TypingEngine('a' * 100);
      for (var i = 1; i <= 50; i++) {
        e.type('a', i * 200); // 5 cps = 60 wpm
      }
      expect(e.rollingWpm(10000), closeTo(60, 6));
      expect(e.wpmAt(10000), closeTo(60, 3));
      expect(e.intervals().every((v) => v == 200), isTrue);
    });

    test('per-character stats record errors', () {
      final e = TypingEngine('ab');
      e.type('z', 10);
      e.backspace();
      e.type('a', 20);
      expect(e.charStats['a']![1], 1);
      expect(e.charStats['a']![0], 2);
    });

    test('word helpers', () {
      final e = TypingEngine('one two');
      expect(e.wordEnd, 3);
      for (final c in 'one t'.split('')) {
        e.type(c, 1);
      }
      expect(e.wordStart, 4);
      expect(e.wordEnd, 7);
    });
  });
}
