#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
base64 -d .bootstrap/v069.patch.gz.b64 | gzip -d > /tmp/v069.patch
patch -p1 < /tmp/v069.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 69/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.69.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v069-inline.js',s)"
node --check /tmp/lakenav-v069-inline.js
grep -q 'v0.69' app/src/main/assets/index.html
grep -q 'windAnimationToggle' app/src/main/assets/index.html
grep -q 'STORAGE_WIND_ANIMATION' app/src/main/assets/index.html
printf 'LakeNav WI v0.69 wind readout-only mode applied.\n'
