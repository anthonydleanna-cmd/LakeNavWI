#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

base64 -d .bootstrap/v090.patch.gz.b64 | gzip -d > /tmp/v090.patch
patch -p1 < /tmp/v090.patch

sed -i "s/versionCode [0-9][0-9]*/versionCode 90/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.90.0'/" app/build.gradle

node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v090-inline.js',s)"
node --check /tmp/lakenav-v090-inline.js

grep -q 'v0.90' app/src/main/assets/index.html
grep -q 'navTouchLockShield' app/src/main/assets/index.html
grep -q 'HOLD TO UNLOCK' app/src/main/assets/index.html
grep -q 'navigationTouchLocked' app/src/main/assets/index.html
grep -q 'LakeNavWI/0.90' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'Version 0.90 features' README.md
printf 'LakeNav WI v0.90 navigation touch lock applied.\n'
