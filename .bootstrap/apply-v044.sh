#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
patch -p1 < .bootstrap/v044.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 44/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.44.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v044-inline.js',s)"
node --check /tmp/lakenav-v044-inline.js
grep -q 'v0.44' app/src/main/assets/index.html
grep -q 'routeCrossTrackInfo' app/src/main/assets/index.html
grep -q 'xteLimitSelect' app/src/main/assets/index.html
printf 'LakeNav WI v0.44 cross-track guidance applied.\n'
