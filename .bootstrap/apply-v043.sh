#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v043.patch.gz.b64 | base64 -d | gzip -d > /tmp/lakenav-v043.patch
patch -p1 < /tmp/lakenav-v043.patch
python3 - <<'PY'
from pathlib import Path
rp=Path('README.md')
r=rp.read_text()
if '## Version 0.43 features' not in r:
    insert='''\n## Version 0.43 features\n\n### Formal navigation-state cleanup\n- Adds a single navigation-state model that distinguishes Explore, Track, Waypoint Navigation, Route Navigation, Route Planning, North Up Follow, Course Up Acquisition/Follow, and Free Pan.\n- Track, waypoint, and route starts now enter follow mode through one shared transition path instead of several partially duplicated camera changes.\n- Free pan is a real navigation state in both Course Up and North Up. Once the user releases follow, GPS updates no longer unexpectedly recenter the map until Center/GPS is tapped.\n- Route drawing is an explicit planning state and temporarily suspends follow without losing the user's selected navigation behavior afterward.\n- Stopping a route/waypoint while Track remains active falls cleanly back to Track; stopping navigation with no active track falls back to Explore.\n- The map status chip now identifies the current operational state (for example TRACK • Course Up, ROUTE + TRACK • Course Up, FREE PAN • TRACK active, or PLAN • North Up).\n- Center/GPS now uses the same resume-follow transition as other navigation modes. Existing v0.41 GPS filtering and v0.42 screen-space free pan behavior remain intact.\n'''
    pos=r.find('\n## Version 0.42 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 43/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.43.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v043-inline.js',s)"
node --check /tmp/lakenav-v043-inline.js
grep -q 'v0.43' app/src/main/assets/index.html
grep -q 'navigationStateSnapshot' app/src/main/assets/index.html
grep -q 'resumeNavigationFollow' app/src/main/assets/index.html
grep -q 'Version 0.43 features' README.md
printf 'LakeNav WI v0.43 formal navigation-state cleanup applied.\n'
