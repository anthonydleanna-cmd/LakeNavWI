#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v049.patch.gz.b64.part00 .bootstrap/v049.patch.gz.b64.part01 .bootstrap/v049.patch.gz.b64.part02 | base64 -d | gzip -d > /tmp/v049.patch
patch -p1 < /tmp/v049.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 49/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.49.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v049-inline.js',s)"
node --check /tmp/lakenav-v049-inline.js
grep -q 'v0.49' app/src/main/assets/index.html
grep -q 'depthSourceBadge' app/src/main/assets/index.html
grep -q 'noaaAidSymbolMeta' app/src/main/assets/index.html
grep -q 'chooseDepth2dGroup' app/src/main/assets/index.html
grep -q 'depthReferenceBtn' app/src/main/assets/index.html
printf 'LakeNav WI v0.49 data-aware bathymetry and navigation-aid refinements applied.\n'
