import 'dart:math';
import '../../core/util/dates.dart';
import '../../core/util/misc.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';
import '../race/engine/metrics.dart';
import '../race/engine/race_models.dart';
import '../career/progress.dart';
import '../career/rewards.dart';

// ---------------------------------------------------------------------------------------------------- lessons

class LessonOutcome {
  int stars = 0;
  bool passed = false, first = false;
  int bestBefore = 0;
  List<String> rewardLines = [];
}

class LessonsLogic {
  static int stars(PlayerProfile p, Lesson l) => ((p.m('lessons')[l.id] as num?) ?? 0).toInt();
  static bool unlocked(PlayerProfile p, ContentDb db, Lesson l) => l.n <= 1 || stars(p, db.lessons.firstWhere((x) => x.n == l.n - 1, orElse: () => l)) > 0 || stars(p, l) > 0;

  static int completed(PlayerProfile p) => p.m('lessons').values.where((v) => (v as num) > 0).length;

  /// ★ pass (accuracy + target speed) · ★★ accuracy +4 · ★★★ accuracy 98% and +8 WPM.
  static int starsFor(RaceResult r, Lesson l) {
    if (r.suspicious || r.chars < l.text.length * 0.9) return 0;
    if (r.accuracy < l.minAcc || r.wpm < l.targetWpm) return 0;
    if (r.accuracy >= 98 && r.wpm >= l.targetWpm + 8) return 3;
    if (r.accuracy >= l.minAcc + 4) return 2;
    return 1;
  }

  static RaceConfig config(Lesson l, {String biome = 'city'}) => RaceConfig(
        modeId: 'lesson',
        title: 'الدرس ${l.n}: ${loc(l.title)}',
        text: TextItem({'id': 'lesson_${l.id}', 't': l.text, 'cat': 'lesson', 'topic': 'lesson', 'lang': 'en', 'diff': 1, 'len': l.text.length}),
        biomeId: biome,
        rules: RaceRules.purePlay,
        rewards: false,
        meta: {'lesson': l.id, 'focus': l.focus},
      );

  static LessonOutcome apply(PlayerProfile p, ContentDb db, Lesson l, RaceResult r) {
    final o = LessonOutcome();
    o.bestBefore = stars(p, l);
    o.stars = starsFor(r, l);
    o.passed = o.stars > 0;
    if (!o.passed) return o;
    p.addCounter('lessons_done', 1);
    if (o.stars > o.bestBefore) p.m('lessons')[l.id] = o.stars;
    if (o.bestBefore == 0) {
      o.first = true;
      o.rewardLines = Rewards.grant(p, db, Map<String, dynamic>.from(l.reward));
      Season.addPoints(p, db, 15);
    }
    return o;
  }

  /// Which lesson to start at, given a placement-test speed.
  static int recommended(double wpm) => wpm < 15 ? 1 : (wpm < 22 ? 7 : (wpm < 30 ? 13 : (wpm < 40 ? 19 : (wpm < 55 ? 24 : 28))));

  /// A placement result lets experienced typists skip ahead: earlier lessons count as passed with one star.
  static int unlockBefore(PlayerProfile p, ContentDb db, int n) {
    var c = 0;
    for (final l in db.lessons.where((x) => x.n < n)) {
      if (stars(p, l) == 0) {
        p.m('lessons')[l.id] = 1;
        c++;
      }
    }
    return c;
  }

  static Set<String> learnedKeys(ContentDb db, PlayerProfile p) {
    final out = <String>{};
    for (final l in db.lessons) {
      if (stars(p, l) > 0) out.addAll(l.allowed.split('').where((c) => c != ' '));
    }
    return out;
  }
}

// ---------------------------------------------------------------------------------------------------- placement / official test

class Level {
  final String label;
  final int from;
  const Level(this.label, this.from);
}

class OfficialTest {
  static const levels = [Level('مبتدئ', 0), Level('متدرّب', 20), Level('متوسط', 35), Level('جيد جداً', 50), Level('متقدّم', 70), Level('محترف', 100), Level('خبير', 140)];

  static Level levelFor(double wpm) => levels.lastWhere((l) => wpm >= l.from);

  static RaceConfig config(ContentDb db, Random rnd, {required String lang}) {
    final pool = db.officialTexts();
    final t = pool.isEmpty ? db.pickText(rnd, lang: lang, cats: const ['story'], minLen: 200) : pool[rnd.nextInt(pool.length)];
    return RaceConfig(modeId: 'official', title: 'الاختبار الرسمي (60 ثانية)', text: t, biomeId: 'city', rules: RaceRules.purePlay, rewards: false, timeLimitMs: ((db.econ('tests')['officialSeconds'] as num?)?.toInt() ?? 60) * 1000);
  }

  static int minAccuracy(ContentDb db) => (db.econ('tests')['minAccuracy'] as num?)?.toInt() ?? 90;

  static bool valid(RaceResult r, ContentDb db) => !r.suspicious && r.chars >= 60 && r.accuracy >= minAccuracy(db) && !r.config.text.id.startsWith('custom');

  static String code(String name, double wpm, double acc, DateTime when) => 'TRL-${stableHash('$name|${wpm.round()}|${acc.round()}|${dayKey(when)}|trl-cert').toRadixString(36).toUpperCase().padLeft(6, '0').substring(0, 6)}';

  /// Stores the placement result; returns the certificate data when the run qualifies.
  static CertificateData? apply(PlayerProfile p, ContentDb db, RaceResult r, {DateTime? now}) {
    if (r.suspicious || r.chars < 60) return null;
    final when = now ?? DateTime.now();
    final lvl = levelFor(r.wpm);
    final pl = p.m('placement');
    pl
      ..['wpm'] = double.parse(r.wpm.toStringAsFixed(1))
      ..['acc'] = double.parse(r.accuracy.toStringAsFixed(1))
      ..['at'] = when.millisecondsSinceEpoch
      ..['level'] = lvl.label;
    if (!valid(r, db)) return null;
    final code = OfficialTest.code(p.name, r.wpm, r.accuracy, when);
    final certs = p.m('certs');
    if (!certs.containsKey(code)) {
      certs[code] = when.millisecondsSinceEpoch;
      p.addCounter('certificates', 1);
    }
    return CertificateData(name: p.name, wpm: r.wpm, accuracy: r.accuracy, level: lvl.label, date: when, code: code, chars: r.chars, seconds: (r.config.timeLimitMs ?? 60000) ~/ 1000);
  }
}

class CertificateData {
  final String name, level, code;
  final double wpm, accuracy;
  final DateTime date;
  final int chars, seconds;
  const CertificateData({required this.name, required this.wpm, required this.accuracy, required this.level, required this.date, required this.code, required this.chars, required this.seconds});
}

// ---------------------------------------------------------------------------------------------------- vocabulary (Arabic -> English)

class VocabLogic {
  static int box(PlayerProfile p, String id) => ((p.m('vocab')[id] as num?) ?? 0).toInt();

  static int mastered(PlayerProfile p) => p.m('vocab').values.where((v) => (v as num) >= 4).length;
  static int seen(PlayerProfile p) => p.m('vocab').values.where((v) => (v as num) >= 1).length;

  /// Leitner-style selection: unseen and low-box words are much more likely than mastered ones.
  static List<VocabWord> pick(ContentDb db, PlayerProfile p, int n, Random rnd) {
    final pool = db.vocab.toList();
    if (pool.isEmpty) return const [];
    final weights = <double>[for (final w in pool) const [4.0, 3.0, 2.0, 1.2, 0.6, 0.25][box(p, w.id).clamp(0, 5)]];
    final out = <VocabWord>[];
    final taken = <int>{};
    var guard = 0;
    while (out.length < min(n, pool.length) && guard++ < 5000) {
      final total = weights.asMap().entries.where((e) => !taken.contains(e.key)).fold<double>(0, (a, e) => a + e.value);
      var x = rnd.nextDouble() * total;
      for (var i = 0; i < pool.length; i++) {
        if (taken.contains(i)) continue;
        x -= weights[i];
        if (x <= 0) {
          taken.add(i);
          out.add(pool[i]);
          break;
        }
      }
    }
    return out;
  }

  static RaceConfig config(List<VocabWord> words) {
    final text = words.map((w) => w.en).join(' ');
    return RaceConfig(
      modeId: 'vocab',
      title: 'مفردات: من العربية إلى الإنجليزية',
      text: TextItem({'id': 'vocab_${stableHash(text)}', 't': text, 'cat': 'vocab', 'topic': 'vocab', 'lang': 'en', 'diff': 2, 'len': text.length}),
      biomeId: 'city',
      rules: const RaceRules(powerups: false, pit: false, slipstream: false),
      vocabHints: {for (var i = 0; i < words.length; i++) i: words[i].ar},
      meta: {'vocab': words.map((w) => w.id).toList()},
    );
  }

  /// Promotes words typed without a single mistake, demotes the others. Returns the number of clean words.
  static int record(PlayerProfile p, List<VocabWord> words, RaceResult r) {
    if (r.suspicious) return 0;
    var clean = 0;
    final boxes = p.m('vocab');
    for (final w in words) {
      final errors = (r.wordStats[w.en] as num?)?.toInt() ?? 0;
      final cur = box(p, w.id);
      if (errors == 0) {
        boxes[w.id] = min(5, cur + 1);
        clean++;
      } else {
        boxes[w.id] = max(1, cur - 1);
      }
    }
    if (clean > 0) p.addCounter('vocab_words', clean);
    return clean;
  }
}

// ---------------------------------------------------------------------------------------------------- smart training (weak keys)

class KeyStat {
  final String ch;
  final int attempts, errors;
  final double avgMs;
  const KeyStat(this.ch, this.attempts, this.errors, this.avgMs);
  double get errorRate => attempts == 0 ? 0 : errors / attempts;
}

class TrainingLogic {
  static const minAttempts = 8;

  static List<KeyStat> stats(PlayerProfile p, String lang) {
    final cs = p.m('charStats');
    final out = <KeyStat>[];
    cs.forEach((k, v) {
      if (!k.startsWith('$lang:') || v is! List || v.length < 3) return;
      final ch = k.substring(lang.length + 1);
      if (ch.length != 1) return;
      final a = (v[0] as num).toInt(), e = (v[1] as num).toInt(), t = (v[2] as num).toInt();
      out.add(KeyStat(ch, a, e, a == 0 ? 0 : t / a));
    });
    return out;
  }

  /// Weakness 0..1 per character (errors weigh more than slowness).
  static Map<String, double> heat(PlayerProfile p, String lang) {
    final list = stats(p, lang).where((s) => s.attempts >= minAttempts && s.ch.trim().isNotEmpty).toList();
    if (list.isEmpty) return {};
    final avgMs = list.fold<double>(0, (a, s) => a + s.avgMs) / list.length;
    final out = <String, double>{};
    for (final s in list) {
      final slow = avgMs <= 0 ? 0.0 : ((s.avgMs - avgMs) / avgMs).clamp(0.0, 1.0);
      out[s.ch] = (s.errorRate * 6).clamp(0.0, 1.0) * 0.75 + slow * 0.25;
    }
    return out;
  }

  static List<String> weakKeys(PlayerProfile p, String lang, {int n = 6}) {
    final h = heat(p, lang).entries.where((e) => e.value > 0.12).toList()..sort((a, b) => b.value.compareTo(a.value));
    return h.take(n).map((e) => e.key).toList();
  }

  /// Builds a practice text dominated by words containing the weak keys (real words from the shipped texts).
  static String drill(ContentDb db, List<String> weak, Random rnd, {String lang = 'en', int length = 170}) {
    final vocab = <String>{};
    for (final t in db.texts.where((t) => t.lang == lang)) {
      for (final w in RegExp(r"[A-Za-z']+").allMatches(t.text).map((m) => m.group(0)!.toLowerCase())) {
        if (w.length >= 3 && w.length <= 9) vocab.add(w.split('').map(foldChar).join());
      }
    }
    final words = vocab.toList()..sort();
    final weakSet = weak.map((w) => w.toLowerCase()).toSet();
    List<String> scored(int minHits) => words.where((w) => w.split('').where(weakSet.contains).length >= minHits).toList();
    var pool = weakSet.isEmpty ? words : scored(2);
    if (pool.length < 25) pool = scored(1);
    if (pool.isEmpty) pool = words.isEmpty ? ['practice', 'typing', 'keyboard', 'fingers', 'speed'] : words;
    final out = <String>[];
    var len = 0;
    while (len < length) {
      final w = pool[rnd.nextInt(pool.length)];
      if (out.isNotEmpty && out.last == w) continue;
      out.add(w);
      len += w.length + 1;
    }
    return out.join(' ');
  }

  static RaceConfig config(String text, List<String> weak) => RaceConfig(
        modeId: 'training',
        title: 'تدريب ذكي${weak.isEmpty ? '' : ': ${weak.map((e) => e.toUpperCase()).join(' ')}'}',
        text: TextItem({'id': 'training_${stableHash(text)}', 't': text, 'cat': 'training', 'topic': 'training', 'lang': 'en', 'diff': 3, 'len': text.length}),
        biomeId: 'city',
        rules: RaceRules.purePlay,
        meta: {'weak': weak},
      );
}
