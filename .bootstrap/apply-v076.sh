#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
cat .bootstrap/v076.patch.part00 .bootstrap/v076.patch.part01 .bootstrap/v076.patch.part02 > /tmp/lakenav-v076.patch
patch -p1 < /tmp/lakenav-v076.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 76/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.76.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v076-inline.js',s)"
node --check /tmp/lakenav-v076-inline.js
grep -q 'v0.76' app/src/main/assets/index.html
grep -q 'lakeLibrarySheet' app/src/main/assets/index.html
grep -q 'STORAGE_LAKE_FAVORITES' app/src/main/assets/index.html
grep -q 'refreshLakeLibraryNearby' app/src/main/assets/index.html
grep -q 'lakeDiscoveryFavoriteBtn' app/src/main/assets/index.html
printf 'LakeNav WI v0.76 lake library applied.\n'
