#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re
p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.26</span></div>', s, count=1)

# NOAA nav-aid popup: explicitly show the official/available name when the user taps a marker.
s=s.replace("      const name=(p.OBJNAM||p.INFORM||'').toString().trim();", "      const name=(p.OBJNAM||p.NOBJNM||p.INFORM||'').toString().trim();", 1)
s=s.replace("      const parts=['<div class=\"encAidPopup\"><strong>'+encText(name||typeLabel)+'</strong>','<div>'+typeLabel+' • NOAA ENC '+encText(bandName)+'</div>'];", "      const parts=['<div class=\"encAidPopup\"><strong>'+encText(name||typeLabel)+'</strong>','<div>'+typeLabel+' • NOAA ENC '+encText(bandName)+'</div>'];\n      if (name) parts.push('<div><b>Name:</b> '+encText(name)+'</div>');", 1)

# Prevent the close-zoom depth tint from stacking multiple ENC scale bands on top of each other in 2D.
# Keep the merged collection for 3D/reference, but render the normal 2D map from the most detailed
# available scale that returned data. This preserves continuity while keeping opacity consistent.
old="""    if (depthShadeEnabled) {
      if (depthShadeLayer && map) { try { map.removeLayer(depthShadeLayer); } catch(e) {} }
      depthShadeLayer=L.geoJSON(geojson,{
        pane:'depthPane',interactive:false,
        style:feature=>{
          const props=feature&&feature.properties?feature.properties:{};
          const shallowFt=Number(props.DRVAL1)*M_TO_FT;
          const band=depthBandForFeet(shallowFt);
          return {color:'rgba(56,77,88,.18)',weight:0.30,fillColor:band.fill,fillOpacity:0.32};
        }
      }).addTo(map);
      renderDepthLabels(merged);
      if ($('depthLegendStatus')) $('depthLegendStatus').textContent = results.map(r=>r.source.name).join(' + ')+' ENC • '+merged.length+' merged depth areas • padded close-zoom coverage.';
    }"""
new="""    if (depthShadeEnabled) {
      if (depthShadeLayer && map) { try { map.removeLayer(depthShadeLayer); } catch(e) {} }
      const best2dGroup=results.slice().sort((a,b)=>a.priority-b.priority)[0];
      const depth2dFeatures=best2dGroup && Array.isArray(best2dGroup.features) ? best2dGroup.features : merged;
      const depth2dGeojson={type:'FeatureCollection',features:depth2dFeatures};
      depthShadeLayer=L.geoJSON(depth2dGeojson,{
        pane:'depthPane',interactive:false,
        style:feature=>{
          const props=feature&&feature.properties?feature.properties:{};
          const shallowFt=Number(props.DRVAL1)*M_TO_FT;
          const band=depthBandForFeet(shallowFt);
          return {color:'rgba(56,77,88,.16)',weight:0.26,fillColor:band.fill,fillOpacity:0.30};
        }
      }).addTo(map);
      renderDepthLabels(depth2dFeatures);
      if ($('depthLegendStatus')) $('depthLegendStatus').textContent = (best2dGroup?best2dGroup.source.name:'NOAA')+' ENC • '+depth2dFeatures.length+' depth areas • single-scale 2D shading prevents close-zoom color stacking.';
    }"""
if old not in s:
    raise SystemExit('depth render block not found')
s=s.replace(old,new,1)

p.write_text(s)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.26 features' not in r:
    insert='''\n## Version 0.26 features\n\n### Depth overlay consistency and NOAA aid details\n- Fixes the close-zoom 2D depth overlay from becoming too strong when multiple ENC scale bands overlap. LakeNav still keeps the merged multi-scale depth collection available internally, but the normal 2D display now renders the most detailed available NOAA depth scale as a single visual layer.\n- Slightly reduces depth fill and boundary opacity again so the bathymetry remains subtle underneath navigation aids, routes, radar, and other operational overlays.\n- Keeps depth labels tied to the same single-scale 2D feature set to reduce duplicate labels at close zoom.\n- NOAA buoy/beacon/daymark/light symbols remain unlabeled on the map, but their tap popup now explicitly includes the available NOAA name, using `OBJNAM`, `NOBJNM`, or informational text as fallback.\n- No Course Up/perspective behavior changes in this pass so the next navigation-view iteration can be based on focused user feedback.\n'''
    pos=r.find('\n## Version 0.25 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 26/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.26.0'/" app/build.gradle
grep -q 'v0.26' app/src/main/assets/index.html
grep -q 'single-scale 2D shading' app/src/main/assets/index.html
grep -q 'Version 0.26 features' README.md
printf 'LakeNav WI v0.26 depth rendering and NOAA popup refinements applied.\n'
