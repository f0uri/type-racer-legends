#!/usr/bin/env python3
"""Rebuilds content/catalog.json: file list, sha256, per-file version (auto bump on change) and catalog version.
Hand-maintained fields in catalog.json (killSwitch, featured, dailyPool, minAppVersion) are preserved."""
import json, os, hashlib, datetime, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'content')
cat_path = os.path.join(ROOT, 'catalog.json')
old = json.load(open(cat_path, encoding='utf-8')) if os.path.exists(cat_path) else {}
oldfiles = old.get('files', {})
files = {}; changed = False
for dp, _, fns in os.walk(ROOT):
    for fn in sorted(fns):
        if not fn.endswith('.json') or fn == 'catalog.json': continue
        full = os.path.join(dp, fn); rel = os.path.relpath(full, ROOT).replace(os.sep, '/')
        data = open(full, 'rb').read()
        try: json.loads(data)
        except Exception as e: sys.exit(f'INVALID JSON {rel}: {e}')
        h = hashlib.sha256(data).hexdigest(); key = rel[:-5]
        prev = oldfiles.get(key)
        ver = 1 if not prev else (prev['version'] if prev['sha256'] == h else prev['version'] + 1)
        if not prev or prev['sha256'] != h: changed = True
        files[key] = {"path": rel, "version": ver, "sha256": h, "bytes": len(data)}
if set(oldfiles) != set(files): changed = True
cat = {"schema": 1, "version": old.get('version', 0) + (1 if changed or not old else 0), "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
       "minAppVersion": old.get('minAppVersion', 1),
       "killSwitch": old.get('killSwitch', {"features": [], "items": []}),
       "featured": old.get('featured', {"shop": ["c_vortex", "p_aurora", "b_crimson", "n_rainbow"]}),
       "dailyPool": old.get('dailyPool', []), "files": files}
if not changed and old: cat['generatedAt'] = old.get('generatedAt', cat['generatedAt'])
json.dump(cat, open(cat_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
open(cat_path + '.sha256', 'w').write(hashlib.sha256(open(cat_path, 'rb').read()).hexdigest())
print('catalog v%d, %d files, changed=%s' % (cat['version'], len(files), changed))

# --- TEMPORARY DIAGNOSTIC (removed right after the output is read) -------------
import subprocess
if os.environ.get('GITHUB_ACTIONS') == 'true':
    try:
        r = subprocess.run(['flutter', 'analyze', '--no-fatal-infos'], capture_output=True, text=True, timeout=1500)
        out = ((r.stdout or '') + '\n' + (r.stderr or '')).strip()
        lines = out.splitlines()
        fatal, infos = [], 0
        for line in lines:
            parts = [x.strip() for x in line.split('\u2022')]
            if len(parts) >= 4 and parts[0] in ('error', 'warning', 'info'):
                if parts[0] == 'info':
                    infos += 1
                    continue
                fatal.append('%s | %s | %s: %s' % (parts[0], parts[3], parts[2], parts[1]))
        print('::error ::DIAG exit=%s lines=%d fatal=%d infos=%d' % (r.returncode, len(lines), len(fatal), infos))
        for e in fatal[:22]:
            print('::error ::' + e.replace('%', '%25').replace('\r', ' ')[:900])
        for line in lines[-4:]:
            print('::error ::RAW ' + line.replace('%', '%25').replace('\r', ' ')[:400])
    except Exception as e:
        print('::error ::DIAG failed: %s' % e)
    try:
        t = subprocess.run(['flutter', 'test', '--reporter', 'json'], capture_output=True, text=True, timeout=2400)
        names, fails, prints = {}, [], {}
        for line in (t.stdout or '').splitlines():
            line = line.strip()
            if not line.startswith('{'): continue
            try: ev = json.loads(line)
            except Exception: continue
            kind = ev.get('type')
            if kind == 'testStart':
                names[ev['test']['id']] = ev['test'].get('name', '?')
            elif kind == 'print':
                prints.setdefault(ev.get('testID'), []).append((ev.get('message') or ''))
            elif kind == 'testDone' and ev.get('result') != 'success' and not ev.get('hidden'):
                fails.append(ev.get('testID'))
        print('::error ::TESTS exit=%s failed=%d' % (t.returncode, len(fails)))
        # one line per failing test: the runner keeps only the last ~10 annotations, so the
        # readout must be small and dense.
        for tid in fails[:3]:
            pieces = []
            for msg in prints.get(tid, []):
                for piece in msg.splitlines():
                    piece = piece.strip()
                    if not piece or len(piece) < 4: continue
                    pieces.append(piece)
            picks = []
            for idx, piece in enumerate(pieces):
                if 'relevant error-causing widget' in piece:
                    nxt = pieces[idx + 1] if idx + 1 < len(pieces) else ''
                    picks.append('CAUSE ' + nxt)
                elif 'overflowed by' in piece or 'hit test' in piece or 'Bad state' in piece:
                    picks.append(piece)
            print('::error ::FAIL %s :: %s' % (names.get(tid, '?')[:60], (' || '.join(picks[:4])).replace('%', '%25')[:850]))
    except Exception as e:
        print('::error ::TESTS diag failed: %s' % e)
