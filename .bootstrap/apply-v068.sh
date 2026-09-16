#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
base64 -d .bootstrap/v068.patch.gz.b64 | gzip -d > /tmp/v068.patch
patch -p1 < /tmp/v068.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 68/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.68.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v068-inline.js',s)"
node --check /tmp/lakenav-v068-inline.js
grep -q 'v0.68' app/src/main/assets/index.html
grep -q 'bindSheetSwipeToClose' app/src/main/assets/index.html
grep -q 'lockNavigationPuckBeforeReveal' app/src/main/assets/index.html
grep -q 'resyncNavigationPuckAfterStop' app/src/main/assets/index.html
printf 'LakeNav WI v0.68 dark route cards, swipe-down sheets, and navigation puck handoff applied.\n'
