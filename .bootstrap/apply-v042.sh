#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.42</span></div>', s, count=1)

# Free pan in Course Up must use normal screen-space controls. Keeping the rotated DOM surface
# while Leaflet handles drag deltas causes finger motion to feel rotated/inverted. Enter free pan
# before the drag begins and hold the chart upright without changing the user's map center.
old_drag="""    map.on('dragstart', () => {
      navFreePanHeading=Number.isFinite(Number(mapRotationDeg)) ? Number(mapRotationDeg) : 0;
      navFollowMode=false;
      updateNavigationPerspectiveUi();
      applyMapOrientationWithHeading(navFreePanHeading);
      if($('chartChip')) $('chartChip').textContent='Free pan • tap GPS to resume';
    });"""
new_drag="""    const enterScreenSpaceFreePan = (ev) => {
      if (orientationMode!=='courseup' || !navFollowMode || routeDrawMode || mapMode!=='2d') return;
      const t=ev && ev.target;
      if (t && t.closest && t.closest('.leaflet-control,.leaflet-popup,button,input,select,textarea,a')) return;
      navFreePanHeading=0;
      navFollowMode=false;
      mapRotationDeg=0;
      if ($('mapWrap')) $('mapWrap').classList.add('freePanUpright');
      updateNavigationPerspectiveUi();
      applyMapOrientationWithHeading(0);
      if($('chartChip')) $('chartChip').textContent='Free pan • North Up • tap GPS to resume';
    };
    const mapContainer=map.getContainer ? map.getContainer() : null;
    if (mapContainer) mapContainer.addEventListener('pointerdown',enterScreenSpaceFreePan,{capture:true,passive:true});
    map.on('dragstart', () => {
      if (orientationMode==='courseup' && navFollowMode) enterScreenSpaceFreePan(null);
      if (orientationMode==='courseup' && navFreePanHeading!=null) {
        navFreePanHeading=0;
        mapRotationDeg=0;
        if ($('mapWrap')) $('mapWrap').classList.add('freePanUpright');
        applyMapOrientationWithHeading(0);
        if($('chartChip')) $('chartChip').textContent='Free pan • North Up • tap GPS to resume';
      }
    });"""
if old_drag not in s:
    raise SystemExit('v0.34 dragstart block not found')
s=s.replace(old_drag,new_drag,1)

# Resuming follow removes the temporary free-pan presentation before Course Up is reacquired.
reset_anchor="""    navFilteredFix=null;
    navFilterHeading=null;
    navFreePanHeading=null;
  }
"""
reset_new="""    navFilteredFix=null;
    navFilterHeading=null;
    navFreePanHeading=null;
    if ($('mapWrap')) $('mapWrap').classList.remove('freePanUpright');
  }
"""
if reset_anchor not in s:
    raise SystemExit('resetCourseUpAcquisition tail not found')
s=s.replace(reset_anchor,reset_new,1)

# Explicitly leaving Course Up should also clear the temporary upright free-pan state.
leave_old="    else { navCourseAcquired=false; navStableFix=null; navFilteredFix=null; navFilterHeading=null; navFreePanHeading=null; }"
leave_new="    else { navCourseAcquired=false; navStableFix=null; navFilteredFix=null; navFilterHeading=null; navFreePanHeading=null; if($('mapWrap')) $('mapWrap').classList.remove('freePanUpright'); }"
if leave_old in s:
    s=s.replace(leave_old,leave_new,1)

# Keep free pan upright even though orientationMode intentionally remains 'courseup' so Center/GPS
# can return to the active navigation camera without changing the user's selected mode.
old_free="""    const freePanHeading = !navFollowMode && navFreePanHeading != null ? navFreePanHeading : null;
    const courseUpVisual = orientationMode === 'courseup' && ((navFollowMode && navCourseAcquired) || freePanHeading != null);"""
new_free="""    const freePanHeading = !navFollowMode && navFreePanHeading != null ? 0 : null;
    const courseUpVisual = orientationMode === 'courseup' && ((navFollowMode && navCourseAcquired) || freePanHeading != null);"""
if old_free not in s:
    raise SystemExit('freePanHeading orientation block not found')
s=s.replace(old_free,new_free,1)

css='''
/* v0.42 screen-space free pan */
#mapWrap.freePanUpright #map {
  transition: transform 120ms ease-out !important;
}
#mapWrap.freePanUpright #chartChip::before { content:'' !important; }
'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.42 features' not in r:
    insert='''\n## Version 0.42 features\n\n### Screen-space free pan\n- Course Up free pan now releases the navigation camera into an upright North Up browsing surface before Leaflet begins handling the drag. Finger movement therefore matches screen movement regardless of the vessel heading.\n- The map center is preserved when free pan begins; the change is orientation-only, so the user continues exploring from the same area rather than jumping to another location.\n- Tracking can remain active while free panning. GPS/track collection continues in the background, but automatic follow stays suspended until Center/GPS is tapped.\n- Center/GPS removes the temporary free-pan presentation and resumes the existing Course Up movement-acquisition/follow behavior without changing the GPS filtering introduced in v0.41.\n'''
    pos=r.find('\n## Version 0.41 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)

p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 42/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.42.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v042-inline.js',s)"
node --check /tmp/lakenav-v042-inline.js
grep -q 'v0.42' app/src/main/assets/index.html
grep -q 'enterScreenSpaceFreePan' app/src/main/assets/index.html
grep -q 'freePanUpright' app/src/main/assets/index.html
grep -q 'Version 0.42 features' README.md
printf 'LakeNav WI v0.42 screen-space free pan applied.\n'
