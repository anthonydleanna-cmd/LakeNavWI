#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
cat .bootstrap/v077.patch.part00 .bootstrap/v077.patch.part01 .bootstrap/v077.patch.part02 > /tmp/lakenav-v077.patch
patch -p1 < /tmp/lakenav-v077.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 77/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.77.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v077-inline.js',s)"
node --check /tmp/lakenav-v077-inline.js
grep -q 'v0.77' app/src/main/assets/index.html
grep -q 'Recently boated' app/src/main/assets/index.html
grep -q 'syncRecentlyBoatedFromTrackLogs' app/src/main/assets/index.html
grep -q 'geometryType=esriGeometryPolyline' app/src/main/assets/index.html
printf 'LakeNav WI v0.77 Recently Boated applied.\n'
