#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v046.patch.gz.b64.part00 | base64 -d | gzip -d > /tmp/v046.patch
patch -p1 < /tmp/v046.patch
python3 - <<'PY'
from pathlib import Path
p=Path('README.md')
r=p.read_text()
if '## Version 0.46 features' not in r:
    insert='''\n## Version 0.46 features\n\n### Time-styled breadcrumbs and Return Track\n- The current recorded breadcrumb now uses age bands so the newest five minutes are strongest, the next fifteen minutes are softer, and older travel remains as a faint base trail.\n- A Navigate back action is available from the Track menu and from each saved track in the Track Log.\n- Return Track simplifies long recordings into a manageable guidance route, reverses the current track automatically, and for saved tracks chooses the direction from the end closest to the current GPS position.\n- Return Track uses the existing route guidance engine, including Course Up, waypoint progression, ETA, cross-track error, and off-course warnings, but remains temporary and is not saved into the normal route list.\n- Return Track is drawn in cyan with reduced intermediate marker clutter so the original breadcrumb stays visually distinct.\n'''
    pos=r.find('\n## Version 0.45 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
p.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 46/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.46.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v046-inline.js',s)"
node --check /tmp/lakenav-v046-inline.js
grep -q 'v0.46' app/src/main/assets/index.html
grep -q 'renderTimedBreadcrumb' app/src/main/assets/index.html
grep -q 'startReturnTrackById' app/src/main/assets/index.html
grep -q 'Version 0.46 features' README.md
printf 'LakeNav WI v0.46 time breadcrumbs and Return Track applied.\n'
