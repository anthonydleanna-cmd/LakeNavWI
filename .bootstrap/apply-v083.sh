#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

# v0.83 intentionally rolls the map renderer back to the exact stable v0.78 map behavior.
# v0.79-v0.82 were water-color experiments only. Reverse them in order so navigation,
# track history, lake discovery/library, launch and fishing features from v0.78 remain intact.

python3 - <<'PY'
from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()

# Restore the exact v0.81 createMarineBaseLayer function first, because v0.82 modified
# only that function. This lets the checked-in v0.81 patch reverse cleanly afterward.
patch=Path('.bootstrap/v081.patch').read_text().splitlines()
start=None
end=None
for i,line in enumerate(patch):
    if line.startswith('+  function createMarineBaseLayer() {'):
        start=i
        break
if start is None:
    raise SystemExit('v0.83 could not locate v0.81 createMarineBaseLayer in patch')
# Collect added lines belonging to the function until the context line for toggleNoaa.
lines=[]
for line in patch[start:]:
    if line.startswith('   function toggleNoaa(on) {') or line.startswith('  function toggleNoaa(on) {'):
        break
    if line.startswith('+') and not line.startswith('+++'):
        lines.append(line[1:])
# Trim any blank added lines after the function, but keep one newline in replacement.
while lines and lines[-1]=='':
    lines.pop()
old_start=s.find('  function createMarineBaseLayer() {')
old_end=s.find('\n  function toggleNoaa(on) {', old_start)
if old_start<0 or old_end<0:
    raise SystemExit('v0.83 could not locate current createMarineBaseLayer')
s=s[:old_start]+'\n'.join(lines)+'\n'+s[old_end:]
# Return the brand to v0.81 so the v0.81 reverse patch matches exactly.
s=s.replace('<span class="versionPill">v0.82</span>','<span class="versionPill">v0.81</span>',1)
p.write_text(s)
PY

patch --batch --fuzz=0 -R -p1 < .bootstrap/v081.patch
patch --batch --fuzz=0 -R -p1 < .bootstrap/v080.patch
patch --batch --fuzz=0 -R -p1 < .bootstrap/v079.patch

python3 - <<'PY'
from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
old='<div id="brand">LakeNav WI <span class="versionPill">v0.78</span></div>'
new='<div id="brand">LakeNav WI <span class="versionPill">v0.83</span></div>'
if old not in s:
    raise SystemExit('v0.83 rollback did not return to v0.78 brand baseline')
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
