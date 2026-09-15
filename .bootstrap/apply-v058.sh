#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v058.patch.gz.b64.part00 \
    .bootstrap/v058.patch.gz.b64.part01 \
  | base64 -d | gzip -d > /tmp/v058.patch
patch -p1 < /tmp/v058.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 58/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.58.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v058-inline.js',s)"
node --check /tmp/lakenav-v058-inline.js
grep -q 'v0.58' app/src/main/assets/index.html
grep -q 'tool.primaryTool' app/src/main/assets/index.html
grep -q 'Loading chart aids' app/src/main/assets/index.html
grep -q 'setTimeout(()=>{' app/src/main/assets/index.html
printf 'LakeNav WI v0.58 NOAA startup recovery and dark toolbar fix applied.\n'
