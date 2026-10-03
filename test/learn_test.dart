import 'dart:math';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/data/models/content_models.dart';
import 'package:type_racer_legends/data/models/profile.dart';
import 'package:type_racer_legends/features/learn/certificate.dart';
import 'package:type_racer_legends/features/learn/keyboard_guide.dart';
import 'package:type_racer_legends/features/learn/learn_logic.dart';
import 'package:type_racer_legends/features/profile/share_card.dart';
import 'package:type_racer_legends/features/race/engine/race_models.dart';
import 'package:type_racer_legends/features/stats/stats_logic.dart';
import 'test_support.dart';

RaceResult result({double wpm = 40, double acc = 97, int chars = 200, bool suspicious = false, Map<String, dynamic> words = const {}, String mode = 'lesson', String text = 'x', int? limit, double time = 30}) => RaceResult(
      config: RaceConfig(modeId: mode, title: 't', rules: RaceRules.purePlay, timeLimitMs: limit, text: TextItem({'id': text, 't': 'a' * chars, 'cat': 'x', 'lang': 'en', 'diff': 1, 'len': chars})),
      standings: const [],
      playerRank: 1,
      wpm: wpm,
      rawWpm: wpm,
      accuracy: acc,
      time: time,
      maxCombo: 10,
      errors: 1,
      chars: chars,
      nitroUses: 0,
      perfectWords: 0,
      powerupsUsed: 0,
      pitPerfect: false,
      photoFinish: false,
      timeUp: false,
      suspicious: suspicious,
      intervals: const [],
      samples: const [],
      charStats: const {},
      wordStats: words,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = loadSeedContent();

  group('finger map', () {
    test('every key has a finger; home row fingers are right', () {
      for (final row in Fingers.rows) {
        for (final k in row) {
          expect(Fingers.fingerOfKey(k), isNotNull, reason: k);
        }
      }
      expect(Fingers.fingerOfKey('f'), 3);
      expect(Fingers.fingerOfKey('j'), 5);
      expect(Fingers.fingerOfKey('a'), 0);
      expect(Fingers.fingerOfKey(';'), 8);
      expect(Fingers.fingerOfKey(' '), 4);
      expect(Fingers.fingerOfKey('g'), 3); // index reaches over
      expect(Fingers.fingerOfKey('h'), 5);
    });

    test('shifted characters map to their base key and need Shift', () {
      expect(Fingers.keyFor('A'), (key: 'a', shift: true));
      expect(Fingers.keyFor('a'), (key: 'a', shift: false));
      expect(Fingers.keyFor('!'), (key: '1', shift: true));
      expect(Fingers.keyFor('@'), (key: '2', shift: true));
      expect(Fingers.keyFor('?'), (key: '/', shift: true));
      expect(Fingers.keyFor('{'), (key: '[', shift: true));
      expect(Fingers.keyFor('7'), (key: '7', shift: false));
      expect(Fingers.keyFor('é'), isNull);
      expect(Fingers.describe('A'), contains('Shift'));
      expect(Fingers.describe('k'), 'الوسطى اليمنى');
      expect(Fingers.describe(' '), contains('الإبهام'));
    });
  });

  group('lessons', () {
    test('30 lessons with growing alphabets, target speeds and usable texts', () {
      expect(db.lessons.length, 30);
      var prev = 0;
      for (final l in db.lessons) {
        expect(l.n, prev + 1);
        prev = l.n;
        expect(l.text.length, inInclusiveRange(60, 300));
        expect(l.text.contains(RegExp(r'\s{2,}')), isFalse);
        expect(l.targetWpm, greaterThan(10));
      }
      // early lessons only use the letters taught so far
      final l3 = db.lessons[2];
      final allowed = l3.allowed.split('').toSet();
      for (final ch in l3.text.split('')) {
        expect(allowed.contains(ch), isTrue, reason: 'lesson 3 uses "$ch"');
      }
      expect(db.lessons.map((l) => l.title['ar']).every((t) => t != null), isTrue);
    });

    test('stars need accuracy and speed; unlock in order; rewards once', () {
      final l = db.lessons.first;
      expect(LessonsLogic.starsFor(result(wpm: l.targetWpm - 1.0, chars: l.text.length), l), 0);
      expect(LessonsLogic.starsFor(result(wpm: l.targetWpm + 1.0, acc: l.minAcc - 1, chars: l.text.length), l), 0);
      expect(LessonsLogic.starsFor(result(wpm: l.targetWpm + 1.0, acc: l.minAcc + 0.0, chars: l.text.length), l), 1);
      expect(LessonsLogic.starsFor(result(wpm: l.targetWpm + 1.0, acc: l.minAcc + 5.0, chars: l.text.length), l), 2);
      expect(LessonsLogic.starsFor(result(wpm: l.targetWpm + 9.0, acc: 99, chars: l.text.length), l), 3);
      expect(LessonsLogic.starsFor(result(wpm: 99, suspicious: true, chars: l.text.length), l), 0);
      expect(LessonsLogic.starsFor(result(wpm: 99, chars: 5), l), 0); // did not finish the text
      final p = PlayerProfile.fresh('d');
      expect(LessonsLogic.unlocked(p, db, db.lessons[0]), isTrue);
      expect(LessonsLogic.unlocked(p, db, db.lessons[1]), isFalse);
      final o = LessonsLogic.apply(p, db, l, result(wpm: l.targetWpm + 10.0, acc: 99, chars: l.text.length));
      expect(o.first, isTrue);
      expect(o.stars, 3);
      expect(o.rewardLines, isNotEmpty);
      expect(p.counter('lessons_done'), 1);
      expect(LessonsLogic.unlocked(p, db, db.lessons[1]), isTrue);
      final again = LessonsLogic.apply(p, db, l, result(wpm: l.targetWpm + 2.0, acc: l.minAcc + 0.0, chars: l.text.length));
      expect(again.first, isFalse);
      expect(again.rewardLines, isEmpty);
      expect(LessonsLogic.stars(p, l), 3); // best kept
      expect(p.counter('lessons_done'), 2);
    });

    test('placement lets fast typists skip the basics', () {
      expect(LessonsLogic.recommended(10), 1);
      expect(LessonsLogic.recommended(25), 13);
      expect(LessonsLogic.recommended(80), 28);
      final p = PlayerProfile.fresh('d');
      final skipped = LessonsLogic.unlockBefore(p, db, 13);
      expect(skipped, 12);
      expect(LessonsLogic.unlocked(p, db, db.lessons[12]), isTrue);
      expect(LessonsLogic.learnedKeys(db, p), containsAll(['f', 'j', 'a']));
    });
  });

  group('official test, levels and certificate', () {
    test('levels by speed', () {
      expect(OfficialTest.levelFor(5).label, 'مبتدئ');
      expect(OfficialTest.levelFor(36).label, 'متوسط');
      expect(OfficialTest.levelFor(75).label, 'متقدّم');
      expect(OfficialTest.levelFor(150).label, 'خبير');
    });

    test('60 second pure test; certificate only for accurate, non-suspicious, long-enough runs; issued once per code', () {
      final cfg = OfficialTest.config(db, Random(1), lang: 'en');
      expect(cfg.timeLimitMs, 60000);
      expect(cfg.rules.pure, isTrue);
      expect(cfg.rewards, isFalse);
      final p = PlayerProfile.fresh('d')..setIdentity(name: 'Sami');
      final now = DateTime(2026, 10, 5);
      final cert = OfficialTest.apply(p, db, result(mode: 'official', wpm: 64.4, acc: 96.2, chars: 320, limit: 60000, time: 60), now: now)!;
      expect(cert.name, 'Sami');
      expect(cert.level, 'جيد جداً');
      expect(cert.code, startsWith('TRL-'));
      expect(p.counter('certificates'), 1);
      expect(p.m('placement')['wpm'], 64.4);
      OfficialTest.apply(p, db, result(mode: 'official', wpm: 64.4, acc: 96.2, chars: 320, limit: 60000, time: 60), now: now);
      expect(p.counter('certificates'), 1); // same code
      expect(OfficialTest.apply(p, db, result(wpm: 70, acc: 80, chars: 320), now: now), isNull); // too inaccurate
      expect(OfficialTest.apply(p, db, result(wpm: 70, acc: 99, chars: 20), now: now), isNull); // too short
      expect(OfficialTest.apply(p, db, result(wpm: 999, acc: 99, chars: 400, suspicious: true), now: now), isNull);
      expect(p.m('placement')['wpm'], 70); // placement still updated by the honest (but inaccurate) run
      expect(OfficialTest.code('A', 50, 95, now), isNot(OfficialTest.code('B', 50, 95, now)));
    });

    testWidgets('the certificate renders to a PNG and a real PDF (Arabic drawn by the text engine)', (t) async {
      await t.runAsync(loadTestFonts);
      final data = CertificateData(name: 'سامي الرحالي', wpm: 71.3, accuracy: 97.4, level: 'متقدّم', date: DateTime(2026, 10, 5), code: 'TRL-ABC123', chars: 340, seconds: 60);
      final png = await t.runAsync(() => CertificateRenderer.png(data));
      expect(png!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(png.length, greaterThan(20000));
      final pdf = await t.runAsync(() => CertificateRenderer.pdf(data));
      expect(String.fromCharCodes(pdf!.sublist(0, 5)), '%PDF-');
      expect(pdf.length, greaterThan(png.length ~/ 2));
    });

    testWidgets('the player card renders', (t) async {
      await t.runAsync(loadTestFonts);
      final look = await t.runAsync(() async => null);
      expect(look, isNull);
      const d = CardData(name: 'Sami', title: 'Road Legend', rankLabel: 'ذهبي', rankIcon: Icons.military_tech, flag: 'MA', avatar: Icons.sports_motorsports, level: 12, stats: [('WPM', '72'), ('الدقة', '97%'), ('السلسلة', '5')]);
      final png = await t.runAsync(() => ShareCardRenderer.png(d));
      expect(png!.sublist(0, 4), [137, 80, 78, 71]);
      expect(png.length, greaterThan(10000));
    });
  });

  group('vocabulary', () {
    test('selection favours unseen and weak words and never repeats inside a race', () {
      final p = PlayerProfile.fresh('d');
      for (final w in db.vocab.take(200)) {
        p.m('vocab')[w.id] = 5;
      }
      final rnd = Random(3);
      var fresh = 0, total = 0;
      for (var i = 0; i < 60; i++) {
        final pick = VocabLogic.pick(db, p, 10, rnd);
        expect(pick.map((w) => w.id).toSet().length, pick.length);
        for (final w in pick) {
          total++;
          if (VocabLogic.box(p, w.id) == 0) fresh++;
        }
      }
      expect(fresh / total, greaterThan(0.6)); // only 87 of 287 words are unseen, yet they dominate
    });

    test('config has Arabic hints per word; clean words are promoted, mistakes demote', () {
      final words = db.vocab.take(4).toList();
      final cfg = VocabLogic.config(words);
      expect(cfg.text.text, words.map((w) => w.en).join(' '));
      expect(cfg.vocabHints![2], words[2].ar);
      final p = PlayerProfile.fresh('d');
      p.m('vocab')[words[1].id] = 3;
      final r = result(mode: 'vocab', words: {words[1].en: 2});
      final clean = VocabLogic.record(p, words, r);
      expect(clean, 3);
      expect(VocabLogic.box(p, words[0].id), 1);
      expect(VocabLogic.box(p, words[1].id), 2); // demoted
      expect(p.counter('vocab_words'), 3);
      expect(VocabLogic.record(p, words, result(suspicious: true)), 0);
    });
  });

  group('smart training', () {
    test('heat map: errors and slowness make a key weak; too few attempts are ignored', () {
      final p = PlayerProfile.fresh('d');
      final cs = p.m('charStats');
      cs['en:e'] = [200, 2, 200 * 160];
      cs['en:a'] = [200, 1, 200 * 150];
      cs['en:q'] = [50, 20, 50 * 400]; // error prone + slow
      cs['en:z'] = [3, 3, 3 * 500]; // too few attempts
      cs['fr:é'] = [100, 50, 100 * 300];
      final heat = TrainingLogic.heat(p, 'en');
      expect(heat['q']!, greaterThan(heat['e']!));
      expect(heat.containsKey('z'), isFalse);
      expect(heat.containsKey('é'), isFalse);
      expect(TrainingLogic.weakKeys(p, 'en').first, 'q');
      expect(TrainingLogic.weakKeys(PlayerProfile.fresh('x'), 'en'), isEmpty);
    });

    test('drills are made of real words that contain the weak letters', () {
      final d = TrainingLogic.drill(db, ['q', 'x'], Random(2));
      expect(d.length, greaterThanOrEqualTo(150));
      final ws = d.split(' ');
      final hits = ws.where((w) => w.contains('q') || w.contains('x')).length;
      expect(hits / ws.length, greaterThan(0.8));
      expect(d.contains(RegExp(r'[^a-z \x27]')), isFalse);
      final neutral = TrainingLogic.drill(db, const [], Random(2));
      expect(neutral.length, greaterThanOrEqualTo(150));
      final cfg = TrainingLogic.config(d, ['q', 'x']);
      expect(cfg.modeId, 'training');
      expect(cfg.title, contains('Q'));
    });
  });

  group('stats and weekly goal', () {
    test('per-day table accumulates and prunes; accuracy and play time are tracked', () {
      final p = PlayerProfile.fresh('d');
      final now = DateTime(2026, 10, 7, 12);
      StatsLogic.recordRace(p, result(wpm: 50, acc: 95, chars: 100, time: 20), now: now);
      StatsLogic.recordRace(p, result(wpm: 70, acc: 99, chars: 100, time: 20), now: now);
      StatsLogic.recordRace(p, result(wpm: 500, suspicious: true), now: now);
      StatsLogic.recordRace(p, result(wpm: 500, chars: 10), now: now);
      final d = StatsLogic.day(p, '2026-10-07')!;
      expect(d.races, 2);
      expect(d.best, 70);
      expect(d.avg, 60);
      expect(StatsLogic.avgAccuracy(p), closeTo(97, 0.01));
      expect(StatsLogic.playTime(p).inSeconds, 40);
      final last = StatsLogic.lastDays(p, 7, now: now);
      expect(last.length, 7);
      expect(last.last.races, 2);
      expect(last.first.races, 0);
      for (var i = 0; i < 130; i++) {
        StatsLogic.recordRace(p, result(chars: 100), now: DateTime(2026, 1, 1).add(Duration(days: i)));
      }
      expect(p.m('sdays').length, lessThanOrEqualTo(StatsLogic.maxDays));
    });

    test('goal: suggestion, weekly progress from the best day, one reward per week', () {
      final p = PlayerProfile.fresh('d');
      expect(Goal.suggest(p), greaterThanOrEqualTo(10));
      for (final w in <double>[40, 44, 42, 46]) {
        p.pushHistory(w);
      }
      final s = Goal.suggest(p);
      expect(s, inInclusiveRange(45, 52));
      final wed = DateTime(2026, 10, 7, 10); // Wednesday, week of 2026-10-05
      Goal.set(p, 50, wed);
      expect(Goal.current(p, wed)!['target'], 50);
      expect(Goal.current(p, DateTime(2026, 10, 14)), isNull); // next week: no goal yet
      expect(Goal.progress(p, wed), 0);
      StatsLogic.recordRace(p, result(wpm: 35, chars: 100), now: DateTime(2026, 10, 5));
      expect(Goal.progress(p, wed), closeTo(0.7, 0.01));
      expect(Goal.claim(p, wed), isFalse);
      StatsLogic.recordRace(p, result(wpm: 52, chars: 100), now: DateTime(2026, 10, 6));
      expect(Goal.achieved(p, wed), isTrue);
      expect(Goal.claim(p, wed), isTrue);
      expect(Goal.claim(p, wed), isFalse);
      expect(p.coins, 300);
      Goal.set(p, 55, wed); // changing the target after claiming must not allow a second reward
      expect(Goal.claimed(p, wed), isTrue);
    });

    test('trend compares the last races with the ones before', () {
      final p = PlayerProfile.fresh('d');
      expect(StatsLogic.trend(p), 0);
      for (final w in <double>[30, 30, 30, 30, 40, 40, 40, 40]) {
        p.pushHistory(w);
      }
      expect(StatsLogic.trend(p), 10);
    });
  });
}
