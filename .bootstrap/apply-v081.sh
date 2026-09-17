#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
patch -p1 < .bootstrap/v081.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 81/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.81.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v081-inline.js',s)"
node --check /tmp/lakenav-v081-inline.js
grep -q 'v0.81' app/src/main/assets/index.html
grep -q 'createMarineBaseLayer' app/src/main/assets/index.html
! grep -q 'createWaterEmphasisLayer' app/src/main/assets/index.html
! grep -q 'quickWaterEmphasisToggle' app/src/main/assets/index.html
printf 'LakeNav WI v0.81 base-map water recolor applied.\n'
