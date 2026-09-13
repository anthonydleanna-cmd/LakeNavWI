#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re
p=Path('app/src/main/assets/index.html')
s=p.read_text()
s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.21</span></div>', s, count=1)

# Make major contour text easier to read at pitch: one centered label per boundary, larger halo.
s=s.replace("'symbol-placement':'line','symbol-spacing':360,", "'symbol-placement':'line-center',")
s=s.replace("'text-field':['get','label'],'text-size':['interpolate',['linear'],['zoom'],11.5,10,15,13],", "'text-field':['get','label'],'text-size':['interpolate',['linear'],['zoom'],11.5,11,14,13,16,15],")
s=s.replace("'text-padding':6", "'text-padding':10")
s=s.replace("'text-color':'rgba(239,253,255,.88)','text-halo-color':'rgba(7,42,55,.78)','text-halo-width':1.5,'text-halo-blur':0.7", "'text-color':'#f5feff','text-halo-color':'rgba(3,28,39,.94)','text-halo-width':2.4,'text-halo-blur':0.9")

# At close zoom make the water tint slightly more opaque and boundaries more subtle.
s=s.replace("'fill-opacity':['interpolate',['linear'],['zoom'],7,0.56,11,0.62,15,0.68]", "'fill-opacity':['interpolate',['linear'],['zoom'],7,0.56,11,0.62,14,0.69,17,0.74]")
s=s.replace("'line-width':['interpolate',['linear'],['zoom'],8,0.35,12,0.65,16,1.05]", "'line-width':['interpolate',['linear'],['zoom'],8,0.35,12,0.58,16,0.82]")

# Replace the viewport fetcher. High zoom now pads the request and merges several ENC scales,
# drawing broader coverage first and the most detailed coverage last. This avoids the sparse/blocky
# appearance when a detailed ENC layer only covers part of a close view.
start=s.index('  async function refreshDepthShading() {')
end=s.index('  function toggleDepthShading(on) {', start)
new_refresh=r'''  async function refreshDepthShading() {
    const wantsDepth = depthShadeEnabled || mapMode === '3d';
    if (!wantsDepth || !map) return;
    if ($('depthLegend')) $('depthLegend').style.display = depthShadeEnabled ? 'block' : 'none';
    if (offlineMode) {
      if (depthShadeEnabled && $('depthLegendStatus')) $('depthLegendStatus').textContent = 'Offline mode: NOAA vector depth areas require a network connection.';
      return;
    }
    const view = mapMode === '3d' && map3d ? map3d : map;
    const raw = view.getBounds();
    const viewZoom = Number(view.getZoom ? view.getZoom() : map.getZoom());
    const lonSpan=Math.abs(raw.getEast()-raw.getWest());
    const latSpan=Math.abs(raw.getNorth()-raw.getSouth());
    const padFactor = viewZoom >= 14 ? 0.34 : (viewZoom >= 11 ? 0.22 : 0.12);
    const b={
      west:raw.getWest()-lonSpan*padFactor,
      east:raw.getEast()+lonSpan*padFactor,
      south:raw.getSouth()-latSpan*padFactor,
      north:raw.getNorth()+latSpan*padFactor
    };
    const span=Math.max(Math.abs(b.east-b.west),Math.abs(b.north-b.south));
    if (span > 6 || viewZoom < 7) {
      if (depthShadeEnabled && $('depthLegendStatus')) $('depthLegendStatus').textContent = 'Zoom in to load NOAA depth-area polygons.';
      return;
    }

    const candidates=depthSourcesForZoom(viewZoom);
    const sourceCount=viewZoom >= 14 ? Math.min(4,candidates.length) : (viewZoom >= 11 ? Math.min(3,candidates.length) : Math.min(2,candidates.length));
    const sources=candidates.slice(0,sourceCount);
    const requestId=++depthShadeRequest;
    const geom=[b.west,b.south,b.east,b.north].map(v=>Number(v).toFixed(7)).join(',');
    let lastError=null;
    const results=[];

    await Promise.all(sources.map(async (source,priority) => {
      const url=source.url+'?where=1%3D1'+
        '&geometry='+encodeURIComponent(geom)+
        '&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects'+
        '&outFields=DRVAL1,DRVAL2,DSNM&returnGeometry=true&outSR=4326&f=geojson&resultRecordCount=3000';
      try {
        const resp=await fetch(url);
        if (!resp.ok) throw new Error('HTTP '+resp.status);
        const geojson=await resp.json();
        const features=geojson && Array.isArray(geojson.features) ? geojson.features : [];
        if (features.length) results.push({source,priority,features});
      } catch(e) { lastError=e; }
    }));
    if (requestId !== depthShadeRequest) return;
    if (!results.length) {
      if (depthShadeEnabled && $('depthLegendStatus')) $('depthLegendStatus').textContent = lastError ? 'NOAA depth colors unavailable: '+(lastError.message||lastError) : 'No NOAA ENC depth-area coverage returned in this view.';
      return;
    }

    // Broadest data first, detailed data last. Duplicate geometries are discarded by a compact key.
    results.sort((a,b)=>b.priority-a.priority);
    const seen=new Set();
    const merged=[];
    results.forEach(group=>group.features.forEach((f,idx)=>{
      if (!f || !f.geometry) return;
      const pr=f.properties||{};
      const bb=geometryBounds(f.geometry);
      const key=bb ? [Number(pr.DRVAL1).toFixed(2),Number(pr.DRVAL2).toFixed(2),bb.minLat.toFixed(5),bb.minLon.toFixed(5),bb.maxLat.toFixed(5),bb.maxLon.toFixed(5)].join('|') : group.source.name+'|'+idx;
      if (seen.has(key)) return;
      seen.add(key);
      f.properties=Object.assign({},pr,{__lakenavSource:group.source.name,__lakenavPriority:group.priority});
      merged.push(f);
    }));
    const geojson={type:'FeatureCollection',features:merged};
    latestDepthGeojson=geojson;
    sync3dDepthData();

    if (depthShadeEnabled) {
      if (depthShadeLayer && map) { try { map.removeLayer(depthShadeLayer); } catch(e) {} }
      depthShadeLayer=L.geoJSON(geojson,{
        pane:'depthPane',interactive:false,
        style:feature=>{
          const props=feature&&feature.properties?feature.properties:{};
          const shallowFt=Number(props.DRVAL1)*M_TO_FT;
          const band=depthBandForFeet(shallowFt);
          return {color:'rgba(56,77,88,.24)',weight:0.38,fillColor:band.fill,fillOpacity:0.54};
        }
      }).addTo(map);
      renderDepthLabels(merged);
      if ($('depthLegendStatus')) $('depthLegendStatus').textContent = results.map(r=>r.source.name).join(' + ')+' ENC • '+merged.length+' merged depth areas • padded close-zoom coverage.';
    }
  }

'''
s=s[:start]+new_refresh+s[end:]
p.write_text(s)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.21 features' not in r:
    insert='''\n## Version 0.21 features\n\n### Better close-zoom bathymetry\n- Pads the visible 3D request area at close zoom so depth polygons are already available just beyond the screen edge.\n- Merges multiple NOAA ENC depth-area scales at higher zoom instead of replacing broader coverage with a sparse detailed layer. Broader polygons render first and more detailed chart data renders on top.\n- Raises close-zoom depth tint slightly while reducing hard boundary weight, improving continuity without hiding the aerial terrain.\n\n### More readable contour labels\n- Major depth-boundary labels use a single centered label per boundary instead of repeating text along the line.\n- Larger type and a stronger dark halo make contour labels easier to read at a pitched 3D camera angle.\n- Existing sparse depth-range numbers remain the primary easy-to-read numeric depth reference.\n'''
    pos=r.find('\n## Version 0.20 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 21/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.21.0'/" app/build.gradle
grep -q 'v0.21' app/src/main/assets/index.html
grep -q 'Better close-zoom bathymetry' README.md
printf 'LakeNav WI v0.21 close-zoom bathymetry improvements applied.\n'
