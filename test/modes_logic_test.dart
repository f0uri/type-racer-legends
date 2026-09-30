import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/data/merge/profile_merge.dart';
import 'package:type_racer_legends/data/models/content_models.dart';
import 'package:type_racer_legends/data/models/profile.dart';
import 'package:type_racer_legends/features/career/campaign_logic.dart';
import 'package:type_racer_legends/features/career/challenge_link.dart';
import 'package:type_racer_legends/features/career/custom_text_screen.dart';
import 'package:type_racer_legends/features/career/daily_screen.dart';
import 'package:type_racer_legends/features/career/tournament_logic.dart';
import 'package:type_racer_legends/features/career/world_tour_screen.dart';
import 'package:type_racer_legends/features/race/engine/race_models.dart';
import 'test_support.dart';

RaceResult res({double wpm = 60, double acc = 97, int rank = 1, int n = 4, bool suspicious = false, bool timeUp = false, int chars = 120}) => RaceResult(
      config: RaceConfig(modeId: 'quick', title: 't', text: TextItem({'id': 'x', 't': 'a' * chars, 'cat': 'sentence', 'lang': 'en', 'diff': 2, 'len': chars})),
      standings: List.generate(n, (i) => RacerResult(id: 'r$i', rank: i + 1, name: i + 1 == rank ? 'me' : 'ai$i', cc: 'MA', wpm: 50, time: 20, isPlayer: i + 1 == rank, isAi: i + 1 != rank, accuracy: 95)),
      playerRank: rank,
      wpm: wpm,
      rawWpm: wpm,
      accuracy: acc,
      time: 20,
      maxCombo: 10,
      errors: 1,
      chars: chars,
      nitroUses: 0,
      perfectWords: 0,
      powerupsUsed: 0,
      pitPerfect: false,
      photoFinish: false,
      timeUp: timeUp,
      suspicious: suspicious,
      intervals: const [],
      samples: const [],
      charStats: const {},
    );

void main() {
  final db = loadSeedContent();

  group('campaign', () {
    test('50 stages, sequential unlock, boss every last stage of a biome', () {
      expect(db.stages.length, 50);
      final p = PlayerProfile.fresh('d');
      expect(CampaignLogic.unlocked(p, 1), isTrue);
      expect(CampaignLogic.unlocked(p, 2), isFalse);
      p.setCampaignStars(1, 1);
      expect(CampaignLogic.unlocked(p, 2), isTrue);
      for (final b in db.biomes) {
        final last = db.stages.where((s) => s.biome == b.id).last;
        expect(last.boss, 'boss_${b.id}');
        expect(db.boss(last.boss!), isNotNull);
      }
    });

    test('stars: top-2 = 1, win = 2, win + accuracy goal = 3; cheats and time-outs give none', () {
      final s = db.stage(1)!;
      expect(CampaignLogic.starsFor(res(rank: 3), s), 0);
      expect(CampaignLogic.starsFor(res(rank: 2), s), 1);
      expect(CampaignLogic.starsFor(res(rank: 1, acc: s.accStar - 1), s), 2);
      expect(CampaignLogic.starsFor(res(rank: 1, acc: s.accStar.toDouble()), s), 3);
      expect(CampaignLogic.starsFor(res(suspicious: true), s), 0);
      expect(CampaignLogic.starsFor(res(timeUp: true), s), 0);
    });

    test('first clear pays the stage reward once; better stars pay a quarter of coins', () {
      final p = PlayerProfile.fresh('d');
      final s = db.stage(1)!;
      final coins = (s.reward['coins'] as num).toInt();
      final o1 = CampaignLogic.apply(p, s, res(rank: 2), db);
      expect(o1.firstClear, isTrue);
      expect(o1.coins, coins);
      final o2 = CampaignLogic.apply(p, s, res(rank: 2), db);
      expect(o2.coins, 0);
      final o3 = CampaignLogic.apply(p, s, res(rank: 1, acc: 99), db);
      expect(o3.firstClear, isFalse);
      expect(o3.coins, (coins * 0.25 * 2).round());
      expect(p.campaignStars(1), 3);
    });

    test('beating a boss records it', () {
      final p = PlayerProfile.fresh('d');
      final s = db.stage(9)!;
      final o = CampaignLogic.apply(p, s, res(rank: 1), db);
      expect(o.bossBeaten, isTrue);
      expect(p.bossesDefeated, 1);
    });

    test('built configs have the right opponent count, boss and modifier', () {
      final p = PlayerProfile.fresh('d');
      final settings = GameSettingsStub.make();
      for (final n in [1, 9, 25, 50]) {
        final st = db.stage(n)!;
        final cfg = CampaignLogic.buildConfig(db, p, settings, st, Random(n));
        expect(cfg.opponents.length, st.oppCount);
        expect(cfg.mod, st.mod);
        expect(cfg.text.len, inInclusiveRange(1, 400));
        expect(cfg.opponents.any((o) => o.isBoss), st.isBoss);
      }
    });
  });

  group('tournament', () {
    TournamentDef d8() => db.tournaments.firstWhere((t) => t.size == 8);
    TournamentDef d16() => db.tournaments.firstWhere((t) => t.size == 16);

    test('the draw is deterministic and contains the player exactly once', () {
      final a = Bracket.generate(db, d8(), '2026-09-30', playerName: 'Sami', playerCc: 'MA', playerWpm: 40);
      final b = Bracket.generate(db, d8(), '2026-09-30', playerName: 'Sami', playerCc: 'MA', playerWpm: 40);
      expect(a.entries.map((e) => e.name).toList(), b.entries.map((e) => e.name).toList());
      expect(a.entries.where((e) => e.isPlayer).length, 1);
      expect(a.entries.length, 8);
      expect(a.entries.map((e) => e.name).toSet().length, 8);
      final c = Bracket.generate(db, d8(), '2026-10-01', playerName: 'Sami', playerCc: 'MA', playerWpm: 40);
      expect(c.entries.map((e) => e.name).toList(), isNot(a.entries.map((e) => e.name).toList()));
    });

    test('playing through an 8-player bracket: 3 wins make you champion and pay out', () {
      final p = PlayerProfile.fresh('d');
      final def = d8();
      var st = TournamentLogic.enter(p, def, 40);
      expect(p.counter('tournaments_played'), 1);
      var coins = 0;
      for (var r = 0; r < def.rounds; r++) {
        final b = TournamentLogic.bracketFor(db, p, def, st);
        expect(b.matchOf(r, b.player), isNotNull, reason: 'round $r');
        final e = TournamentLogic.recordResult(p, def, st, true);
        coins += (e['coins'] as num?)?.toInt() ?? 0;
        st = TournamentLogic.stateOf(p, def)!;
      }
      expect(st.won, isTrue);
      expect(st.alive, isFalse);
      expect(p.counter('tournaments_won'), 1);
      expect(coins, greaterThan(1000));
      expect(p.m('titles').containsKey('t_tourn_daily'), isTrue);
    });

    test('a loss eliminates the player and ends the attempt for the period', () {
      final p = PlayerProfile.fresh('d');
      final def = d16();
      var st = TournamentLogic.enter(p, def, 50);
      TournamentLogic.recordResult(p, def, st, true);
      st = TournamentLogic.stateOf(p, def)!;
      TournamentLogic.recordResult(p, def, st, false);
      st = TournamentLogic.stateOf(p, def)!;
      expect(st.alive, isFalse);
      expect(st.won, isFalse);
      expect(st.round, 1);
      // next period starts fresh
      expect(TournamentLogic.stateOf(p, def, DateTime.now().add(const Duration(days: 8))), isNull);
    });

    test('AI-only matches resolve consistently and stronger seeds win more often', () {
      var strong = 0, total = 0;
      for (var s = 0; s < 60; s++) {
        final b = Bracket.generate(db, d8(), 'k$s', playerName: 'P', playerCc: 'MA', playerWpm: 40);
        b.resolveRound(0, playerWon: true);
        for (final m in b.rounds[0]) {
          if (m.involves(b.player)) continue;
          total++;
          final stronger = m.a.wpm > m.b.wpm ? m.a : m.b;
          if (m.winner!.id == stronger.id) strong++;
        }
      }
      expect(strong / total, greaterThan(0.6));
    });

    test('state survives a cloud merge (claimed rewards are a map, longer history wins)', () {
      final a = PlayerProfile.fresh('a'), b = PlayerProfile.fresh('b');
      final def = d8();
      final sa = TournamentLogic.enter(a, def, 40);
      TournamentLogic.recordResult(a, def, sa, true);
      TournamentLogic.enter(b, def, 40);
      final merged = ProfileMerger.merge(b, a);
      final ms = TournamentLogic.stateOf(merged, def)!;
      expect(ms.results.length, 1);
      expect(ms.claimed, contains(1));
    });
  });

  group('daily / weekly / world / link / custom', () {
    test('daily bonus is granted once per day and needs accuracy', () {
      final p = PlayerProfile.fresh('d');
      final now = DateTime(2026, 9, 30, 10);
      expect(DailyLogic.apply(p, res(acc: 80), now: now)['first'], 0);
      final a = DailyLogic.apply(p, res(wpm: 55), now: now);
      expect(a['first'], 1);
      expect(a['coins'], greaterThan(0));
      expect(DailyLogic.apply(p, res(wpm: 70), now: now)['first'], 0);
      expect(p.m('daily')['best'], 70);
      expect(p.counter('daily_done'), 1);
      expect(DailyLogic.dailyDone(p, now), isTrue);
      expect(DailyLogic.dailyDone(p, DateTime(2026, 10, 1)), isFalse);
      final w = DailyLogic.apply(p, res(), weekly: true, now: now);
      expect(w['gems'], 15);
    });

    test('world tour: stops unlock in order and need wpm + accuracy', () {
      final p = PlayerProfile.fresh('d');
      final first = db.cities.firstWhere((c) => c.idx == 0), second = db.cities.firstWhere((c) => c.idx == 1);
      expect(WorldTourLogic.unlocked(p, db, first), isTrue);
      expect(WorldTourLogic.unlocked(p, db, second), isFalse);
      expect(WorldTourLogic.passes(res(wpm: first.minWpm - 1.0), first), isFalse);
      expect(WorldTourLogic.passes(res(wpm: first.minWpm + 1.0, acc: 85), first), isFalse);
      final got = WorldTourLogic.apply(p, first, res(wpm: first.minWpm + 5.0));
      expect(got['coins'], greaterThan(0));
      expect(WorldTourLogic.unlocked(p, db, second), isTrue);
      expect(WorldTourLogic.apply(p, first, res(wpm: first.minWpm + 5.0))['coins'], 0);
      expect(p.worldStops, 1);
    });

    test('challenge links round-trip and reject tampering', () {
      const l = ChallengeLink(textId: 'en_s001', wpm: 72, name: 'Sami', cc: 'MA', acc: 96);
      final back = ChallengeLink.parse(l.webUri)!;
      expect(back.wpm, 72);
      expect(back.textId, 'en_s001');
      expect(back.name, 'Sami');
      expect(ChallengeLink.parse(l.appUri)!.wpm, 72);
      final tampered = l.webUri.replace(queryParameters: {...l.webUri.queryParameters, 'w': '200'});
      expect(ChallengeLink.parse(tampered), isNull);
      final absurd = ChallengeLink(textId: 't', wpm: 900, name: 'x');
      expect(ChallengeLink.parse(absurd.webUri), isNull);
      expect(ChallengeLink.parse(Uri.parse('https://x.y/?t=1')), isNull);
    });

    test('custom text sanitising', () {
      expect(sanitizeCustomText('“Hello”  world…\n\nit’s  fine'), '"Hello" world... it\'s fine');
      expect(sanitizeCustomText('café déjà vu', lang: 'en'), 'cafe deja vu');
      expect(sanitizeCustomText('café', lang: 'fr'), 'café');
      expect(sanitizeCustomText('a\u200Bb\tc'), 'ab c');
    });
  });
}
