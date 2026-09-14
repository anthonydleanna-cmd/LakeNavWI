#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.30</span></div>', s, count=1)

# Course Up itself is the GPS-follow navigation camera. Track/waypoint/route navigation can
# still switch into it automatically, but a user selecting Course Up also gets the same stable camera.
old="""  function navigationPerspectiveActive() {
    return mapMode === '2d' && navPerspectiveEnabled && orientationMode === 'courseup' && operationalNavigationActive() && !routeDrawMode;
  }
"""
new="""  function navigationPerspectiveActive() {
    return mapMode === '2d' && navPerspectiveEnabled && orientationMode === 'courseup' && !routeDrawMode;
  }
"""
if old not in s:
    raise SystemExit('navigationPerspectiveActive v0.29 block not found')
s=s.replace(old,new,1)

# Add a screen-fixed GPS vessel. In follow mode this is the user's visual anchor; the map moves
# underneath it instead of asking a Leaflet marker inside a rotated DOM tree to stay in place.
needle='<div id="map"></div>\n    <div id="navZoomControl"'
insert='''<div id="map"></div>\n    <div id="navGpsAnchor" aria-hidden="true"><div class="navGpsHalo"></div><div class="navGpsBoat"><svg viewBox="0 0 46 56"><path d="M23 3 L41 50 L23 42 L5 50 Z" fill="#087cb8" stroke="#ffffff" stroke-width="4" stroke-linejoin="round"/><circle cx="23" cy="34" r="4" fill="#ffffff"/></svg></div></div>\n    <div id="navZoomControl"'''
if needle not in s:
    raise SystemExit('map/navZoomControl insertion anchor not found')
s=s.replace(needle,insert,1)

# Replace the perspective UI state so manual pan drops back to a normal upright map, while follow
# mode gets both the oversized rotating chart and the fixed lower-center GPS anchor.
pattern=r"  function updateNavigationPerspectiveUi\(\) \{.*?\n  \}\n\n  function currentNavigationSpeedMps\(\) \{"
m=re.search(pattern,s,flags=re.S)
if not m:
    raise SystemExit('updateNavigationPerspectiveUi block not found')
replacement=r'''  function updateNavigationPerspectiveUi() {
    const active=navigationPerspectiveActive();
    const followVisual=active && navFollowMode;
    const pinned=followVisual && !!currentLoc;
    if ($('quickPerspectiveToggle')) $('quickPerspectiveToggle').checked=navPerspectiveEnabled;
    if ($('mapWrap')) {
      $('mapWrap').classList.toggle('courseUp2d', followVisual);
      $('mapWrap').classList.toggle('navPerspective2d', followVisual);
      $('mapWrap').classList.toggle('navGpsPinned', pinned);
    }
    if (followVisual !== navPerspectiveLayoutActive) {
      navPerspectiveLayoutActive=followVisual;
      if (map) {
        const c=map.getCenter();
        setTimeout(()=>{ try { map.invalidateSize({pan:false,animate:false}); map.panTo(c,{animate:false}); applyMapOrientation(); } catch(e) {} },70);
        setTimeout(()=>{ try { map.invalidateSize({pan:false,animate:false}); } catch(e) {} },260);
      }
    }
    if ($('chartChip') && mapMode==='2d') {
      if (followVisual) $('chartChip').textContent='Navigation follow';
      else if (active && !navFollowMode) $('chartChip').textContent='Free pan • tap GPS to resume';
      else $('chartChip').textContent=(map && noaaLayer && map.hasLayer(noaaLayer)) ? 'NOAA chart overlay' : 'OSM map';
    }
  }

  function currentNavigationSpeedMps() {'''
s=s[:m.start()]+replacement+s[m.end():]

# The map now rotates around its true center. The GPS arrow is independent and fixed lower-center,
# which prevents the vessel from orbiting sideways as the DOM transform changes heading.
s=s.replace("    const courseUpVisual = orientationMode === 'courseup' && !(operationalNavigationActive() && !navFollowMode);",
            "    const courseUpVisual = orientationMode === 'courseup' && navFollowMode;",1)

# Manual drag immediately exits the rotated follow surface. This makes finger drag direction match
# the map direction and hides the pinned arrow until GPS/Center is tapped again.
old_drag="    map.on('dragstart', () => { navFollowMode=false; applyMapOrientationWithHeading(null); if($('chartChip')) $('chartChip').textContent='Free pan • tap GPS to resume'; });"
new_drag="    map.on('dragstart', () => { navFollowMode=false; updateNavigationPerspectiveUi(); applyMapOrientationWithHeading(null); if($('chartChip')) $('chartChip').textContent='Free pan • tap GPS to resume'; });"
if old_drag not in s:
    raise SystemExit('v0.29 dragstart block not found')
s=s.replace(old_drag,new_drag,1)

# Entering Course Up must enable follow BEFORE applying orientation so the very first frame is the
# pinned navigation camera instead of a transient rotated/free-pan hybrid.
old_toggle="""    orientationMode = orientationMode === 'courseup' ? 'northup' : 'courseup';
    const h = activeHeading();
    mapRotationDeg = orientationMode === 'courseup' && h ? h.degrees : 0;
    localStorage.setItem(STORAGE_ORIENTATION, orientationMode);
    applyMapOrientation();
    if (orientationMode==='courseup' && navPerspectiveEnabled) { navFollowMode=true; if(currentLoc) setTimeout(()=>centerPrimaryNavigationView(true),50); }
    else if (currentLoc && mapMode==='2d') map.panTo([currentLoc.lat,currentLoc.lon],{animate:true,duration:.28});
"""
new_toggle="""    orientationMode = orientationMode === 'courseup' ? 'northup' : 'courseup';
    if (orientationMode==='courseup' && navPerspectiveEnabled) navFollowMode=true;
    const h = activeHeading();
    mapRotationDeg = orientationMode === 'courseup' && h ? h.degrees : 0;
    localStorage.setItem(STORAGE_ORIENTATION, orientationMode);
    updateNavigationPerspectiveUi();
    applyMapOrientation();
    if (orientationMode==='courseup' && navPerspectiveEnabled) { if(currentLoc) setTimeout(()=>centerPrimaryNavigationView(true),70); }
    else if (currentLoc && mapMode==='2d') map.panTo([currentLoc.lat,currentLoc.lon],{animate:true,duration:.28});
"""
if old_toggle not in s:
    raise SystemExit('toggleOrientationMode block not found')
s=s.replace(old_toggle,new_toggle,1)

# Perspective toggle uses the same ordering fix.
old_set="""    navPerspectiveEnabled=!!on;
    localStorage.setItem(STORAGE_NAV_PERSPECTIVE,navPerspectiveEnabled?'1':'0');
    updateNavigationPerspectiveUi();
    if (navPerspectiveEnabled && orientationMode==='courseup') {
      navFollowMode=true;
      if (currentLoc) setTimeout(()=>centerPrimaryNavigationView(true),40);
"""
new_set="""    navPerspectiveEnabled=!!on;
    localStorage.setItem(STORAGE_NAV_PERSPECTIVE,navPerspectiveEnabled?'1':'0');
    if (navPerspectiveEnabled && orientationMode==='courseup') navFollowMode=true;
    updateNavigationPerspectiveUi();
    if (navPerspectiveEnabled && orientationMode==='courseup') {
      if (currentLoc) setTimeout(()=>centerPrimaryNavigationView(true),60);
"""
if old_set not in s:
    raise SystemExit('setNavigationPerspective ordering block not found')
s=s.replace(old_set,new_set,1)

# Center/GPS restores the pinned follow camera immediately.
center_pat=r"(\$\('centerBtn'\)\.addEventListener\('click', \(\) => \{\n      if \(currentLoc && map\) \{\n        navFollowMode=true;)(.*?)\n      \}\n    \}\);"
cm=re.search(center_pat,s,flags=re.S)
if not cm:
    raise SystemExit('centerBtn handler not found')
center_new=cm.group(1)+"\n        updateNavigationPerspectiveUi();\n        applyMapOrientation();"+cm.group(2)+"\n      }\n    });"
s=s[:cm.start()]+center_new+s[cm.end():]

# Keep the pinned class in sync once the first GPS fix arrives.
old_loc_tail="""    updateHeadingVisuals();
    maybeFollowPrimaryNavigation();
"""
new_loc_tail="""    updateNavigationPerspectiveUi();
    updateHeadingVisuals();
    maybeFollowPrimaryNavigation();
"""
if old_loc_tail not in s:
    raise SystemExit('location update tail not found')
s=s.replace(old_loc_tail,new_loc_tail,1)

css='''
/* v0.30 pinned GPS navigation camera */
#navGpsAnchor {
  display:none; position:absolute; left:50%; top:76%; width:58px; height:66px;
  transform:translate(-50%,-50%); z-index:790; pointer-events:none;
}
#mapWrap.navGpsPinned #navGpsAnchor { display:block; }
#navGpsAnchor .navGpsHalo {
  position:absolute; left:50%; top:52%; width:50px; height:50px; transform:translate(-50%,-50%);
  border-radius:50%; background:rgba(8,124,184,.12); border:1px solid rgba(255,255,255,.88);
  box-shadow:0 2px 10px rgba(0,54,86,.20),0 0 0 5px rgba(8,124,184,.07);
}
#navGpsAnchor .navGpsBoat {
  position:absolute; left:50%; top:50%; width:46px; height:56px; transform:translate(-50%,-50%);
  filter:drop-shadow(0 3px 5px rgba(0,34,54,.40));
}
#navGpsAnchor svg { display:block; width:100%; height:100%; overflow:visible; }
#mapWrap.navGpsPinned #map .boatMarker { opacity:0 !important; }
/* A 200% Leaflet surface gives enough cover for every rotation angle around the true center. */
#mapWrap.courseUp2d #map,
#mapWrap.navPerspective2d #map { inset:-50%; transform-origin:50% 50% !important; }
'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.30 features' not in r:
    insert='''\n## Version 0.30 features\n\n### Pinned GPS Course Up camera\n- Rebuilds the Course Up visual model around a fixed screen-position GPS vessel at the lower center of the map. The vessel no longer depends on a Leaflet marker inside the rotated map surface; the chart moves beneath the vessel instead.\n- Course Up is now a follow camera whenever selected, even when the user is not actively recording a track or navigating to a saved route/waypoint. Manual dragging temporarily releases follow; tapping GPS/Center restores it.\n- Returns the rotating map transform origin to the true center and expands the Leaflet chart surface to 200% of the visible map area. This removes the large unloaded/exposed wedges created by the previous lower-pivot rotation approach.\n- Adds two staged Leaflet size invalidations when entering/leaving follow mode so the larger rotated surface requests the tiles it actually needs.\n- Free pan is always upright and hides the pinned navigation vessel, so dragging behaves naturally.\n- The v0.29 movement-first heading logic remains in place: actual GPS displacement drives the moving camera, Android GPS bearing is secondary, and phone compass is primarily a stopped fallback.\n'''
    pos=r.find('\n## Version 0.29 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)

p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 30/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.30.0'/" app/build.gradle
grep -q 'v0.30' app/src/main/assets/index.html
grep -q 'navGpsAnchor' app/src/main/assets/index.html
grep -q 'inset:-50%' app/src/main/assets/index.html
grep -q 'Version 0.30 features' README.md
printf 'LakeNav WI v0.30 pinned GPS navigation camera applied.\n'
