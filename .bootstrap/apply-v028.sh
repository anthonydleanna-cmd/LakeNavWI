#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.28</span></div>', s, count=1)

# Course Up needs its overscan and upright zoom controls whether or not Track/navigation is active.
old="""  function updateNavigationPerspectiveUi() {
    const active=navigationPerspectiveActive();
    if ($('quickPerspectiveToggle')) $('quickPerspectiveToggle').checked=navPerspectiveEnabled;
    if ($('mapWrap')) $('mapWrap').classList.toggle('navPerspective2d', active);
"""
new="""  function updateNavigationPerspectiveUi() {
    const active=navigationPerspectiveActive();
    const courseUp2d=(mapMode==='2d' && orientationMode==='courseup' && !routeDrawMode);
    if ($('quickPerspectiveToggle')) $('quickPerspectiveToggle').checked=navPerspectiveEnabled;
    if ($('mapWrap')) {
      $('mapWrap').classList.toggle('courseUp2d', courseUp2d);
      $('mapWrap').classList.toggle('navPerspective2d', active);
    }
"""
if old not in s:
    raise SystemExit('updateNavigationPerspectiveUi anchor not found')
s=s.replace(old,new,1)

# Reuse the fixed, screen-aligned zoom control any time the 2D chart rotates.
s=s.replace('#mapWrap.navPerspective2d #map { inset:-30%; }', '#mapWrap.courseUp2d #map { inset:-34%; }',1)
s=s.replace('#mapWrap.navPerspective2d .leaflet-control-zoom { display:none !important; }', '#mapWrap.courseUp2d .leaflet-control-zoom { display:none !important; }',1)
s=s.replace('#mapWrap.navPerspective2d #navZoomControl { display:flex; flex-direction:column; }', '#mapWrap.courseUp2d #navZoomControl { display:flex; flex-direction:column; }',1)

# Dynamic cover scaling must protect the rotating chart even outside active Track mode.
s=s.replace("    if (visualAngle && navigationPerspectiveActive() && $('mapWrap')) {", "    if (visualAngle && mapMode==='2d' && $('mapWrap')) {",1)
s=s.replace('      const overscan=1.60;', '      const overscan=1.68;',1)
s=s.replace('      scale=Math.min(1.48,Math.max(1.02,scale));', '      scale=Math.min(1.62,Math.max(1.04,scale));',1)

# Stronger active-navigation composition. This is deliberately limited to Track/Navigate so planning stays flat.
css='''
/* v0.28 Course Up / active navigation camera corrections */
#mapWrap.courseUp2d { overflow:hidden; }
#mapWrap.courseUp2d #map { transform-origin:50% 68%; }
#mapWrap.navPerspective2d #map {
  transform-origin:50% 72%;
  filter:saturate(1.04) contrast(1.025);
}
#mapWrap.navPerspective2d::after {
  content:''; position:absolute; inset:0; z-index:641; pointer-events:none;
  background:linear-gradient(to bottom,rgba(5,28,43,.16) 0%,rgba(5,28,43,.06) 18%,rgba(255,255,255,0) 42%,rgba(255,255,255,0) 82%,rgba(1,18,29,.10) 100%);
}
#mapWrap.navPerspective2d #navZoomControl { top:46%; }
'''
s=s.replace('\n/* v0.27 active navigation follow presentation */', css+'\n/* v0.27 active navigation follow presentation */',1)

# Increase the forward camera offset so the vessel sits lower and more of the route ahead is visible.
s=s.replace('      aheadM=Math.max(140,Math.min(1500,visibleM*0.235 + speedLookAhead));', '      aheadM=Math.max(180,Math.min(1800,visibleM*0.30 + speedLookAhead));',1)
s=s.replace('      const speedLookAhead=Math.min(900,speedMps*34);', '      const speedLookAhead=Math.min(1050,speedMps*42);',1)

# Make the active follow cadence smoother without making the compass overly twitchy.
s=s.replace('    if (now-lastNavFollowAt < 700) return;', '    if (now-lastNavFollowAt < 420) return;',1)
s=s.replace("    if (target) map.panTo(target,{animate:false,noMoveStart:true});", "    if (target) map.panTo(target,{animate:false,noMoveStart:true});",1)

# The active navigation chip should clearly distinguish this from ordinary Course Up browsing.
s=s.replace("if (active) $('chartChip').textContent='2D navigation view';", "if (active) $('chartChip').textContent='Navigation follow';",1)

p.write_text(s)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.28 features' not in r:
    insert='''\n## Version 0.28 features\n\n### Course Up camera fixes\n- Fixes exposed/dead map space when Course Up is selected without Track enabled. Rotating Course Up now always gets oversized-map coverage and stronger dynamic cover scaling.\n- Keeps zoom controls screen-aligned and upright in every Course Up state instead of letting Leaflet zoom controls rotate diagonally with the chart.\n- Active Track/Navigate mode gets more forward look-ahead, a lower vessel composition, stronger navigation shading, and a faster follow cadence to move closer to the feel of modern turn-by-turn navigation.\n- Planning/exploration remains flat; the stronger navigation camera treatment is reserved for active tracking or navigation.\n- Existing NOAA depth, aids, radar, wind, waves, waypoints, routes, and offline behavior remain on the same geographic map engine in this pass so overlay alignment is preserved.\n'''
    pos=r.find('\n## Version 0.27 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 28/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.28.0'/" app/build.gradle
grep -q 'v0.28' app/src/main/assets/index.html
grep -q 'courseUp2d' app/src/main/assets/index.html
grep -q 'Course Up camera fixes' README.md
printf 'LakeNav WI v0.28 Course Up camera fixes applied.\n'
