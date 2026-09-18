#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

base64 -d .bootstrap/v086_transform.py.gz.b64 | gzip -d > /tmp/lakenav-v086-transform.py
python3 /tmp/lakenav-v086-transform.py

sed -i "s/versionCode [0-9][0-9]*/versionCode 86/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.86.0'/" app/build.gradle

node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v086-inline.js',s)"
node --check /tmp/lakenav-v086-inline.js

grep -q 'v0.86' app/src/main/assets/index.html
grep -q 'shouldAcceptNativeLocation' app/src/main/assets/index.html
grep -q 'gpsQualityProvider' app/src/main/assets/index.html
grep -q 'NAV_CONTINUITY_NOFIX_MAX_MS = 8000' app/src/main/assets/index.html
grep -q 'const minInterval=340' app/src/main/assets/index.html
grep -q 'getElapsedRealtimeNanos' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'LocationManager.GPS_PROVIDER, 500L, 0.0f' app/src/main/java/com/lakenav/wi/MainActivity.java

printf 'LakeNav WI v0.86 navigation hardening applied.\n'
