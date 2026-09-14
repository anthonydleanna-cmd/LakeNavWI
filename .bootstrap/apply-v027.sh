#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.27</span></div>', s, count=1)

# Course-up perspective is now an operational navigation state rather than a general browsing state.
old="""  function navigationPerspectiveActive() {
    return mapMode === '2d' && navPerspectiveEnabled && orientationMode === 'courseup' && !routeDrawMode;
  }
"""
new="""  function operationalNavigationActive() {
    const directNav = (typeof navWp !== 'undefined' && !!navWp);
    const routeNav = (typeof activeRouteId !== 'undefined' && !!activeRouteId);
    const tracking = (typeof recording !== 'undefined' && !!recording);
    return directNav || routeNav || tracking;
  }

  function navigationPerspectiveActive() {
    return mapMode === '2d' && navPerspectiveEnabled && orientationMode === 'courseup' && operationalNavigationActive() && !routeDrawMode;
  }
"""
if old not in s:
    raise SystemExit('navigationPerspectiveActive block not found')
s=s.replace(old,new,1)

# Make look-ahead feel closer to turn-by-turn navigation: boat low on screen, more map ahead,
# and progressively more look-ahead while moving when a speed value is available.
old="""  function perspectiveCenterLatLng() {
    if (!map || !currentLoc || !navigationPerspectiveActive()) return currentLoc ? [currentLoc.lat,currentLoc.lon] : null;
    const h=activeHeading();
    if (!h) return [currentLoc.lat,currentLoc.lon];
    let aheadM=260;
    try {
      const b=map.getBounds();
      const c=map.getCenter();
      const visibleM=distanceMeters(b.getSouth(),c.lng,b.getNorth(),c.lng);
      aheadM=Math.max(110,Math.min(1250,visibleM*0.19));
    } catch(e) {}
    const end=destinationPoint(currentLoc.lat,currentLoc.lon,h.degrees,aheadM);
    return [end[0],end[1]];
  }
"""
new="""  function currentNavigationSpeedMps() {
    try {
      if (currentLoc && Number.isFinite(Number(currentLoc.speed))) return Math.max(0,Number(currentLoc.speed));
      if (typeof lastSpeedMps !== 'undefined' && Number.isFinite(Number(lastSpeedMps))) return Math.max(0,Number(lastSpeedMps));
      if ($('speedValue')) {
        const mph=Number(String($('speedValue').textContent||'').replace(/[^0-9.\-]/g,''));
        if (Number.isFinite(mph)) return Math.max(0,mph/2.23694);
      }
      if ($('spd')) {
        const mph=Number(String($('spd').textContent||'').replace(/[^0-9.\-]/g,''));
        if (Number.isFinite(mph)) return Math.max(0,mph/2.23694);
      }
    } catch(e) {}
    return 0;
  }

  function perspectiveCenterLatLng() {
    if (!map || !currentLoc || !navigationPerspectiveActive()) return currentLoc ? [currentLoc.lat,currentLoc.lon] : null;
    const h=activeHeading();
    if (!h) return [currentLoc.lat,currentLoc.lon];
    let aheadM=300;
    try {
      const b=map.getBounds();
      const c=map.getCenter();
      const visibleM=distanceMeters(b.getSouth(),c.lng,b.getNorth(),c.lng);
      const speedMps=currentNavigationSpeedMps();
      const speedLookAhead=Math.min(900,speedMps*34);
      aheadM=Math.max(140,Math.min(1500,visibleM*0.235 + speedLookAhead));
    } catch(e) {}
    const end=destinationPoint(currentLoc.lat,currentLoc.lon,h.degrees,aheadM);
    return [end[0],end[1]];
  }
"""
if old not in s:
    raise SystemExit('perspectiveCenterLatLng block not found')
s=s.replace(old,new,1)

# Active tracking/navigation should automatically adopt Course Up, but ordinary map browsing remains North Up/free.
anchor="""  function centerPrimaryNavigationView(animate) {
"""
helper="""  function ensureOperationalCourseUp() {
    if (!operationalNavigationActive() || routeDrawMode || mapMode!=='2d') return;
    if (orientationMode !== 'courseup') {
      orientationMode='courseup';
      navFollowMode=true;
      applyMapOrientation();
      updateNavigationPerspectiveUi();
    }
  }

"""
if anchor not in s:
    raise SystemExit('centerPrimaryNavigationView anchor not found')
s=s.replace(anchor,helper+anchor,1)

old="""  function maybeFollowPrimaryNavigation() {
    if (!navFollowMode || !navigationPerspectiveActive() || !map || !currentLoc || routeDrawMode) return;
    const now=performance.now();
"""
new="""  function maybeFollowPrimaryNavigation() {
    ensureOperationalCourseUp();
    if (!navFollowMode || !navigationPerspectiveActive() || !map || !currentLoc || routeDrawMode) return;
    const now=performance.now();
"""
if old not in s:
    raise SystemExit('maybeFollowPrimaryNavigation block not found')
s=s.replace(old,new,1)

# The perspective option describes when it will be used now.
s=s.replace('Navigation perspective<small>Forward-looking 2D view in Course Up</small>', 'Navigation follow view<small>Forward-looking Course Up while tracking or navigating</small>',1)
s=s.replace('North Up stays a flat planning chart. Course Up shifts the chart ahead of the boat and adds subtle navigation shading without using the 3D terrain engine.', 'Explore normally in the flat planning chart. Starting a track, waypoint, or route switches into the forward-looking Course Up follow view; dragging the map temporarily releases follow.',1)

# Give the active follow view a more obvious navigation-camera composition and persistent resume cue.
css='''
/* v0.27 active navigation follow presentation */
#mapWrap.navPerspective2d #navPerspectiveShade {
  background:
    linear-gradient(to bottom, rgba(3,31,46,.23) 0%, rgba(7,48,65,.08) 19%, rgba(255,255,255,0) 43%, rgba(255,255,255,0) 78%, rgba(4,28,40,.10) 100%),
    radial-gradient(ellipse at 50% 118%, rgba(0,0,0,.12) 0%, rgba(0,0,0,0) 51%);
}
#mapWrap.navPerspective2d #chartChip { font-weight:800; letter-spacing:.02em; }
#mapWrap.navPerspective2d #chartChip::before { content:'FOLLOW • '; color:#69e9ff; }
'''
s=s.replace('\n/* v0.24 NOAA ENC-derived navigation-aid symbols */', css+'\n/* v0.24 NOAA ENC-derived navigation-aid symbols */',1)

# Starting either direct waypoint navigation or route navigation should enter follow mode immediately.
# Existing v0.23 injected navFollowMode=true into both start paths; extend those anchors with Course Up activation.
s=s.replace("    navFollowMode=true;\n    if (map) map.fitBounds(currentLoc ?", "    navFollowMode=true;\n    ensureOperationalCourseUp();\n    if (map) map.fitBounds(currentLoc ?",1)
s=s.replace("    navFollowMode=true;\n    if (map) map.fitBounds(L.latLngBounds", "    navFollowMode=true;\n    ensureOperationalCourseUp();\n    if (map) map.fitBounds(L.latLngBounds",1)

# When a user stops all operational navigation, leave the chart usable without forcing the perspective state.
# UI refresh is enough; orientation can remain Course Up until the user changes it.
s=s.replace("$('nav').classList.remove('on');", "$('nav').classList.remove('on'); updateNavigationPerspectiveUi();",1)

p.write_text(s)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.27 features' not in r:
    insert='''\n## Version 0.27 features\n\n### Active navigation follow view\n- Changes Course Up perspective from a general browsing presentation into the dedicated movement/navigation camera. The normal map remains the planning/exploration view until a track, waypoint navigation, or saved route is active.\n- Starting active navigation automatically moves LakeNav into Course Up follow mode and keeps the vessel lower in the visual field so substantially more of the map ahead remains visible.\n- Look-ahead distance now grows with the visible map scale and, when available, current GPS speed. This produces a more turn-by-turn navigation feel instead of simply centering the boat.\n- Manual dragging still releases auto-follow so another area can be inspected; the existing GPS/center control resumes navigation follow.\n- Route drawing remains a flat planning operation and does not trigger the navigation camera.\n\n### Design direction\n- The goal of this pass is the same visual behavior as modern road navigation apps: stable heading-up motion, the vessel below center, and the useful map area biased toward what is ahead.\n- This remains a marine situational-awareness aid rather than an automotive routing clone; route geometry, NOAA aids, depth information, radar, wind, waves, and existing LakeNav overlays remain geographically aligned.\n'''
    pos=r.find('\n## Version 0.26 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 27/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.27.0'/" app/build.gradle
grep -q 'v0.27' app/src/main/assets/index.html
grep -q 'operationalNavigationActive' app/src/main/assets/index.html
grep -q 'Active navigation follow view' README.md
printf 'LakeNav WI v0.27 active navigation follow mode applied.\n'
