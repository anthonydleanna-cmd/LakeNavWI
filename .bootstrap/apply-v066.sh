#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
base64 -d .bootstrap/v066.patch.gz.b64 | gzip -d > /tmp/v066.patch
patch -p1 < /tmp/v066.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 66/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.66.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v066-inline.js',s)"
node --check /tmp/lakenav-v066-inline.js
grep -q 'v0.66' app/src/main/assets/index.html
grep -q 'routeDrawPlaceBtn' app/src/main/assets/index.html
grep -q 'routeDrawTapContinue' app/src/main/assets/index.html
printf 'LakeNav WI v0.66 tap-and-continue route workflow applied.\n'
