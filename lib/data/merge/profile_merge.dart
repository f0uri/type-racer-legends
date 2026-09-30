import '../models/profile.dart';

/// Conflict-free merge of two player profiles. Never destroys progress:
/// - additive values are per-device grow-only counters (max per device, then summed)
/// - bests use max, collections use union, settings/selection use last-writer-wins
class ProfileMerger {
  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  static Map<String, dynamic> _mm(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static Map<String, dynamic> _unionMin(dynamic a, dynamic b) {
    final r = _mm(a);
    _mm(b).forEach((k, v) {
      r[k] = r.containsKey(k) ? (_i(r[k]) < _i(v) ? r[k] : v) : v;
    });
    return r;
  }

  static Map<String, dynamic> _maxMap(dynamic a, dynamic b) {
    final r = _mm(a);
    _mm(b).forEach((k, v) {
      r[k] = r.containsKey(k) ? ((r[k] as num) >= (v as num) ? r[k] : v) : v;
    });
    return r;
  }

  static Map<String, dynamic> _orMap(dynamic a, dynamic b) {
    final r = _mm(a);
    _mm(b).forEach((k, v) {
      r[k] = (r[k] == true) || (v == true);
    });
    return r;
  }

  static List<dynamic> _unionList(dynamic a, dynamic b) {
    final s = <dynamic>{...((a as List?) ?? []), ...((b as List?) ?? [])};
    return s.toList();
  }

  static Map<String, dynamic> _period(dynamic a, dynamic b) {
    final x = _mm(a), y = _mm(b);
    if (x.isEmpty) return y;
    if (y.isEmpty) return x;
    final kx = (x['key'] ?? '').toString(), ky = (y['key'] ?? '').toString();
    if (kx.compareTo(ky) > 0) return x;
    if (kx.compareTo(ky) < 0) return y;
    // same period: keep the more advanced record (longer result list), then union what was claimed
    final lx = (x['res'] is List) ? (x['res'] as List).length : 0, ly = (y['res'] is List) ? (y['res'] as List).length : 0;
    final r = _mm(ly > lx ? y : x);
    r['claimed'] = _orMap(x['claimed'], y['claimed']);
    r['base'] = _maxMap(x['base'], y['base']);
    r['best'] = _maxMap({'v': x['best'] ?? 0}, {'v': y['best'] ?? 0})['v'];
    if (x['done'] == true || y['done'] == true) r['done'] = true;
    return r;
  }

  static PlayerProfile merge(PlayerProfile local, PlayerProfile remote) {
    final a = local.d, b = remote.d;
    final r = <String, dynamic>{...b, ...a}; // defaults: local wins on unknown keys
    r['v'] = _i(a['v']) > _i(b['v']) ? a['v'] : b['v'];
    r['deviceId'] = a['deviceId'];
    r['uid'] = a['uid'] ?? b['uid'];
    r['updatedAt'] = _i(a['updatedAt']) > _i(b['updatedAt']) ? a['updatedAt'] : b['updatedAt'];
    r['rev'] = (_i(a['rev']) > _i(b['rev']) ? _i(a['rev']) : _i(b['rev'])) + 1;

    // identity: last writer wins
    final newerIdentity = _i(a['profileAt']) >= _i(b['profileAt']) ? a : b;
    final olderIdentity = identical(newerIdentity, a) ? b : a;
    for (final k in ['name', 'country', 'avatar', 'title', 'refCode', 'profileAt']) {
      r[k] = newerIdentity[k] ?? olderIdentity[k];
    }
    r['referredBy'] = a['referredBy'] ?? b['referredBy'];

    // counters
    final ca = _mm(a['c']), cb = _mm(b['c']);
    final c = <String, dynamic>{};
    for (final k in {...ca.keys, ...cb.keys}) {
      c[k] = _maxMap(ca[k], cb[k]);
    }
    r['c'] = c;
    r['b'] = _maxMap(a['b'], b['b']);

    // vehicles
    final va = _mm(a['vehicles']), vb = _mm(b['vehicles']);
    final v = <String, dynamic>{};
    for (final id in {...va.keys, ...vb.keys}) {
      final x = va[id] as Map?, y = vb[id] as Map?;
      if (x == null || y == null) {
        v[id] = Map<String, dynamic>.from((x ?? y) as Map);
        continue;
      }
      final loWinner = _i(x['loAt']) >= _i(y['loAt']) ? x : y;
      v[id] = {
        'at': _i(x['at']) < _i(y['at']) ? x['at'] : y['at'],
        'upg': _maxMap(x['upg'], y['upg']),
        'lo': Map<String, dynamic>.from((loWinner['lo'] as Map?) ?? {}),
        'loAt': _i(loWinner['loAt']),
      };
    }
    r['vehicles'] = v;
    for (final k in ['skins', 'outfits', 'titles', 'ach', 'achClaimed', 'bossWon', 'lessons', 'seenItems']) {
      r[k] = _unionMin(a[k], b[k]);
    }
    final sa = _mm(a['sel']), sb = _mm(b['sel']);
    r['sel'] = _i(sa['at']) >= _i(sb['at']) ? sa : sb;

    // quests
    final qa = _mm(a['quests']), qb = _mm(b['quests']);
    r['quests'] = {'daily': _period(qa['daily'], qb['daily']), 'weekly': _period(qa['weekly'], qb['weekly'])};

    // streak
    final ta = _mm(a['streak']), tb = _mm(b['streak']);
    final la = (ta['last'] ?? '').toString(), lb = (tb['last'] ?? '').toString();
    Map<String, dynamic> st;
    if (la.compareTo(lb) > 0) {
      st = ta;
    } else if (la.compareTo(lb) < 0) {
      st = tb;
    } else {
      st = _i(ta['count']) >= _i(tb['count']) ? ta : tb;
    }
    r['streak'] = {'count': _i(st['count']), 'last': st['last'] ?? '', 'best': _i(ta['best']) > _i(tb['best']) ? _i(ta['best']) : _i(tb['best'])};

    // season
    final ea = _mm(a['season']), eb = _mm(b['season']);
    if (_i(ea['id']) > _i(eb['id'])) {
      r['season'] = ea;
    } else if (_i(ea['id']) < _i(eb['id'])) {
      r['season'] = eb;
    } else {
      r['season'] = {
        'id': _i(ea['id']),
        'premium': ea['premium'] == true || eb['premium'] == true,
        'free': _unionList(ea['free'], eb['free']),
        'prem': _unionList(ea['prem'], eb['prem']),
      };
    }

    r['campaign'] = _maxMap(a['campaign'], b['campaign']);
    r['world'] = _maxMap(a['world'], b['world']);

    // settings LWW
    if (_i(a['settingsAt']) >= _i(b['settingsAt'])) {
      r['settings'] = _mm(a['settings']);
      r['settingsAt'] = a['settingsAt'];
    } else {
      r['settings'] = _mm(b['settings']);
      r['settingsAt'] = b['settingsAt'];
    }
    r['flags'] = _orMap(a['flags'], b['flags']);

    // history LWW
    if (_i(a['histAt']) >= _i(b['histAt'])) {
      r['hist'] = a['hist'];
      r['histAt'] = a['histAt'];
    } else {
      r['hist'] = b['hist'];
      r['histAt'] = b['histAt'];
    }

    // char stats: element-wise max
    final cha = _mm(a['charStats']), chb = _mm(b['charStats']);
    final cs = <String, dynamic>{};
    for (final k in {...cha.keys, ...chb.keys}) {
      final x = (cha[k] as List?) ?? [0, 0, 0], y = (chb[k] as List?) ?? [0, 0, 0];
      cs[k] = List.generate(3, (i) => _i(x[i]) > _i(y[i]) ? _i(x[i]) : _i(y[i]));
    }
    r['charStats'] = cs;

    r['daily'] = _period(a['daily'], b['daily']);
    r['weeklyCh'] = _period(a['weeklyCh'], b['weeklyCh']);
    final evA = _mm(a['events']), evB = _mm(b['events']);
    final ev = <String, dynamic>{};
    for (final k in {...evA.keys, ...evB.keys}) {
      final x = _mm(evA[k]), y = _mm(evB[k]);
      ev[k] = {'claimed': _orMap(x['claimed'], y['claimed']), 'base': _maxMap(x['base'], y['base'])};
    }
    r['events'] = ev;
    final tA = _mm(a['tourn']), tB = _mm(b['tourn']);
    final tr = <String, dynamic>{};
    for (final k in {...tA.keys, ...tB.keys}) {
      tr[k] = _period(tA[k], tB[k]);
    }
    r['tourn'] = tr;
    r['chests'] = _maxMap(a['chests'], b['chests']);

    final pa = (a['pendingPurchases'] as List?) ?? [], pb = (b['pendingPurchases'] as List?) ?? [];
    final seen = <String>{};
    r['pendingPurchases'] = [...pa, ...pb].where((e) => seen.add((e as Map)['token'].toString())).toList();
    return PlayerProfile(r);
  }

  /// Summary fields mirrored at the top level of the Firestore user document.
  static Map<String, dynamic> summary(PlayerProfile p) {
    final li = p.level();
    return {
      'name': p.name,
      'country': p.country,
      'level': li.level,
      'xp': p.xp,
      'coins': p.coins < 0 ? 0 : p.coins,
      'gems': p.gems < 0 ? 0 : p.gems,
      'bestWpm': p.best('bestWpm').round(),
      'rankPoints': p.rankPoints,
      'streak': p.streak,
      'lastPlayedAt': p.streakLast,
      'refCode': p.refCode,
    };
  }
}
