#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
patch -p1 < .bootstrap/v080.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 80/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.80.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v080-inline.js',s)"
node --check /tmp/lakenav-v080-inline.js
grep -q 'v0.80' app/src/main/assets/index.html
grep -q 'hydro.nationalmap.gov' app/src/main/assets/index.html
if grep -q "mapLayerId:1" app/src/main/assets/index.html; then echo 'v0.80 still contains stream centerline styling'; exit 1; fi
printf 'LakeNav WI v0.80 brighter water-area tint applied.\n'
