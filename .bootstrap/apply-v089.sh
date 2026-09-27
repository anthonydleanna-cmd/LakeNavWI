#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

base64 -d .bootstrap/v089.patch.gz.b64 | gzip -d > /tmp/v089.patch
patch -p1 < /tmp/v089.patch

sed -i "s/versionCode [0-9][0-9]*/versionCode 89/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.89.0'/" app/build.gradle

node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v089-inline.js',s)"
node --check /tmp/lakenav-v089-inline.js

grep -q 'v0.89' app/src/main/assets/index.html
grep -q 'syncBackgroundTrackFromNative' app/src/main/assets/index.html
grep -q 'startBackgroundTrack' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'class BackgroundTrackService' app/src/main/java/com/lakenav/wi/BackgroundTrackService.java
grep -q 'FOREGROUND_SERVICE_LOCATION' app/src/main/AndroidManifest.xml
grep -q 'foregroundServiceType="location"' app/src/main/AndroidManifest.xml
grep -q 'Version 0.89 features' README.md
printf 'LakeNav WI v0.89 background track reliability applied.\n'
