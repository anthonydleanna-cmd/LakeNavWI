#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v053.patch.gz.b64.part00 .bootstrap/v053.patch.gz.b64.part01 | base64 -d | gzip -d > /tmp/v053.patch
patch -p1 < /tmp/v053.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 53/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.53.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v053-inline.js',s)"
node --check /tmp/lakenav-v053-inline.js
grep -q 'v0.53' app/src/main/assets/index.html
grep -q 'storedDepthShade' app/src/main/assets/index.html
grep -q 'softened detail blend' app/src/main/assets/index.html
grep -q 'fillOpacity:hasBase?.08:.40' app/src/main/assets/index.html
printf 'LakeNav WI v0.53 softer contour blending and first-launch depth default applied.\n'
