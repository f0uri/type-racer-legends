import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/data/models/content_models.dart';
import 'package:type_racer_legends/features/leaderboard/leaderboard_service.dart';
import 'package:type_racer_legends/features/race/engine/race_models.dart';
import 'package:type_racer_legends/features/race/engine/typing_engine.dart';

RaceResult r({String mode = 'daily', RaceRules rules = RaceRules.purePlay, bool suspicious = false, int chars = 120, double acc = 96, int ivs = 100}) => RaceResult(
      config: RaceConfig(modeId: mode, title: 't', rules: rules, text: TextItem({'id': 'eq1', 't': 'a' * chars, 'cat': 'sentence', 'lang': 'en', 'diff': 2, 'len': chars})),
      standings: const [],
      playerRank: 1,
      wpm: 71.26,
      rawWpm: 72,
      accuracy: acc,
      time: 20,
      maxCombo: 30,
      errors: 2,
      chars: chars,
      nitroUses: 0,
      perfectWords: 0,
      powerupsUsed: 0,
      pitPerfect: false,
      photoFinish: false,
      timeUp: false,
      suspicious: suspicious,
      intervals: List.filled(ivs, 150),
      samples: const [],
      charStats: const {},
    );

void main() {
  test('only pure-play results of leaderboard modes are submitted', () {
    expect(ScorePayload.fromResult(r()), isNotNull);
    expect(ScorePayload.fromResult(r(mode: 'weekly')), isNotNull);
    expect(ScorePayload.fromResult(r(mode: 'quick', rules: RaceRules.full)), isNull); // bonuses enabled
    expect(ScorePayload.fromResult(r(mode: 'quick')), isNull);
    expect(ScorePayload.fromResult(r(suspicious: true)), isNull);
    expect(ScorePayload.fromResult(r(chars: 10)), isNull);
    expect(ScorePayload.fromResult(r(acc: 70)), isNull);
    expect(ScorePayload.fromResult(r(ivs: 5)), isNull);
  });

  test('payload is compact and capped', () {
    final p = ScorePayload.fromResult(r(ivs: 900))!;
    expect(p.intervals.length, 400);
    final j = p.toJson();
    expect(j['wpm'], 71.3);
    expect(j['textId'], 'eq1');
    expect(j['mode'], 'daily');
  });

  test('a real run travels with its keystroke log and its own verdict', () {
    const source = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final e = TypingEngine(source);
    var t = 400;
    for (var i = 0; i < source.length; i++) {
      e.type(source[i], t);
      t += 250;
    }
    final span = t - 250 - 400;
    final res = RaceResult(
      config: RaceConfig(modeId: 'daily', title: 't', rules: RaceRules.purePlay, text: TextItem({'id': 'eq1', 't': source, 'cat': 'sentence', 'lang': 'en', 'diff': 2, 'len': source.length})),
      standings: const [],
      playerRank: 1,
      wpm: 45,
      rawWpm: 45,
      accuracy: 100,
      time: 20,
      maxCombo: 30,
      errors: 0,
      chars: source.length,
      nitroUses: 0,
      perfectWords: 0,
      powerupsUsed: 0,
      pitPerfect: false,
      photoFinish: false,
      timeUp: false,
      suspicious: false,
      intervals: List.filled(60, 250),
      samples: const [],
      charStats: const {},
      typingMs: span + 2000,
      keys: e.keyLog(),
    );
    final p = ScorePayload.fromResult(res)!;
    final j = p.toJson();
    expect(j['keys'], isNotEmpty);
    expect(j['full'], isTrue);
    expect(j['replay'], 'verified');
    expect((j['keys'] as List).length, source.length * 3);
  });

  test('board ids: global, country, weekly (Monday key) and monthly', () {
    final now = DateTime(2026, 10, 7);
    expect(LeaderboardService.boardId(Board.global, now: now), 'global');
    expect(LeaderboardService.boardId(Board.country, cc: 'ma', now: now), 'country_MA');
    expect(LeaderboardService.boardId(Board.weekly, now: now), 'weekly_2026-10-05');
    expect(LeaderboardService.boardId(Board.monthly, now: now), 'monthly_202610');
  });
}
