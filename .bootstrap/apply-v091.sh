#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

cp .bootstrap/v091_NavigationService.java app/src/main/java/com/lakenav/wi/NavigationService.java
python3 .bootstrap/v091_transform.py

sed -i "s/versionCode [0-9][0-9]*/versionCode 91/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.91.0'/" app/build.gradle

node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)].map(x=>x[1]).join('\n');fs.writeFileSync('/tmp/lakenav-v091-inline.js',s)"
node --check /tmp/lakenav-v091-inline.js

grep -q 'v0.91' app/src/main/assets/index.html
grep -q 'syncLockScreenNavigationFromNative' app/src/main/assets/index.html
grep -q 'startLockScreenNavigation' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'class NavigationService' app/src/main/java/com/lakenav/wi/NavigationService.java
grep -q 'foregroundServiceType="location"' app/src/main/AndroidManifest.xml
grep -q 'Version 0.91 features' README.md
printf 'LakeNav WI v0.91 lock-screen navigation applied.\n'
