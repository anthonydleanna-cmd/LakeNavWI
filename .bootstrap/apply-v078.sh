#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
patch -p1 < .bootstrap/v078.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 78/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.78.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v078-inline.js',s)"
node --check /tmp/lakenav-v078-inline.js
grep -q 'v0.78' app/src/main/assets/index.html
grep -q 'toggleHistoryTrack' app/src/main/assets/index.html
grep -q 'bubblingMouseEvents:false' app/src/main/assets/index.html
printf 'LakeNav WI v0.78 saved track show/hide fix applied.\n'
