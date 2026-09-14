#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re
p=Path('app/src/main/assets/index.html')
s=p.read_text()
s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.24</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.25</span></div>', s, count=1)

# Depth below operational overlays and more subtle.
s=s.replace("map.getPane('depthPane').style.zIndex = 330;", "map.getPane('depthPane').style.zIndex = 305;",1)
s=s.replace("return {color:'rgba(56,77,88,.24)',weight:0.38,fillColor:band.fill,fillOpacity:0.54};", "return {color:'rgba(56,77,88,.18)',weight:0.30,fillColor:band.fill,fillOpacity:0.32};",1)

# NOAA aid symbols stay clean; details remain available on tap.
s=s.replace("    const zoom=map.getZoom();\n    const showLabels=zoom>=13;", "    const zoom=map.getZoom();",1)
s=s.replace("      const label=showLabels && name ? '<span class=\"encAidLabel\">'+encText(name)+'</span>' : '';\n      const html='<div class=\"encAidWrap '+kind+'\"><div class=\"encAidShape\" style=\"background:'+noaaAidColour(p)+'\"></div>'+label+'</div>';", "      const html='<div class=\"encAidWrap '+kind+'\"><div class=\"encAidShape\" style=\"background:'+noaaAidColour(p)+'\"></div></div>';",1)
s=s.replace(".encAidLabel { position:absolute; left:18px; top:1px; white-space:nowrap; font:700 9px/1.1 system-ui,sans-serif; color:#f7fdff; text-shadow:0 1px 2px #00151f,0 0 2px #00151f,0 0 4px #00151f; pointer-events:none; }\n","")
s=s.replace("NOAA navigation aids<small>Buoys, beacons, daymarks and lights on the normal map</small>", "NOAA navigation aids<small>Clean symbols only • tap an aid for name and details</small>",1)
s=s.replace("Depth colors<small>NOAA ENC bathymetry</small>", "Depth colors<small>Subtle NOAA ENC bathymetry beneath other overlays</small>",1)

# Perspective layout: clip overscan and keep zoom controls outside the rotating map.
s=s.replace("#mapWrap { position: relative; flex: 1 1 auto; min-height: 0; }", "#mapWrap { position: relative; flex: 1 1 auto; min-height: 0; overflow:hidden; }",1)
css='''\n/* v0.25 course-up perspective refinement */\n#mapWrap.navPerspective2d #map { inset:-30%; }\n#mapWrap.navPerspective2d .leaflet-control-zoom { display:none !important; }\n#navZoomControl { display:none; position:absolute; left:10px; top:50%; transform:translateY(-50%); z-index:760; border-radius:14px; overflow:hidden; box-shadow:0 7px 18px rgba(4,31,45,.22); border:1px solid rgba(255,255,255,.7); }\n#mapWrap.navPerspective2d #navZoomControl { display:flex; flex-direction:column; }\n#navZoomControl button { width:42px; height:42px; border:0; background:rgba(248,253,255,.94); color:#173c4c; font-size:25px; font-weight:500; line-height:1; padding:0; }\n#navZoomControl button + button { border-top:1px solid rgba(13,65,84,.14); }\n#navZoomControl button:active { background:#e1f2f7; }\n'''
s=s.replace("\n/* v0.24 NOAA ENC-derived navigation-aid symbols */", css+"\n/* v0.24 NOAA ENC-derived navigation-aid symbols */",1)
s=s.replace('<div id="map"></div>\n    <div id="navPerspectiveShade"', '<div id="map"></div>\n    <div id="navZoomControl" aria-label="Map zoom"><button id="navZoomInBtn" aria-label="Zoom in">+</button><button id="navZoomOutBtn" aria-label="Zoom out">−</button></div>\n    <div id="navPerspectiveShade"',1)
s=s.replace("  let lastNavFollowAt = 0;", "  let lastNavFollowAt = 0;\n  let navPerspectiveLayoutActive = false;",1)

old='''  function updateNavigationPerspectiveUi() {\n    const active=navigationPerspectiveActive();\n    if ($('quickPerspectiveToggle')) $('quickPerspectiveToggle').checked=navPerspectiveEnabled;\n    if ($('mapWrap')) $('mapWrap').classList.toggle('navPerspective2d', active);\n    if ($('chartChip') && mapMode==='2d') {\n      if (active) $('chartChip').textContent='2D navigation view';\n      else $('chartChip').textContent=(map && noaaLayer && map.hasLayer(noaaLayer)) ? 'NOAA chart overlay' : 'OSM map';\n    }\n  }\n'''
new='''  function updateNavigationPerspectiveUi() {\n    const active=navigationPerspectiveActive();\n    if ($('quickPerspectiveToggle')) $('quickPerspectiveToggle').checked=navPerspectiveEnabled;\n    if ($('mapWrap')) $('mapWrap').classList.toggle('navPerspective2d', active);\n    if (active !== navPerspectiveLayoutActive) {\n      navPerspectiveLayoutActive=active;\n      if (map) {\n        const c=map.getCenter();\n        setTimeout(()=>{ try { map.invalidateSize({pan:false,animate:false}); map.panTo(c,{animate:false}); applyMapOrientation(); } catch(e) {} },60);\n      }\n    }\n    if ($('chartChip') && mapMode==='2d') {\n      if (active) $('chartChip').textContent='2D navigation view';\n      else $('chartChip').textContent=(map && noaaLayer && map.hasLayer(noaaLayer)) ? 'NOAA chart overlay' : 'OSM map';\n    }\n  }\n'''
if old not in s: raise SystemExit('updateNavigationPerspectiveUi block not found')
s=s.replace(old,new,1)

old='''    const visualAngle = orientationMode === 'courseup' ? mapRotationDeg : 0;\n    const scale = visualAngle ? 1.12 : 1;\n'''
new='''    const visualAngle = orientationMode === 'courseup' ? mapRotationDeg : 0;\n    let scale = visualAngle ? 1.12 : 1;\n    if (visualAngle && navigationPerspectiveActive() && $('mapWrap')) {\n      const wrap=$('mapWrap');\n      const w=Math.max(1,wrap.clientWidth), h=Math.max(1,wrap.clientHeight);\n      const aspect=h/w;\n      const rad=Math.abs(visualAngle)*Math.PI/180;\n      const c=Math.abs(Math.cos(rad)), sn=Math.abs(Math.sin(rad));\n      const overscan=1.60;\n      const reqX=c+aspect*sn;\n      const reqY=c+(1/aspect)*sn;\n      scale=Math.max(1,reqX/overscan,reqY/overscan)*1.035;\n      scale=Math.min(1.48,Math.max(1.02,scale));\n    }\n'''
if old not in s: raise SystemExit('orientation scale block not found')
s=s.replace(old,new,1)

wire="    $('quickNoaaAidsToggle').addEventListener('change', e => setNoaaNavAids(e.target.checked));\n"
if wire not in s: raise SystemExit('NOAA toggle wiring not found')
s=s.replace(wire,wire+"    $('navZoomInBtn').addEventListener('click', () => { if(map) map.zoomIn(); });\n    $('navZoomOutBtn').addEventListener('click', () => { if(map) map.zoomOut(); });\n",1)

p.write_text(s)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.25 features' not in r:
    insert='''\n## Version 0.25 features\n\n### Perspective-view cleanup\n- Course Up navigation perspective now uses an oversized map canvas with bounded dynamic cover scaling, reducing exposed corner/dead-space artifacts as the chart rotates.\n- Leaflet's built-in zoom buttons are hidden in the rotated perspective state and replaced by fixed upright zoom controls outside the rotating chart surface.\n- The map wrapper clips overscan cleanly, while the right-side dock, chart chips, and other LakeNav controls stay screen-aligned.\n\n### Cleaner NOAA aids + subtler depth tint\n- NOAA buoy/beacon/daymark/light labels are no longer permanently drawn beside symbols. Tap a symbol to view its name and NOAA-derived details.\n- Depth colors move below radar/other operational overlays and use a lighter 32% fill opacity, keeping bathymetry visible without dominating combined layers.\n'''
    pos=r.find('\n## Version 0.24 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 25/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.25.0'/" app/build.gradle
grep -q 'v0.25' app/src/main/assets/index.html
grep -q 'navZoomControl' app/src/main/assets/index.html
grep -q 'fillOpacity:0.32' app/src/main/assets/index.html
grep -q 'Perspective-view cleanup' README.md
printf 'LakeNav WI v0.25 perspective and overlay cleanup applied.\n'
