#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v041.patch.gz.b64 | base64 -d | gzip -d > /tmp/lakenav-v041.patch
patch -p1 < /tmp/lakenav-v041.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 41/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.41.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v041-inline.js',s)"
node --check /tmp/lakenav-v041-inline.js
grep -q 'v0.41' app/src/main/assets/index.html
grep -q 'isTransientGpsOutlier' app/src/main/assets/index.html
grep -q 'isTrackDirectionalOutlier' app/src/main/assets/index.html
grep -q 'versionCode 41' app/build.gradle
printf 'LakeNav WI v0.41 GPS jump and track vertex guards applied.\n'
