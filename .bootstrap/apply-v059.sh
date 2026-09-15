#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

cat .bootstrap/v059.patch.gz.b64.part00 \
    .bootstrap/v059.patch.gz.b64.part01 \
    .bootstrap/v059.patch.gz.b64.part02 \
    .bootstrap/v059.patch.gz.b64.part03 \
    .bootstrap/v059.patch.gz.b64.part04 \
    .bootstrap/v059.patch.gz.b64.part05 \
    .bootstrap/v059.patch.gz.b64.part06 \
    .bootstrap/v059.patch.gz.b64.part07 \
  | base64 -d | gzip -d > /tmp/v059.patch

patch -p1 < /tmp/v059.patch

sed -i "s/versionCode [0-9][0-9]*/versionCode 59/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.59.0'/" app/build.gradle

node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v059-inline.js',s)"
node --check /tmp/lakenav-v059-inline.js

grep -q 'v0.59' app/src/main/assets/index.html
grep -q 'NAV_CONTINUITY_NOFIX_MAX_MS' app/src/main/assets/index.html
grep -q 'navigationContinuityWanted' app/src/main/assets/index.html
grep -q 'routeGeometryPoints' app/src/main/assets/index.html
grep -q 'keepBuffer: 8' app/src/main/assets/index.html
grep -q "arrow.style.top='78%'" app/src/main/assets/index.html
grep -q "point ' + (activeRouteIndex + 1) + ' of '" app/src/main/assets/index.html
if grep -q 'markerStride=returnTrack' app/src/main/assets/index.html; then
  echo 'Legacy hidden return-track marker stride still present' >&2
  exit 1
fi

printf 'LakeNav WI v0.59 navigation continuity, compact nav HUD, route-point, recenter, and tile-gap fixes applied.\n'
