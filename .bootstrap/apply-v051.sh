#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v051.patch.gz.b64.part00 .bootstrap/v051.patch.gz.b64.part01 | base64 -d | gzip -d > /tmp/v051.patch
patch -p1 < /tmp/v051.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 51/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.51.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v051-inline.js',s)"
node --check /tmp/lakenav-v051-inline.js
grep -q 'v0.51' app/src/main/assets/index.html
grep -q 'depthCachedGroups' app/src/main/assets/index.html
grep -q 'renderDepth2dFromGroups' app/src/main/assets/index.html
grep -q 'zoomingOut' app/src/main/assets/index.html
printf 'LakeNav WI v0.51 smooth verified-depth zoom handoff applied.\n'
