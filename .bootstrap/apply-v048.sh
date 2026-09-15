#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v048.patch.gz.b64.part00 .bootstrap/v048.patch.gz.b64.part01 .bootstrap/v048.patch.gz.b64.part02 .bootstrap/v048.patch.gz.b64.part03 .bootstrap/v048.patch.gz.b64.part04 | base64 -d | gzip -d > /tmp/v048.patch
patch -p1 < /tmp/v048.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 48/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.48.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v048-inline.js',s)"
node --check /tmp/lakenav-v048-inline.js
grep -q 'v0.48' app/src/main/assets/index.html
grep -q 'marineBaseTiles' app/src/main/assets/index.html
grep -q 'waypointVisualKind' app/src/main/assets/index.html
grep -q 'routeCasingLine' app/src/main/assets/index.html
grep -q 'setMarineDepthState' app/src/main/assets/index.html
grep -q 'plannedRoutePath' app/src/main/assets/index.html
printf 'LakeNav WI v0.48 marine visual chart pass applied.\n'
