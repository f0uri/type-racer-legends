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
        t = subprocess.run(['flutter', 'test', '--reporter', 'json'], capture_output=True, text=True, timeout=2400)
        names, fails, prints, errors = {}, [], {}, {}
        for line in (t.stdout or '').splitlines():
            line = line.strip()
            if not line.startswith('{'): continue
            try: ev = json.loads(line)
            except Exception: continue
            kind = ev.get('type')
            if kind == 'testStart':
                names[ev['test']['id']] = ev['test'].get('name', '?')
            elif kind == 'print':
                prints.setdefault(ev.get('testID'), []).append(ev.get('message') or '')
            elif kind == 'error':
                errors.setdefault(ev.get('testID'), []).append((ev.get('error') or ''))
            elif kind == 'testDone' and ev.get('result') != 'success' and not ev.get('hidden'):
                fails.append(ev.get('testID'))
        print('::error ::TESTS exit=%s failed=%d' % (t.returncode, len(fails)))
        for tid in fails[:4]:
            pieces = []
            for msg in errors.get(tid, []):
                for piece in msg.splitlines():
                    piece = piece.strip()
                    if piece: pieces.append(piece)
            hot, frames = [], []
            for piece in pieces:
                if 'overflowed by' in piece or 'Bad state' in piece or 'was thrown' in piece:
                    if piece not in hot: hot.append(piece)
                if 'relevant error-causing widget' in piece:
                    hot.append(piece)
                if 'package:type_racer_legends/' in piece or 'test/layout_sizes_test.dart' in piece:
                    if piece not in frames: frames.append(piece)
            body = ' || '.join(hot[:2] + frames[:3])
            print('::error ::FAIL %s :: %s' % (names.get(tid, '?')[:52], body.replace('%', '%25')[:880]))
    except Exception as e:
        print('::error ::TESTS diag failed: %s' % e)
