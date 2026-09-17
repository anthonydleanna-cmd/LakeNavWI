#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

# v0.79-v0.82 water-rendering experiments are intentionally removed from the active
# materialization chain. At this point the app is the known-good v0.78 source.
python3 - <<'PY'
from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
old='<div id="brand">LakeNav WI <span class="versionPill">v0.78</span></div>'
new='<div id="brand">LakeNav WI <span class="versionPill">v0.83</span></div>'
if old not in s:
    raise SystemExit('v0.83 expected stable v0.78 source baseline')
s=s.replace(old,new,1)
p.write_text(s)
PY

sed -i "s/versionCode [0-9][0-9]*/versionCode 83/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.83.0'/" app/build.gradle

node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v083-inline.js',s)"
node --check /tmp/lakenav-v083-inline.js

grep -q 'v0.83' app/src/main/assets/index.html
grep -q "baseLayer = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png'" app/src/main/assets/index.html
! grep -q 'createMarineBaseLayer' app/src/main/assets/index.html
! grep -q 'createWaterEmphasisLayer' app/src/main/assets/index.html
! grep -q 'waterEmphasisToggle' app/src/main/assets/index.html
! grep -q 'STORAGE_WATER_EMPHASIS' app/src/main/assets/index.html

printf 'LakeNav WI v0.83 restored stable v0.78 map/navigation baseline.\n'
