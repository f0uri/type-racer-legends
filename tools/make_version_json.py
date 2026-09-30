#!/usr/bin/env python3
"""Generates version.json for the in-app updater (used for APKs installed outside Google Play)."""
import hashlib, json, os, sys, datetime
apk, name, code, repo, tag = sys.argv[1:6]
h = hashlib.sha256(open(apk, 'rb').read()).hexdigest()
cfg = json.load(open('update_config.json')) if os.path.exists('update_config.json') else {}
notes_ar = open('RELEASE_NOTES_AR.md', encoding='utf-8').read().strip() if os.path.exists('RELEASE_NOTES_AR.md') else 'تحسينات وإصلاحات.'
data = {
    "versionCode": int(code), "versionName": name,
    "apkUrl": f"https://github.com/{repo}/releases/download/{tag}/{os.path.basename(apk)}",
    "size": os.path.getsize(apk), "sha256": h,
    "notes": {"ar": notes_ar, "en": cfg.get("notesEn", "Improvements and bug fixes."), "fr": cfg.get("notesFr", "Améliorations et corrections.")},
    "minSupportedVersion": int(cfg.get("minSupportedVersion", 1)),
    "mandatory": bool(cfg.get("mandatory", False)),
    "publishedAt": datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
}
json.dump(data, open('version.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print(json.dumps(data, ensure_ascii=False, indent=2))
