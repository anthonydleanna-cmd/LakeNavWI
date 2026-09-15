#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v054.patch.gz.b64.part00 \
    .bootstrap/v054.patch.gz.b64.part01 \
    .bootstrap/v054.patch.gz.b64.part02 \
    .bootstrap/v054.patch.gz.b64.part03 \
    .bootstrap/v054.patch.gz.b64.part04 \
  | base64 -d | gzip -d > /tmp/v054.patch
patch -p1 < /tmp/v054.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 54/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.54.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v054-inline.js',s)"
node --check /tmp/lakenav-v054-inline.js
grep -q 'v0.54' app/src/main/assets/index.html
grep -q 'windGridCoversBounds' app/src/main/assets/index.html
grep -q 'refreshWindForCurrentView' app/src/main/assets/index.html
grep -q 'darkModeToggle' app/src/main/assets/index.html
grep -q 'depthLegendToggle' app/src/main/assets/index.html
grep -q 'STORAGE_DARK_MODE' app/src/main/assets/index.html
printf 'LakeNav WI v0.54 wind reflow, dark mode, and collapsible depth legend applied.\n'
