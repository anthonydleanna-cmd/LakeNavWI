#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v057.patch.gz.b64.part00 | base64 -d | gzip -d > /tmp/v057.patch
patch -p1 < /tmp/v057.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 57/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.57.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v057-inline.js',s)"
node --check /tmp/lakenav-v057-inline.js
grep -q 'v0.57' app/src/main/assets/index.html
grep -q 'Selecting the symbol still opens the full NOAA ENC details popup' app/src/main/assets/index.html
if grep -q 'const showLabel=zoom>=14.5' app/src/main/assets/index.html; then
  echo 'Legacy automatic nav-aid labels still present' >&2
  exit 1
fi
printf 'LakeNav WI v0.57 navigation-aid labels hidden until marker selection.\n'
