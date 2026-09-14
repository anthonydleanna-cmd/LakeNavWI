#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re
p=Path('app/src/main/assets/index.html')
s=p.read_text()

# Version.
s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.23</span></div>', s, count=1)

# Keep 3D implementation intact, but park it outside the normal production UI.
s=s.replace('<div class="quickLayerRow"><div class="quickLayerText">3D chart preview<small>Perspective terrain + chartplotter view</small></div><label class="toggleSwitch"><input type="checkbox" id="quick3dToggle"><span></span></label></div>', '<div class="quickLayerRow experimental3dRow"><div class="quickLayerText">3D chart preview<small>Experimental terrain renderer retained for future reference</small></div><label class="toggleSwitch"><input type="checkbox" id="quick3dToggle"><span></span></label></div>', 1)

# New primary 2D navigation-view control.
needle='<div class="quickTitle"><strong>Map layers</strong><button class="closeBtn" id="quickLayersClose" aria-label="Close layers">x</button></div>'
insert=needle+'\n      <div class="quickLayerRow"><div class="quickLayerText">Navigation perspective<small>Forward-looking 2D view in Course Up</small></div><label class="toggleSwitch"><input type="checkbox" id="quickPerspectiveToggle"><span></span></label></div>\n      <div class="muted" style="font-size:9px;line-height:1.3;padding:0 4px 7px">North Up stays a flat planning chart. Course Up shifts the chart ahead of the boat and adds subtle navigation shading without using the 3D terrain engine.</div>'
if needle not in s: raise SystemExit('layers title not found')
s=s.replace(needle,insert,1)

# Add visual-only perspective shading above the geographic map. It never receives taps.
s=s.replace('<div id="map"></div>\n    <div id="map3d"', '<div id="map"></div>\n    <div id="navPerspectiveShade" aria-hidden="true"></div>\n    <div id="map3d"', 1)

css='''\n/* v0.23 primary 2D chartplotter/navigation presentation */\n.experimental3dRow { display:none !important; }\n#download3dLakeBtn { display:none !important; }\n#navPerspectiveShade {\n  display:none; position:absolute; inset:0; z-index:640; pointer-events:none;\n  background:\n    linear-gradient(to bottom, rgba(3,31,46,.19) 0%, rgba(9,53,70,.07) 18%, rgba(255,255,255,0) 39%, rgba(255,255,255,0) 73%, rgba(4,28,40,.08) 100%),\n    radial-gradient(ellipse at 50% 113%, rgba(0,0,0,.10) 0%, rgba(0,0,0,0) 48%);\n  box-shadow: inset 0 16px 28px rgba(2,26,39,.08);\n}\n#mapWrap.navPerspective2d #navPerspectiveShade { display:block; }\n#mapWrap.navPerspective2d #map .leaflet-tile-pane { filter:saturate(1.10) contrast(1.055) brightness(.985); }\n#mapWrap.navPerspective2d #chartChip { background:rgba(6,37,52,.89); color:#eaffff; border:1px solid rgba(73,210,232,.32); }\n#mapWrap.navPerspective2d #orientationBtn { background:rgba(7,42,57,.92); color:#71e5ff; border:1px solid rgba(88,219,240,.30); }\n#mapWrap.navPerspective2d .leaflet-control-zoom { opacity:.92; }\n'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

# Persisted setting. Default ON because it only changes Course Up; North Up remains conventional.
s=s.replace("  const STORAGE_MAP_MODE = 'lakenav.mapmode.v1';", "  const STORAGE_MAP_MODE = 'lakenav.mapmode.v1';\n  const STORAGE_NAV_PERSPECTIVE = 'lakenav.navperspective.v1';",1)
s=s.replace("  let mapMode = localStorage.getItem(STORAGE_MAP_MODE) === '3d' ? '3d' : '2d';", "  // 3D code is intentionally retained, but LakeNav now always starts in the primary 2D engine.\n  let mapMode = '2d';\n  let navPerspectiveEnabled = localStorage.getItem(STORAGE_NAV_PERSPECTIVE) !== '0';\n  let navFollowMode = true;\n  let lastNavFollowAt = 0;",1)

# Insert 2D perspective/follow helpers immediately before the orientation UI.
anchor='  function updateOrientationButton() {'
helpers=r'''  function navigationPerspectiveActive() {
    return mapMode === '2d' && navPerspectiveEnabled && orientationMode === 'courseup' && !routeDrawMode;
  }

  function updateNavigationPerspectiveUi() {
    const active=navigationPerspectiveActive();
    if ($('quickPerspectiveToggle')) $('quickPerspectiveToggle').checked=navPerspectiveEnabled;
    if ($('mapWrap')) $('mapWrap').classList.toggle('navPerspective2d', active);
    if ($('chartChip') && mapMode==='2d') {
      if (active) $('chartChip').textContent='2D navigation view';
      else $('chartChip').textContent=(map && noaaLayer && map.hasLayer(noaaLayer)) ? 'NOAA chart overlay' : 'OSM map';
    }
  }

  function perspectiveCenterLatLng() {
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

  function centerPrimaryNavigationView(animate) {
    if (!map || !currentLoc || mapMode!=='2d') return;
    const target=perspectiveCenterLatLng() || [currentLoc.lat,currentLoc.lon];
    const z=Math.max(map.getZoom(),15);
    if (Math.abs(map.getZoom()-z)>0.01) map.setView(target,z,{animate:!!animate});
    else map.panTo(target,{animate:!!animate,duration:.34,easeLinearity:.25});
  }

  function maybeFollowPrimaryNavigation() {
    if (!navFollowMode || !navigationPerspectiveActive() || !map || !currentLoc || routeDrawMode) return;
    const now=performance.now();
    if (now-lastNavFollowAt < 700) return;
    lastNavFollowAt=now;
    const target=perspectiveCenterLatLng();
    if (target) map.panTo(target,{animate:false,noMoveStart:true});
  }

  function setNavigationPerspective(on) {
    navPerspectiveEnabled=!!on;
    localStorage.setItem(STORAGE_NAV_PERSPECTIVE,navPerspectiveEnabled?'1':'0');
    updateNavigationPerspectiveUi();
    if (navPerspectiveEnabled && orientationMode==='courseup') {
      navFollowMode=true;
      if (currentLoc) setTimeout(()=>centerPrimaryNavigationView(true),40);
    } else if (currentLoc && mapMode==='2d') {
      map.panTo([currentLoc.lat,currentLoc.lon],{animate:true,duration:.3});
    }
  }

'''
if anchor not in s: raise SystemExit('orientation anchor missing')
s=s.replace(anchor,helpers+anchor,1)

# Perspective UI follows orientation/map-mode changes.
s=s.replace("    updateOrientationButton();\n  }\n\n  function applyMapOrientation()", "    updateOrientationButton();\n    updateNavigationPerspectiveUi();\n  }\n\n  function applyMapOrientation()",1)
s=s.replace("    applyMapOrientation();\n    if (window.Android && Android.toast) Android.toast(orientationMode === 'courseup' ? 'Course-up display enabled' : 'North-up display enabled');", "    applyMapOrientation();\n    if (orientationMode==='courseup' && navPerspectiveEnabled) { navFollowMode=true; if(currentLoc) setTimeout(()=>centerPrimaryNavigationView(true),50); }\n    else if (currentLoc && mapMode==='2d') map.panTo([currentLoc.lat,currentLoc.lon],{animate:true,duration:.28});\n    if (window.Android && Android.toast) Android.toast(orientationMode === 'courseup' ? (navPerspectiveEnabled?'Course-up navigation view enabled':'Course-up display enabled') : 'North-up planning view enabled');",1)

# User panning deliberately releases auto-follow; Center restores it.
map_listener="    map.on('click', function (e) {"
if map_listener not in s: raise SystemExit('map click listener missing')
s=s.replace(map_listener, "    map.on('dragstart', () => { navFollowMode=false; });\n    map.on('click', function (e) {",1)

# Initial GPS fix uses the forward-looking center when Course Up is already selected.
s=s.replace("      if (firstFix) {\n        firstFix = false;\n        map.setView([lat, lon], 15);\n      }", "      if (firstFix) {\n        firstFix = false;\n        const firstCenter=perspectiveCenterLatLng() || [lat,lon];\n        map.setView(firstCenter,15);\n      }",1)

# Follow GPS smoothly while in primary Course Up nav view.
s=s.replace("    updateHeadingVisuals();\n    sync3dBoat();", "    updateHeadingVisuals();\n    maybeFollowPrimaryNavigation();\n    sync3dBoat();",1)

# Starting navigation opts into follow, then moves the boat to the lower part of the visual field.
s=s.replace("    updateNavigation();\n    renderOfflineFallbackOverlays();\n    if (map) map.fitBounds(currentLoc ? [[currentLoc.lat, currentLoc.lon], [w.lat, w.lon]] : [[w.lat, w.lon], [w.lat, w.lon]], { padding: [50, 50], maxZoom: 16 });", "    updateNavigation();\n    renderOfflineFallbackOverlays();\n    navFollowMode=true;\n    if (map) map.fitBounds(currentLoc ? [[currentLoc.lat, currentLoc.lon], [w.lat, w.lon]] : [[w.lat, w.lon], [w.lat, w.lon]], { padding: [50, 50], maxZoom: 16 });\n    if (navigationPerspectiveActive() && currentLoc) setTimeout(()=>centerPrimaryNavigationView(true),520);",1)
s=s.replace("    updateNavigation();\n    renderOfflineFallbackOverlays();\n    if (map) map.fitBounds(L.latLngBounds(pts.map(w => [w.lat,w.lon])), { padding:[45,45], maxZoom:16 });", "    updateNavigation();\n    renderOfflineFallbackOverlays();\n    navFollowMode=true;\n    if (map) map.fitBounds(L.latLngBounds(pts.map(w => [w.lat,w.lon])), { padding:[45,45], maxZoom:16 });\n    if (navigationPerspectiveActive() && currentLoc) setTimeout(()=>centerPrimaryNavigationView(true),520);",1)

# Route drawing remains a flat North Up planning operation.
s=s.replace("      mapRotationDeg = 0;\n      applyMapOrientationWithHeading(null);", "      mapRotationDeg = 0;\n      updateNavigationPerspectiveUi();\n      applyMapOrientationWithHeading(null);",1)

# Center button: return to GPS and re-enable follow in the new 2D view.
old="""    $('centerBtn').addEventListener('click', () => {
      if (currentLoc && map) {
        if (mapMode === '3d' && map3d) { map3d.easeTo({center:[currentLoc.lon,currentLoc.lat], zoom:Math.max(map3d.getZoom(),14.5), pitch:62, duration:600, essential:true}); }
        else map.setView([currentLoc.lat, currentLoc.lon], Math.max(map.getZoom(), 15));
      }
    });"""
new="""    $('centerBtn').addEventListener('click', () => {
      if (currentLoc && map) {
        navFollowMode=true;
        if (mapMode === '3d' && map3d) { map3d.easeTo({center:[currentLoc.lon,currentLoc.lat], zoom:Math.max(map3d.getZoom(),14.5), pitch:62, duration:600, essential:true}); }
        else centerPrimaryNavigationView(true);
      }
    });"""
if old in s: s=s.replace(old,new,1)
else:
    # tolerate small prior formatting changes
    s=re.sub(r"\s*\$\('centerBtn'\)\.addEventListener\('click', \(\) => \{.*?\n\s*\}\);", '\n'+new, s, count=1, flags=re.S)

# Wire new toggle; leave hidden 3D toggle functional for future re-enabling.
s=s.replace("    $('quick3dToggle').addEventListener('change', e => setMapMode(e.target.checked ? '3d' : '2d'));", "    $('quickPerspectiveToggle').addEventListener('change', e => setNavigationPerspective(e.target.checked));\n    $('quick3dToggle').addEventListener('change', e => setMapMode(e.target.checked ? '3d' : '2d'));",1)

# Always initialize the production map as 2D, then apply the perspective preference.
s=s.replace("    if (mapMode === '3d') setMapMode('3d', true);", "    setMapMode('2d', true);\n    updateNavigationPerspectiveUi();",1)

# Clean user-facing offline copy while keeping all 3D implementation code available.
s=s.replace('Offline packages keep a high-resolution Wisconsin DNR map snapshot, shoreline geometry, lake identity, DNR contour sheets, and optional downloaded 3D terrain. Download the 3D package on Wi-Fi before a trip and it can render without cellular service.', 'Offline packages keep a high-resolution Wisconsin DNR lake map snapshot, shoreline geometry, lake identity, and DNR contour sheets for dependable 2D use away from service. Experimental 3D package code is retained for future development.',1)

p.write_text(s)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.23 features' not in r:
    insert='''\n## Version 0.23 features\n\n### Primary 2D navigation direction\n- LakeNav now always starts in the established 2D map engine. The full experimental 3D implementation remains in source for future reference, but its normal UI entry and lake-download button are parked for now.\n- Adds a Navigation Perspective option to the Layers panel. North Up remains a conventional flat planning chart; Course Up becomes the forward-looking navigation presentation.\n- The perspective effect intentionally avoids distorting geographic geometry. Instead of tilting the Leaflet canvas, LakeNav shifts the map center ahead of the boat, keeps the vessel lower in the visual field, adds subtle horizon/vignette shading, and slightly strengthens basemap contrast. Waypoint taps and overlay alignment therefore remain geographically correct.\n- Centering on GPS re-enables follow mode. Manual map dragging releases follow so the user can inspect another area without fighting automatic recentering.\n- Starting waypoint or route navigation re-enables follow and transitions into the forward-looking Course Up composition when that view is enabled.\n- Route drawing remains a stable North Up planning operation.\n\n### Why 3D is retained but parked\n- MapLibre terrain, offline terrain-package, 3D navigation, and 3D bathymetry code are intentionally not deleted. They remain available for future experiments or selective reuse without carrying their rendering/network cost in the normal LakeNav workflow.\n'''
    pos=r.find('\n## Version 0.22 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 23/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.23.0'/" app/build.gradle
grep -q 'v0.23' app/src/main/assets/index.html
grep -q 'Navigation perspective' app/src/main/assets/index.html
grep -q 'Primary 2D navigation direction' README.md
printf 'LakeNav WI v0.23 primary 2D navigation perspective applied; 3D code retained.\n'
