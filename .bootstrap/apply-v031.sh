#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.31</span></div>', s, count=1)

# Navigation camera state: Course Up waits for two real movement samples before rotating/following.
state_anchor="  let movementCourseConfidence = 0;"
if state_anchor not in s:
    raise SystemExit('movementCourseConfidence state anchor not found')
s=s.replace(state_anchor, state_anchor+"\n  let movementCourseSamples = 0;\n  let movementCourseSampleAt = 0;\n  let navCourseAcquired = false;\n  let navStableFix = null;",1)

# Count consecutive trustworthy displacement samples. Two samples are required before the chart
# is allowed to rotate so a stationary phone/compass cannot start moving the map underneath the user.
old="""    movementCourseAt=Date.now();
    movementCourseConfidence=Math.max(.35,Math.min(1,(moved/minMove)*.32 + effectiveSpeed*.16));
  }
"""
new="""    const sampleNow=Date.now();
    if (!movementCourseSampleAt || sampleNow-movementCourseSampleAt>4500) movementCourseSamples=0;
    movementCourseSamples=Math.min(8,movementCourseSamples+1);
    movementCourseSampleAt=sampleNow;
    movementCourseAt=sampleNow;
    movementCourseConfidence=Math.max(.35,Math.min(1,(moved/minMove)*.32 + effectiveSpeed*.16));
    if (orientationMode==='courseup' && navFollowMode && movementCourseSamples>=2) {
      navCourseAcquired=true;
      navStableFix=null;
    }
  }
"""
if old not in s:
    raise SystemExit('movement course completion anchor not found')
s=s.replace(old,new,1)

# Helpers for entering Course Up and for choosing the geographic coordinate that the pinned arrow
# represents. While waiting for real movement, both the map camera and accuracy circle remain tied
# to one stable GPS fix. Once movement is acquired, they switch together to the live GPS coordinate.
anchor="  function navigationPerspectiveActive() {"
helper=r'''  function resetCourseUpAcquisition() {
    navCourseAcquired=false;
    movementCourseSamples=0;
    movementCourseSampleAt=0;
    navStableFix=currentLoc ? {lat:currentLoc.lat,lon:currentLoc.lon,accuracy:currentLoc.accuracy} : null;
  }

  function navigationAnchorLocation() {
    if (orientationMode==='courseup' && navFollowMode && !navCourseAcquired) {
      if (!navStableFix && currentLoc) navStableFix={lat:currentLoc.lat,lon:currentLoc.lon,accuracy:currentLoc.accuracy};
      return navStableFix || currentLoc;
    }
    return currentLoc;
  }

'''
if anchor not in s:
    raise SystemExit('navigationPerspectiveActive anchor missing')
s=s.replace(anchor,helper+anchor,1)

# Course Up UI makes the acquisition state explicit rather than pretending compass heading is a
# valid travel direction before the device has actually moved.
old_chip="""      if (followVisual) $('chartChip').textContent='Navigation follow';
      else if (active && !navFollowMode) $('chartChip').textContent='Free pan • tap GPS to resume';
"""
new_chip="""      if (followVisual && !navCourseAcquired) $('chartChip').textContent='Course Up • waiting for movement';
      else if (followVisual) $('chartChip').textContent='Navigation follow';
      else if (active && !navFollowMode) $('chartChip').textContent='Free pan • tap GPS to resume';
"""
if old_chip not in s:
    raise SystemExit('navigation chart chip anchor not found')
s=s.replace(old_chip,new_chip,1)

# Rebuild the camera target around the SAME coordinate represented by the GPS accuracy circle.
# Before movement is acquired the view stays North Up, but the stable GPS coordinate still sits at
# the lower-center anchor. After acquisition, the center moves ahead along the measured travel course.
pattern=r"  function perspectiveCenterLatLng\(\) \{.*?\n  \}\n\n  function ensureOperationalCourseUp\(\) \{"
m=re.search(pattern,s,flags=re.S)
if not m:
    raise SystemExit('perspectiveCenterLatLng block not found')
replacement=r'''  function perspectiveCenterLatLng() {
    const loc=navigationAnchorLocation();
    if (!map || !loc || !navigationPerspectiveActive()) return loc ? [loc.lat,loc.lon] : null;
    const moving=navCourseAcquired;
    const h=moving ? activeHeading() : {degrees:0,source:'Waiting for movement'};
    if (!h || h.degrees == null) return [loc.lat,loc.lon];
    let aheadM=220;
    try {
      const wrap=$('mapWrap');
      const z=map.getZoom();
      const c=map.getCenter();
      const cp=map.project(c,z);
      const north=map.unproject(L.point(cp.x,cp.y-100),z);
      const metersPerPx=Math.max(.01,distanceMeters(c.lat,c.lng,north.lat,north.lng)/100);
      const visibleHeight=wrap ? Math.max(320,wrap.clientHeight) : Math.max(320,map.getSize().y/2);
      // With the v0.30 200% map surface, 26% of wrapper height is exactly the offset needed
      // to place the geographic GPS coordinate at 76% of the visible wrapper height.
      const aheadPx=visibleHeight*.26;
      aheadM=Math.max(35,Math.min(1500,metersPerPx*aheadPx));
    } catch(e) {}
    const end=destinationPoint(loc.lat,loc.lon,h.degrees,aheadM);
    return [end[0],end[1]];
  }

  function ensureOperationalCourseUp() {'''
s=s[:m.start()]+replacement+s[m.end():]

# Starting an automatically-triggered Course Up navigation session must also start with a fresh
# movement acquisition instead of inheriting an old course from earlier map use.
old_ensure="""    if (orientationMode !== 'courseup') {
      orientationMode='courseup';
      navFollowMode=true;
      applyMapOrientation();
      updateNavigationPerspectiveUi();
    }
"""
new_ensure="""    if (orientationMode !== 'courseup') {
      orientationMode='courseup';
      navFollowMode=true;
      resetCourseUpAcquisition();
      applyMapOrientation();
      updateNavigationPerspectiveUi();
    }
"""
if old_ensure not in s:
    raise SystemExit('ensureOperationalCourseUp block not found')
s=s.replace(old_ensure,new_ensure,1)

# Entering Course Up manually also starts from the current stable GPS fix and waits for motion.
old_toggle="""    orientationMode = orientationMode === 'courseup' ? 'northup' : 'courseup';
    if (orientationMode==='courseup' && navPerspectiveEnabled) navFollowMode=true;
"""
new_toggle="""    orientationMode = orientationMode === 'courseup' ? 'northup' : 'courseup';
    if (orientationMode==='courseup' && navPerspectiveEnabled) { navFollowMode=true; resetCourseUpAcquisition(); }
    else { navCourseAcquired=false; navStableFix=null; }
"""
if old_toggle not in s:
    raise SystemExit('v0.30 toggle start not found')
s=s.replace(old_toggle,new_toggle,1)

# Turning the follow perspective on while already in Course Up likewise begins a new acquisition.
old_set="""    if (navPerspectiveEnabled && orientationMode==='courseup') navFollowMode=true;
    updateNavigationPerspectiveUi();
"""
new_set="""    if (navPerspectiveEnabled && orientationMode==='courseup') { navFollowMode=true; resetCourseUpAcquisition(); }
    updateNavigationPerspectiveUi();
"""
if old_set not in s:
    raise SystemExit('v0.30 perspective enable block not found')
s=s.replace(old_set,new_set,1)

# GPS/Center intentionally re-locks to the live coordinate, then requires actual movement before
# allowing Course Up rotation again. This prevents Center from immediately using a stationary compass.
old_center="""        navFollowMode=true;
        updateNavigationPerspectiveUi();
        applyMapOrientation();
"""
new_center="""        navFollowMode=true;
        resetCourseUpAcquisition();
        updateNavigationPerspectiveUi();
        applyMapOrientation();
"""
if old_center not in s:
    raise SystemExit('center acquisition anchor not found')
s=s.replace(old_center,new_center,1)

# The geographic GPS marker/accuracy circle must use the exact same coordinate as the pinned arrow.
# While waiting, that coordinate is deliberately frozen to reject GPS wander. When travel is detected,
# both switch to the live GPS fix on the same update.
metrics_anchor="""    $('accuracyValue').textContent = accuracy >= 0 ? Math.round(accuracy * M_TO_FT) : '--';

    if (map) {
"""
metrics_new="""    $('accuracyValue').textContent = accuracy >= 0 ? Math.round(accuracy * M_TO_FT) : '--';

    if (orientationMode==='courseup' && navFollowMode && !navCourseAcquired && !navStableFix) {
      navStableFix={lat,lon,accuracy};
    }
    const navDisplayLoc=navigationAnchorLocation() || {lat,lon};
    const navDisplayLat=Number(navDisplayLoc.lat), navDisplayLon=Number(navDisplayLoc.lon);

    if (map) {
"""
if metrics_anchor not in s:
    raise SystemExit('location metrics/map anchor not found')
s=s.replace(metrics_anchor,metrics_new,1)

s=s.replace("positionMarker = L.marker([lat, lon], { icon: boatPositionIcon(), keyboard: false, interactive: true, zIndexOffset: 1000 })",
            "positionMarker = L.marker([navDisplayLat, navDisplayLon], { icon: boatPositionIcon(), keyboard: false, interactive: true, zIndexOffset: 1000 })",1)
s=s.replace("accuracyCircle = L.circle([lat, lon], {",
            "accuracyCircle = L.circle([navDisplayLat, navDisplayLon], {",1)
s=s.replace("        positionMarker.setLatLng([lat, lon]);\n        accuracyCircle.setLatLng([lat, lon]);",
            "        positionMarker.setLatLng([navDisplayLat, navDisplayLon]);\n        accuracyCircle.setLatLng([navDisplayLat, navDisplayLon]);",1)

# Do not let compass heading rotate the map while acquiring course. The heading card can still show
# compass information, but the navigation surface itself remains North Up until displacement is proven.
s=s.replace("    const courseUpVisual = orientationMode === 'courseup' && navFollowMode;",
            "    const courseUpVisual = orientationMode === 'courseup' && navFollowMode && navCourseAcquired;",1)

# v0.30's 200% surface already covers every rotation angle. Scaling that surface again changes the
# screen coordinate of the real GPS circle and is the main reason it separated from the pinned arrow.
# Keep the Leaflet map at scale 1 in pinned mode; auxiliary canvases can retain their old cover scale.
old_transform="""    } else {
      $('map').style.transform = visualAngle ? 'rotate(' + (-visualAngle).toFixed(1) + 'deg) scale(' + scale.toFixed(2) + ')' : 'none';
"""
new_transform="""    } else {
      const pinnedMapScale = ($('mapWrap') && $('mapWrap').classList.contains('navGpsPinned')) ? 1 : scale;
      $('map').style.transform = visualAngle ? 'rotate(' + (-visualAngle).toFixed(1) + 'deg) scale(' + pinnedMapScale.toFixed(2) + ')' : 'none';
"""
if old_transform not in s:
    raise SystemExit('map transform scale anchor not found')
s=s.replace(old_transform,new_transform,1)

# Once the second trustworthy movement sample arrives, immediately update marker, camera and rotation
# together instead of waiting for separate UI/GPS timers to catch up.
old_tail="""    updateNavigationPerspectiveUi();
    updateHeadingVisuals();
    maybeFollowPrimaryNavigation();
"""
new_tail="""    if (navCourseAcquired) {
      navStableFix=null;
      if (positionMarker) positionMarker.setLatLng([lat,lon]);
      if (accuracyCircle) accuracyCircle.setLatLng([lat,lon]);
    }
    updateNavigationPerspectiveUi();
    updateHeadingVisuals();
    maybeFollowPrimaryNavigation();
"""
if old_tail not in s:
    raise SystemExit('v0.30 location tail not found')
s=s.replace(old_tail,new_tail,1)

# Make the fixed halo read as the same GPS location circle while waiting/acquired.
css='''
/* v0.31 GPS-coordinate lock */
#mapWrap.navGpsPinned #navGpsAnchor .navGpsHalo {
  border:2px solid rgba(8,124,184,.58);
  background:rgba(8,124,184,.09);
  box-shadow:0 2px 10px rgba(0,54,86,.18),0 0 0 5px rgba(255,255,255,.32);
}
'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.31 features' not in r:
    insert='''\n## Version 0.31 features\n\n### GPS anchor lock + movement acquisition\n- Course Up no longer rotates from phone compass input while stationary. It starts North Up and waits for two trustworthy displacement samples before the navigation surface is allowed to rotate.\n- The pinned navigation arrow and the geographic GPS accuracy circle now use one shared navigation coordinate. Before movement is confirmed that coordinate is held stable to reject GPS wander; after movement is confirmed both switch together to the live GPS fix.\n- Removes extra Leaflet-map scaling in the pinned Course Up camera. The existing 200% chart surface already supplies rotation coverage, and eliminating the additional scale keeps the actual GPS coordinate aligned with the fixed lower-center arrow.\n- Entering Course Up, enabling its follow view, or tapping GPS/Center starts a fresh movement acquisition instead of immediately inheriting stationary compass heading.\n- Once real movement is acquired, the movement-first heading from v0.29 takes over and the map follows/rotates beneath the fixed arrow.\n'''
    pos=r.find('\n## Version 0.30 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)

p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 31/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.31.0'/" app/build.gradle
grep -q 'v0.31' app/src/main/assets/index.html
grep -q 'navCourseAcquired' app/src/main/assets/index.html
grep -q 'Course Up • waiting for movement' app/src/main/assets/index.html
grep -q 'pinnedMapScale' app/src/main/assets/index.html
grep -q 'Version 0.31 features' README.md
printf 'LakeNav WI v0.31 GPS anchor lock and movement gate applied.\n'
