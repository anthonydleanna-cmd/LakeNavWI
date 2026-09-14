#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.34</span></div>', s, count=1)

# Freeze the exact Course Up rotation when follow is released so free pan starts from the same frame
# instead of snapping North Up / resizing the map before the user's drag can begin.
state_anchor="  let navArrowSyncUntil = 0;"
if state_anchor not in s:
    raise SystemExit('v0.33 nav arrow state anchor not found')
s=s.replace(state_anchor,state_anchor+"\n  let navFreePanHeading = null;",1)

# A fresh follow/recenter session clears the free-pan rotation hold.
old_reset="""  function resetCourseUpAcquisition() {
    navCourseAcquired=false;
    movementCourseSamples=0;
    movementCourseSampleAt=0;
    navStableFix=currentLoc ? {lat:currentLoc.lat,lon:currentLoc.lon,accuracy:currentLoc.accuracy} : null;
    navFilteredFix=null;
    navFilterHeading=null;
  }
"""
new_reset="""  function resetCourseUpAcquisition() {
    navCourseAcquired=false;
    movementCourseSamples=0;
    movementCourseSampleAt=0;
    navStableFix=currentLoc ? {lat:currentLoc.lat,lon:currentLoc.lon,accuracy:currentLoc.accuracy} : null;
    navFilteredFix=null;
    navFilterHeading=null;
    navFreePanHeading=null;
  }
"""
if old_reset not in s:
    raise SystemExit('v0.32 resetCourseUpAcquisition block not found')
s=s.replace(old_reset,new_reset,1)

# Continue using the stabilized navigation coordinate while the user is freely panning. This keeps
# the geographic marker and live track endpoint on the same filtered point instead of reverting to a
# raw GPS fix as soon as follow mode is released.
s=s.replace("    if (!rawLoc || orientationMode!=='courseup' || !navFollowMode || !navCourseAcquired) return;",
            "    if (!rawLoc || orientationMode!=='courseup' || (!navFollowMode && navFreePanHeading==null) || !navCourseAcquired) return;",1)
s=s.replace("    if (orientationMode==='courseup' && navFollowMode) {\n      if (!navCourseAcquired) {",
            "    if (orientationMode==='courseup' && (navFollowMode || navFreePanHeading!=null)) {\n      if (!navCourseAcquired) {",1)

# Keep the Course Up chart surface mounted while in free pan. Only the screen-pinned overlay is
# released. Because the 200% Leaflet surface and its rotation remain unchanged, there is no layout
# jump at drag start; the geographic Leaflet marker simply takes over at the exact same pixel.
old_head="""    const active=navigationPerspectiveActive();
    const followVisual=active && navFollowMode;
    const pinned=followVisual && !!currentLoc;
"""
new_head="""    const active=navigationPerspectiveActive();
    const courseSurface=active;
    const followVisual=active && navFollowMode;
    const pinned=followVisual && !!currentLoc;
"""
if old_head not in s:
    raise SystemExit('navigation perspective head not found')
s=s.replace(old_head,new_head,1)
s=s.replace("      $('mapWrap').classList.toggle('courseUp2d', followVisual);\n      $('mapWrap').classList.toggle('navPerspective2d', followVisual);",
            "      $('mapWrap').classList.toggle('courseUp2d', courseSurface);\n      $('mapWrap').classList.toggle('navPerspective2d', courseSurface);",1)
s=s.replace("    if (followVisual !== navPerspectiveLayoutActive) {\n      navPerspectiveLayoutActive=followVisual;",
            "    if (courseSurface !== navPerspectiveLayoutActive) {\n      navPerspectiveLayoutActive=courseSurface;",1)

# Preserve the exact rendered map angle in free pan. GPS/compass updates can continue updating their
# data, but the chart does not rotate under the user's finger until Center/GPS resumes follow.
old_visual="    const courseUpVisual = orientationMode === 'courseup' && navFollowMode && navCourseAcquired;"
new_visual="""    const freePanHeading = !navFollowMode && navFreePanHeading != null ? navFreePanHeading : null;
    const courseUpVisual = orientationMode === 'courseup' && ((navFollowMode && navCourseAcquired) || freePanHeading != null);"""
if old_visual not in s:
    raise SystemExit('courseUpVisual anchor not found')
s=s.replace(old_visual,new_visual,1)
old_target="    const target = courseUpVisual && displayHeading != null ? displayHeading : 0;"
new_target="""    const visualHeading = freePanHeading != null ? freePanHeading : displayHeading;
    const target = courseUpVisual && visualHeading != null ? visualHeading : 0;"""
if old_target not in s:
    raise SystemExit('orientation target anchor not found')
s=s.replace(old_target,new_target,1)

# Release follow without re-centering, resizing or rotating the map first. The v0.33 arrow has already
# been pixel-locked to the Leaflet GPS circle, so hiding the fixed overlay reveals the geographic
# marker directly beneath it and the drag continues from the exact same visual frame.
old_drag="    map.on('dragstart', () => { navFollowMode=false; updateNavigationPerspectiveUi(); applyMapOrientationWithHeading(null); if($('chartChip')) $('chartChip').textContent='Free pan • tap GPS to resume'; });"
new_drag="""    map.on('dragstart', () => {
      navFreePanHeading=Number.isFinite(Number(mapRotationDeg)) ? Number(mapRotationDeg) : 0;
      navFollowMode=false;
      updateNavigationPerspectiveUi();
      applyMapOrientationWithHeading(navFreePanHeading);
      if($('chartChip')) $('chartChip').textContent='Free pan • tap GPS to resume';
    });"""
if old_drag not in s:
    raise SystemExit('v0.33 dragstart handler not found')
s=s.replace(old_drag,new_drag,1)

# The breadcrumb/live GPS line should terminate at the same filtered coordinate represented by the
# arrow and GPS circle. Stored track history remains untouched; only the current rendered endpoint is
# replaced so exported/raw history is not silently rewritten.
anchor="  function navigationAnchorLocation() {"
helper=r'''  function syncNavigationTrackEndpoint() {
    if (!recording || !trackLine || !Array.isArray(trackPoints) || !currentLoc) return;
    const loc=navigationAnchorLocation() || currentLoc;
    if (!loc || !Number.isFinite(Number(loc.lat)) || !Number.isFinite(Number(loc.lon))) return;
    const pts=trackPoints.map(pt=>[Number(pt.lat),Number(pt.lon)]).filter(pt=>Number.isFinite(pt[0])&&Number.isFinite(pt[1]));
    if (pts.length) pts[pts.length-1]=[Number(loc.lat),Number(loc.lon)];
    else pts.push([Number(loc.lat),Number(loc.lon)]);
    try { trackLine.setLatLngs(pts); } catch(e) {}
  }

'''
if anchor not in s:
    raise SystemExit('navigationAnchorLocation anchor missing for track helper')
s=s.replace(anchor,helper+anchor,1)

# Sync after the marker/accuracy circle are placed, before the camera/UI update for this GPS fix.
old_tail="""    if (navCourseAcquired) {
      const filtered=navigationAnchorLocation() || currentLoc;
      if (filtered) {
        if (positionMarker) positionMarker.setLatLng([filtered.lat,filtered.lon]);
        if (accuracyCircle) accuracyCircle.setLatLng([filtered.lat,filtered.lon]);
        runNavigationArrowSyncBurst(820);
      }
    } else {
      runNavigationArrowSyncBurst(420);
    }
    updateNavigationPerspectiveUi();
"""
new_tail="""    if (navCourseAcquired) {
      const filtered=navigationAnchorLocation() || currentLoc;
      if (filtered) {
        if (positionMarker) positionMarker.setLatLng([filtered.lat,filtered.lon]);
        if (accuracyCircle) accuracyCircle.setLatLng([filtered.lat,filtered.lon]);
        runNavigationArrowSyncBurst(820);
      }
    } else {
      runNavigationArrowSyncBurst(420);
    }
    syncNavigationTrackEndpoint();
    updateNavigationPerspectiveUi();
"""
if old_tail not in s:
    raise SystemExit('v0.33 GPS marker tail not found')
s=s.replace(old_tail,new_tail,1)

# Fully clear held free-pan state when Course Up itself is turned off.
s=s.replace("    else { navCourseAcquired=false; navStableFix=null; navFilteredFix=null; navFilterHeading=null; }",
            "    else { navCourseAcquired=false; navStableFix=null; navFilteredFix=null; navFilterHeading=null; navFreePanHeading=null; }",1)

css='''
/* v0.34 seamless Course Up -> free pan handoff */
#mapWrap.courseUp2d:not(.navGpsPinned) #map .boatMarker { opacity:1 !important; }
'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.34 features' not in r:
    insert='''\n## Version 0.34 features\n\n### Seamless free pan + common GPS/track anchor\n- Keeps the arrow tip, GPS circle/marker, and live breadcrumb endpoint on the same stabilized navigation coordinate. The rendered track line now ends exactly at the current GPS/arrow anchor instead of ending at a separate raw GPS fix.\n- Keeps the Course Up navigation anchor near the existing lower-screen position (about 76% of map height), preserving the forward-looking area ahead of the vessel.\n- Reworks the Course Up-to-free-pan handoff so a finger drag no longer tears down the oversized chart surface, recenters the map, or snaps the map North Up first. The view is released from the exact frame already on screen.\n- Free pan freezes the current map rotation while the user explores. GPS data can continue updating, but the chart does not rotate beneath the user's finger.\n- The screen-fixed follow arrow hands off to the geographic Leaflet GPS marker at the same pixel when free pan begins; Center/GPS clears the free-pan hold and resumes the normal movement-acquisition/follow camera.\n- Stored track history is not rewritten by the display correction; only the live rendered endpoint is aligned to the stabilized GPS anchor.\n'''
    pos=r.find('\n## Version 0.33 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)

p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 34/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.34.0'/" app/build.gradle
grep -q 'v0.34' app/src/main/assets/index.html
grep -q 'navFreePanHeading' app/src/main/assets/index.html
grep -q 'syncNavigationTrackEndpoint' app/src/main/assets/index.html
grep -q 'Version 0.34 features' README.md
printf 'LakeNav WI v0.34 seamless free pan and common GPS/track anchor applied.\n'
