#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
s=s.replace('/* v0.56 dark-mode default, pre-paint flicker guard, and contrast diagnostics */','/* v0.56 dark-mode default, pre-paint flicker guard, and contrast diagnostics */\n/* v0.57 navigation-aid label cleanup: symbols stay visible; names/details appear only when selected */')
s=s.replace('<div id="brand">LakeNav WI <span class="versionPill">v0.56</span></div>','<div id="brand">LakeNav WI <span class="versionPill">v0.57</span></div>')
old="""      const showLabel=zoom>=14.5 && !!name;\n      const shortName=name.length>22?name.slice(0,21)+'…':name;\n      const classes=['encAidWrap',kind,meta.shapeClass,meta.lateral].filter(Boolean).join(' ');\n      const html='<div class="'+classes+'" style="--aid-scale:'+scale.toFixed(2)+'"><div class="encAidShape" style="background:'+noaaAidColour(p)+'"></div>'+(showLabel?'<div class="encAidLabel">'+encText(shortName)+'</div>':'')+'</div>';\n      const size=zoom>=16?34:(zoom>=14?31:(zoom>=12?28:24));\n      const icon=L.divIcon({className:'encAidIcon',html,iconSize:[size,size+(showLabel?18:0)],iconAnchor:[size/2,size/2]});\n"""
new="""      // Keep navigation-aid names off the chart while underway.\n      // Selecting the symbol still opens the full NOAA ENC details popup below.\n      const classes=['encAidWrap',kind,meta.shapeClass,meta.lateral].filter(Boolean).join(' ');\n      const html='<div class="'+classes+'" style="--aid-scale:'+scale.toFixed(2)+'"><div class="encAidShape" style="background:'+noaaAidColour(p)+'"></div></div>';\n      const size=zoom>=16?34:(zoom>=14?31:(zoom>=12?28:24));\n      const icon=L.divIcon({className:'encAidIcon',html,iconSize:[size,size],iconAnchor:[size/2,size/2]});\n"""
if old not in s:
    raise SystemExit('v0.57 nav-aid target block not found')
s=s.replace(old,new,1)
p.write_text(s)
PY
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
