#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p = Path('app/src/main/assets/index.html')
s = p.read_text()

# Version badge.
s = re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.20</span></div>', s, count=1)

# MapLibre text labels need a glyph endpoint. It is only used when online depth labels are present.
s = s.replace("return {version:8, sources:{", "return {version:8,glyphs:'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf', sources:{")

# Make 3D refresh depth data independently of the 2D toggle and refresh after initial load.
s = s.replace("add3dNavLayers(); sync3dNavigationData(); sync3dDepthData(); sync3dBoat();", "add3dNavLayers(); sync3dNavigationData(); sync3dDepthData(); sync3dBoat(); scheduleDepthShadeRefresh();", 1)
s = re.sub(r"map3d\.on\('moveend', \(\) => \{[^\n]*scheduleDepthShadeRefresh\(\);[^\n]*\}\);", "map3d.on('moveend', () => { scheduleDepthShadeRefresh(); });", s, count=1)

start = s.index('  function add3dNavLayers() {')
end = s.index('  function sync3dNavigationData() {', start)
new_block = r'''  function depth3dColorExpression() {
    return ['interpolate',['linear'],['to-number',['get','DRVAL1'],0],
      0.0,'#d98b78',
      1.5,'#e7a56f',
      3.0,'#e3c979',
      4.5,'#bdd3a2',
      6.0,'#83c9d0',
      9.0,'#66b6ca',
      12.0,'#4b95b8',
      18.0,'#33789f'];
  }

  function depth3dCollections(data) {
    const pointFeatures=[];
    const contourFeatures=[];
    if (!data || !Array.isArray(data.features)) return {points:emptyFeatureCollection(),contours:emptyFeatureCollection()};
    const zoom = map3d && map3d.getZoom ? Number(map3d.getZoom()) : 12;
    const minArea = zoom >= 14 ? 0.0000012 : (zoom >= 12 ? 0.000006 : 0.00003);
    const maxPoints = zoom >= 14 ? 54 : (zoom >= 12 ? 30 : 16);
    let pointCount=0;
    const majorFt=[5,6,10,12,15,20,30,40,50,60,80,100];
    const closeMajor = ft => majorFt.find(v => Math.abs(v-ft) <= Math.max(1.5, v*0.08));
    const ringsFromGeometry = g => {
      if (!g || !g.coordinates) return [];
      if (g.type==='Polygon') return g.coordinates.length ? [g.coordinates[0]] : [];
      if (g.type==='MultiPolygon') return g.coordinates.map(poly => poly && poly.length ? poly[0] : null).filter(Boolean);
      return [];
    };
    data.features.forEach((feature,idx) => {
      const props=feature && feature.properties ? feature.properties : {};
      const loM=Number(props.DRVAL1), hiM=Number(props.DRVAL2);
      if (!Number.isFinite(loM)) return;
      const loFt=loM*M_TO_FT;
      const hiFt=Number.isFinite(hiM) ? hiM*M_TO_FT : NaN;
      const b=geometryBounds(feature.geometry);
      if (!b) return;
      const size=Math.abs((b.maxLat-b.minLat)*(b.maxLon-b.minLon));
      if (pointCount < maxPoints && size >= minArea) {
        const label = Number.isFinite(hiFt) && hiFt > loFt + 0.8
          ? Math.round(loFt)+'–'+Math.round(hiFt)+' ft'
          : Math.round(loFt)+'+ ft';
        pointFeatures.push({type:'Feature',properties:{label,depthFt:loFt},geometry:{type:'Point',coordinates:[(b.minLon+b.maxLon)/2,(b.minLat+b.maxLat)/2]}});
        pointCount++;
      }
      const major=closeMajor(loFt);
      if (!major) return;
      ringsFromGeometry(feature.geometry).forEach((ring,ri) => {
        if (!Array.isArray(ring) || ring.length < 3) return;
        contourFeatures.push({type:'Feature',properties:{label:major+' ft',depthFt:major,key:idx+'-'+ri},geometry:{type:'LineString',coordinates:ring}});
      });
    });
    return {points:{type:'FeatureCollection',features:pointFeatures},contours:{type:'FeatureCollection',features:contourFeatures}};
  }

  function add3dNavLayers() {
    if (!map3d || !map3dLoaded) return;
    const defs = [
      ['lakenav-track', {type:'geojson',data:emptyFeatureCollection()}],
      ['lakenav-route', {type:'geojson',data:emptyFeatureCollection()}],
      ['lakenav-nav', {type:'geojson',data:emptyFeatureCollection()}],
      ['lakenav-points', {type:'geojson',data:emptyFeatureCollection()}],
      ['lakenav-depth3d', {type:'geojson',data:emptyFeatureCollection()}],
      ['lakenav-depth3d-labels', {type:'geojson',data:emptyFeatureCollection()}],
      ['lakenav-depth3d-contours', {type:'geojson',data:emptyFeatureCollection()}]
    ];
    defs.forEach(([id,spec]) => { if (!map3d.getSource(id)) map3d.addSource(id,spec); });
    if (!map3d.getLayer('lakenav-track-line')) map3d.addLayer({id:'lakenav-track-line',type:'line',source:'lakenav-track',paint:{'line-color':'#ff493c','line-width':4,'line-opacity':.9}});
    if (!map3d.getLayer('lakenav-route-line')) map3d.addLayer({id:'lakenav-route-line',type:'line',source:'lakenav-route',paint:{'line-color':'#ff38b8','line-width':6,'line-opacity':.94}});
    if (!map3d.getLayer('lakenav-nav-line')) map3d.addLayer({id:'lakenav-nav-line',type:'line',source:'lakenav-nav',paint:{'line-color':'#ffd447','line-width':5,'line-dasharray':[2,1.5],'line-opacity':.95}});

    if (!map3d.getLayer('lakenav-depth3d-soft-edge')) map3d.addLayer({
      id:'lakenav-depth3d-soft-edge',type:'line',source:'lakenav-depth3d',
      paint:{
        'line-color':'rgba(111,190,203,.38)',
        'line-width':['interpolate',['linear'],['zoom'],8,8,11,13,14,22,16,28],
        'line-blur':['interpolate',['linear'],['zoom'],8,5,12,8,16,11],
        'line-opacity':0.40
      }
    });
    if (!map3d.getLayer('lakenav-depth3d-fill')) map3d.addLayer({
      id:'lakenav-depth3d-fill',type:'fill',source:'lakenav-depth3d',
      paint:{
        'fill-color':depth3dColorExpression(),
        'fill-opacity':['interpolate',['linear'],['zoom'],7,0.56,11,0.62,15,0.68],
        'fill-antialias':true,
        'fill-outline-color':'rgba(207,240,244,.20)'
      }
    });
    if (!map3d.getLayer('lakenav-depth3d-lines')) map3d.addLayer({
      id:'lakenav-depth3d-lines',type:'line',source:'lakenav-depth3d',
      paint:{
        'line-color':'rgba(215,246,247,.42)',
        'line-width':['interpolate',['linear'],['zoom'],8,0.35,12,0.65,16,1.05],
        'line-opacity':0.48,
        'line-blur':0.45
      }
    });
    if (!map3d.getLayer('lakenav-depth3d-contour-labels')) map3d.addLayer({
      id:'lakenav-depth3d-contour-labels',type:'symbol',source:'lakenav-depth3d-contours',minzoom:11.5,
      layout:{
        'symbol-placement':'line','symbol-spacing':360,
        'text-field':['get','label'],'text-size':['interpolate',['linear'],['zoom'],11.5,10,15,13],
        'text-font':['Open Sans Regular','Arial Unicode MS Regular'],
        'text-keep-upright':true,'text-allow-overlap':false,'text-ignore-placement':false,
        'text-padding':6
      },
      paint:{'text-color':'rgba(239,253,255,.88)','text-halo-color':'rgba(7,42,55,.78)','text-halo-width':1.5,'text-halo-blur':0.7}
    });
    if (!map3d.getLayer('lakenav-depth3d-number-labels')) map3d.addLayer({
      id:'lakenav-depth3d-number-labels',type:'symbol',source:'lakenav-depth3d-labels',minzoom:10.3,
      layout:{
        'text-field':['get','label'],'text-size':['interpolate',['linear'],['zoom'],10.3,10,13,12,16,14],
        'text-font':['Open Sans Regular','Arial Unicode MS Regular'],
        'text-allow-overlap':false,'text-ignore-placement':false,'text-padding':10
      },
      paint:{'text-color':'#f2fdff','text-halo-color':'rgba(5,37,50,.82)','text-halo-width':1.8,'text-halo-blur':0.7}
    });
    if (!map3d.getLayer('lakenav-point-circles')) map3d.addLayer({id:'lakenav-point-circles',type:'circle',source:'lakenav-points',paint:{'circle-radius':['case',['==',['get','kind'],'route'],6,5],'circle-color':['case',['==',['get','kind'],'route'],'#ff38b8','#ffffff'],'circle-stroke-color':['case',['==',['get','kind'],'mob'],'#ff453a','#07354a'],'circle-stroke-width':2.5}});
  }

  function sync3dDepthData() {
    if (!map3d || !map3dLoaded) return;
    const data=latestDepthGeojson && Array.isArray(latestDepthGeojson.features) ? latestDepthGeojson : emptyFeatureCollection();
    const src=map3d.getSource('lakenav-depth3d');
    if (src && src.setData) { try { src.setData(data); } catch(e) {} }
    const derived=depth3dCollections(data);
    const labelSrc=map3d.getSource('lakenav-depth3d-labels');
    const contourSrc=map3d.getSource('lakenav-depth3d-contours');
    if (labelSrc && labelSrc.setData) { try { labelSrc.setData(derived.points); } catch(e) {} }
    if (contourSrc && contourSrc.setData) { try { contourSrc.setData(derived.contours); } catch(e) {} }
  }

'''
s = s[:start] + new_block + s[end:]

start = s.index('  function scheduleDepthShadeRefresh() {')
end = s.index('  function toggleDepthShading(on) {', start)
new_refresh = r'''  function scheduleDepthShadeRefresh() {
    const wantsDepth = depthShadeEnabled || mapMode === '3d';
    if (!wantsDepth) return;
    if (depthShadeTimer) clearTimeout(depthShadeTimer);
    depthShadeTimer = setTimeout(refreshDepthShading, mapMode === '3d' ? 360 : 260);
  }

  async function refreshDepthShading() {
    const wantsDepth = depthShadeEnabled || mapMode === '3d';
    if (!wantsDepth || !map) return;
    if ($('depthLegend')) $('depthLegend').style.display = depthShadeEnabled ? 'block' : 'none';
    if (offlineMode) {
      if (depthShadeEnabled && $('depthLegendStatus')) $('depthLegendStatus').textContent = 'Offline mode: NOAA vector depth areas require a network connection.';
      return;
    }
    const view = mapMode === '3d' && map3d ? map3d : map;
    const b = view.getBounds();
    const viewZoom = Number(view.getZoom ? view.getZoom() : map.getZoom());
    const span = Math.max(Math.abs(b.getEast() - b.getWest()), Math.abs(b.getNorth() - b.getSouth()));
    if (span > 6 || viewZoom < 7) {
      if (depthShadeEnabled && $('depthLegendStatus')) $('depthLegendStatus').textContent = 'Zoom in to load NOAA depth-area polygons.';
      return;
    }

    const sources = depthSourcesForZoom(viewZoom);
    const requestId = ++depthShadeRequest;
    const geom = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()].map(v => Number(v).toFixed(7)).join(',');
    let lastError = null;

    for (let i = 0; i < sources.length; i++) {
      const source = sources[i];
      if (requestId !== depthShadeRequest) return;
      if (depthShadeEnabled && $('depthLegendStatus')) $('depthLegendStatus').textContent = 'Loading ' + source.name + ' ENC depth areas…';
      const url = source.url + '?where=1%3D1' +
        '&geometry=' + encodeURIComponent(geom) +
        '&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects' +
        '&outFields=DRVAL1,DRVAL2,DSNM&returnGeometry=true&outSR=4326&f=geojson&resultRecordCount=1500';
      try {
        const resp = await fetch(url);
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        const geojson = await resp.json();
        if (requestId !== depthShadeRequest) return;
        const features = geojson && Array.isArray(geojson.features) ? geojson.features : [];
        if (!features.length) continue;

        latestDepthGeojson = geojson;
        sync3dDepthData();

        if (depthShadeEnabled) {
          if (depthShadeLayer && map) { try { map.removeLayer(depthShadeLayer); } catch(e) {} }
          depthShadeLayer = L.geoJSON(geojson, {
            pane: 'depthPane',interactive:false,
            style: feature => {
              const props=feature && feature.properties ? feature.properties : {};
              const shallowFt=Number(props.DRVAL1)*M_TO_FT;
              const band=depthBandForFeet(shallowFt);
              return {color:'rgba(56,77,88,.30)',weight:0.45,fillColor:band.fill,fillOpacity:0.54};
            }
          }).addTo(map);
          renderDepthLabels(features);
          if ($('depthLegendStatus')) $('depthLegendStatus').textContent = source.name + ' ENC • ' + features.length + ' depth areas • 3D blends these bands and labels charted depth ranges.';
        }
        return;
      } catch (e) { lastError=e; }
    }

    if (requestId !== depthShadeRequest) return;
    if (depthShadeEnabled && $('depthLegendStatus')) {
      $('depthLegendStatus').textContent = lastError
        ? 'NOAA depth colors unavailable: ' + (lastError.message || lastError)
        : 'No NOAA ENC depth-area coverage returned in this view.';
    }
  }

'''
s = s[:start] + new_refresh + s[end:]
p.write_text(s)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.20 features' not in r:
    insert = '''\n## Version 0.20 features\n\n### Smoother 3D bathymetry\n- 3D depth bands now use a continuous color ramp plus a soft blurred boundary halo to reduce the blocky polygon-edge look.\n- Existing charted depth data stays visible while replacement viewport data loads, avoiding blank flashes.\n- 3D depth coloring remains automatic wherever NOAA ENC depth-area coverage exists.\n\n### 3D depth numbers and contour labels\n- Adds sparse zoom-aware depth-range labels such as `6–12 ft` inside larger charted depth areas. These are depth-area ranges, not fabricated soundings.\n- Adds labels along selected major depth-area boundaries to provide a contour-like chartplotter readout without inventing lake-bottom geometry.\n- Label density increases as the user zooms in and declutters automatically through MapLibre symbol collision handling.\n'''
    pos=r.find('\n## Version 0.19 features')
    if pos < 0: pos=r.find('\n## Version 0.18 features')
    if pos < 0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 20/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.20.0'/" app/build.gradle
grep -q 'v0.20' app/src/main/assets/index.html
grep -q 'Smoother 3D bathymetry' README.md
printf 'LakeNav WI v0.20 smoother 3D bathymetry and labels applied.\n'
