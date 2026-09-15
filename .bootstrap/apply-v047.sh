#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v047.patch.gz.b64.part00 .bootstrap/v047.patch.gz.b64.part01 | base64 -d | gzip -d > /tmp/v047.patch
patch -p1 < /tmp/v047.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 47/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.47.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v047-inline.js',s)"
node --check /tmp/lakenav-v047-inline.js
grep -q 'v0.47' app/src/main/assets/index.html
grep -q 'setTrackPaused' app/src/main/assets/index.html
grep -q 'tripSummarySheet' app/src/main/assets/index.html
grep -q 'buildTripSummary' app/src/main/assets/index.html
printf 'LakeNav WI v0.47 track pause/resume and trip summary applied.\n'
