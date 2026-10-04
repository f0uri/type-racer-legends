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
        t = subprocess.run(['flutter', 'test', 'test/iap_test.dart', '--reporter', 'expanded'], capture_output=True, text=True, timeout=2400)
        tout = [l.rstrip() for l in ((t.stdout or '') + '\n' + (t.stderr or '')).splitlines()]
        print('::error ::IAP exit=%s lines=%d' % (t.returncode, len(tout)))
        shown = 0
        for i, line in enumerate(tout):
            if 'Expected:' in line or 'Actual:' in line or 'Which:' in line:
                for l in tout[max(0, i - 2): i + 6]:
                    print('::error ::' + l.replace('%', '%25')[:900])
                shown += 1
                if shown >= 6: break
        for l in [x for x in tout if x.strip()][-3:]:
            print('::error ::TAIL ' + l.replace('%', '%25')[:900])
    except Exception as e:
        print('::error ::TESTS diag failed: %s' % e)
