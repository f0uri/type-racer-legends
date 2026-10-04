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
# CI hides step logs from the sandbox, so the analyzer output is re-emitted as check
# annotations, which the API does expose.
import subprocess
if os.environ.get('GITHUB_ACTIONS') == 'true':
    try:
        r = subprocess.run(['flutter', 'analyze', '--no-fatal-infos'], capture_output=True, text=True, timeout=1500)
        out = ((r.stdout or '') + '\n' + (r.stderr or '')).strip()
        entries, summary = [], []
        for line in out.splitlines():
            if not line.strip(): continue
            parts = [p.strip() for p in line.split('\u2022')]
            if len(parts) >= 4 and parts[0] in ('error', 'warning', 'info'):
                entries.append('%s | %s | %s: %s' % (parts[0], parts[3], parts[2], parts[1]))
            elif 'issue' in line or 'No issues' in line:
                summary.append(line.strip())
        print('::error ::ANALYZE exit=%s issues=%d' % (r.returncode, len(entries)))
        for e in entries[:20]:
            print('::error ::' + e.replace('%', '%25').replace('\r', ' ')[:900])
        for s in summary[-2:]:
            print('::error ::' + s.replace('%', '%25')[:900])
    except Exception as e:
        print('::error ::diagnostic failed: %s' % e)
