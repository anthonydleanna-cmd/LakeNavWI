#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

base64 -d .bootstrap/v093.patch.gz.b64 | gzip -d > /tmp/v093.patch
patch -p1 < /tmp/v093.patch

sed -i "s/versionCode [0-9][0-9]*/versionCode 93/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.93.0'/" app/build.gradle

node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v093-inline.js',s)"
node --check /tmp/lakenav-v093-inline.js

grep -q 'v0.93' app/src/main/assets/index.html
grep -q 'WI-FI ASSIST' app/src/main/assets/index.html
grep -q 'isWifiConnected' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'assistedFix' app/src/main/java/com/lakenav/wi/NavigationService.java
grep -q 'Version 0.93 features' README.md
printf 'LakeNav WI v0.93 indoor Wi-Fi location assist applied.\n'
