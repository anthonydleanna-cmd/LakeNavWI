#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
base64 -d .bootstrap/v072.patch.gz.b64 | gzip -d > /tmp/v072.patch
patch -p1 < /tmp/v072.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 72/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.72.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v072-inline.js',s)"
node --check /tmp/lakenav-v072-inline.js
grep -q 'v0.72' app/src/main/assets/index.html
grep -q 'opticalShallowsToggle' app/src/main/assets/index.html
grep -q 'planetarycomputer.microsoft.com' app/src/main/assets/index.html
printf 'LakeNav WI v0.72 Optical Shallows layer applied.\n'
