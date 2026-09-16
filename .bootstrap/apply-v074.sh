#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
cat .bootstrap/v074.patch.part00 .bootstrap/v074.patch.part01 .bootstrap/v074.patch.part02 .bootstrap/v074.patch.part03 > /tmp/lakenav-v074.patch
patch -p1 < /tmp/lakenav-v074.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 74/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.74.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v074-inline.js',s)"
node --check /tmp/lakenav-v074-inline.js
grep -q 'v0.74' app/src/main/assets/index.html
grep -q 'clearSelectedLakeDiscovery' app/src/main/assets/index.html
grep -q 'refreshSelectedLakeLaunches' app/src/main/assets/index.html
grep -q 'lakeDiscoveryLaunchList' app/src/main/assets/index.html
printf 'LakeNav WI v0.74 lake deselection and launch integration applied.\n'
