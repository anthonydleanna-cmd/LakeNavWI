#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v055.patch.gz.b64.part00 .bootstrap/v055.patch.gz.b64.part01 .bootstrap/v055.patch.gz.b64.part02 | base64 -d | gzip -d > /tmp/v055.patch
patch -p1 < /tmp/v055.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 55/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.55.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v055-inline.js',s)"
node --check /tmp/lakenav-v055-inline.js
grep -q 'v0.55' app/src/main/assets/index.html
grep -q 'radarOpacityForZoom' app/src/main/assets/index.html
grep -q 'crossfadeRadarTo' app/src/main/assets/index.html
grep -q 'radarNextLayer' app/src/main/assets/index.html
printf 'LakeNav WI v0.55 adaptive radar opacity and crossfade applied.\n'
