#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
base64 -d .bootstrap/v067.patch.gz.b64 | gzip -d > /tmp/v067.patch
patch -p1 < /tmp/v067.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 67/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.67.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v067-inline.js',s)"
node --check /tmp/lakenav-v067-inline.js
grep -q 'v0.67' app/src/main/assets/index.html
grep -q 'routeDrawSavedBtn' app/src/main/assets/index.html
grep -q 'openSavedRoutesFromPlanner' app/src/main/assets/index.html
grep -q 'route-plan-end-explore' app/src/main/assets/index.html
printf 'LakeNav WI v0.67 saved-route access and stable route-planner exit applied.\n'
