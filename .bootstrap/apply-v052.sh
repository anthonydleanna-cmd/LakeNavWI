#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v052.patch.gz.b64.part00 .bootstrap/v052.patch.gz.b64.part01 .bootstrap/v052.patch.gz.b64.part02 .bootstrap/v052.patch.gz.b64.part03 | base64 -d | gzip -d > /tmp/v052.patch
patch -p1 < /tmp/v052.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 52/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.52.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v052-inline.js',s)"
node --check /tmp/lakenav-v052-inline.js
grep -q 'v0.52' app/src/main/assets/index.html
grep -q 'depthVerifiedSurfaceCache' app/src/main/assets/index.html
grep -q 'chooseDepthBaseGroup' app/src/main/assets/index.html
grep -q 'broader verified coverage stays underneath detailed chart data' app/src/main/assets/index.html
printf 'LakeNav WI v0.52 continuous verified-depth surface rendering applied.\n'
