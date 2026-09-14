#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re
p=Path('app/src/main/assets/index.html')
s=p.read_text()
s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.24</span></div>', s, count=1)

# Add a native NOAA feature-data toggle to the main Layers panel. This is independent of the NOAA raster chart overlay.
row='<div class="quickLayerRow"><div class="quickLayerText">Navigation perspective<small>Forward-looking 2D view in Course Up</small></div><label class="toggleSwitch"><input type="checkbox" id="quickPerspectiveToggle"><span></span></label></div>'
if row not in s: raise SystemExit('perspective row not found')
s=s.replace(row, row+'\n      <div class="quickLayerRow"><div class="quickLayerText">NOAA navigation aids<small>Buoys, beacons, daymarks and lights on the normal map</small></div><label class="toggleSwitch"><input type="checkbox" id="quickNoaaAidsToggle"><span></span></label></div>\n      <div id="quickNoaaAidsStatus" class="muted" style="font-size:9px;line-height:1.25;padding:0 4px 7px">Loads NOAA ENC-derived feature data when zoomed into covered waters.</div>',1)

# Marker styling. Symbols intentionally sit on the normal Leaflet map instead of importing NOAA chart texture/colors.
css='''\n/* v0.24 NOAA ENC-derived navigation-aid symbols */\n.encAidIcon { background:transparent !important; border:0 !important; }\n.encAidWrap { position:relative; width:22px; height:22px; display:flex; align-items:center; justify-content:center; filter:drop-shadow(0 1px 1px rgba(0,0,0,.55)); }\n.encAidShape { width:12px; height:12px; border:2px solid rgba(255,255,255,.96); box-shadow:0 0 0 1px rgba(3,27,37,.92); background:#ffd447; }\n.encAidWrap.buoy .encAidShape { border-radius:50% 50% 46% 46%; }\n.encAidWrap.buoy .encAidShape:after { content:''; position:absolute; left:10px; top:15px; width:2px; height:5px; background:#eefcff; box-shadow:0 0 0 1px rgba(3,27,37,.55); }\n.encAidWrap.beacon .encAidShape { border-radius:2px; }\n.encAidWrap.daymark .encAidShape { transform:rotate(45deg); width:10px; height:10px; border-radius:1px; }\n.encAidWrap.light .encAidShape { width:15px; height:15px; border-radius:50%; background:radial-gradient(circle,#fff 0 20%,#ffe86a 21% 47%,rgba(255,218,71,.24) 48% 100%); border:1px solid #fff; box-shadow:0 0 0 1px rgba(3,27,37,.88),0 0 8px rgba(255,229,82,.62); }\n.encAidLabel { position:absolute; left:18px; top:1px; white-space:nowrap; font:700 9px/1.1 system-ui,sans-serif; color:#f7fdff; text-shadow:0 1px 2px #00151f,0 0 2px #00151f,0 0 4px #00151f; pointer-events:none; }\n.encAidPopup { font-size:12px; line-height:1.35; }\n.encAidPopup strong { font-size:13px; }\n'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

# Persistence and runtime state.
s=s.replace("  const STORAGE_NAV_PERSPECTIVE = 'lakenav.navperspective.v1';", "  const STORAGE_NAV_PERSPECTIVE = 'lakenav.navperspective.v1';\n  const STORAGE_NOAA_AIDS = 'lakenav.noaaaids.v1';",1)
s=s.replace("  let lastNavFollowAt = 0;", "  let lastNavFollowAt = 0;\n  let noaaAidsEnabled = localStorage.getItem(STORAGE_NOAA_AIDS) !== '0';\n  let noaaAidsLayer = null;\n  let noaaAidsTimer = null;\n  let noaaAidsRequest = 0;\n  let noaaAidsCoverage = null;\n  let noaaAidsZoomBand = null;\n  let noaaAidsLastFetch = 0;",1)

anchor='  function navigationPerspectiveActive() {'
if anchor not in s: raise SystemExit('navigation perspective function not found')
helpers=r'''  const NOAA_ENC_AID_BANDS = {
    harbour:{service:'enc_harbour',name:'Harbour',layers:[
      [1,'beacon'],[2,'beacon'],[3,'beacon'],[5,'buoy'],[6,'buoy'],[7,'buoy'],[8,'buoy'],[9,'daymark'],[11,'light'],[12,'light']
    ]},
    approach:{service:'enc_approach',name:'Approach',layers:[
      [3,'beacon'],[4,'beacon'],[5,'beacon'],[7,'buoy'],[8,'buoy'],[9,'buoy'],[10,'buoy'],[11,'daymark'],[13,'light'],[14,'light']
    ]},
    coastal:{service:'enc_coastal',name:'Coastal',layers:[
      [1,'beacon'],[2,'beacon'],[3,'beacon'],[4,'buoy'],[5,'buoy'],[6,'buoy'],[7,'buoy'],[8,'daymark'],[10,'light'],[11,'light']
    ]},
    general:{service:'enc_general',name:'General',layers:[
      [1,'beacon'],[2,'beacon'],[4,'buoy'],[5,'buoy'],[6,'buoy'],[7,'buoy'],[8,'daymark'],[10,'light']
    ]}
  };

  function noaaAidBandForZoom(z) {
    if (z >= 14) return NOAA_ENC_AID_BANDS.harbour;
    if (z >= 12) return NOAA_ENC_AID_BANDS.approach;
    if (z >= 10) return NOAA_ENC_AID_BANDS.coastal;
    return NOAA_ENC_AID_BANDS.general;
  }

  function noaaAidBroaderBand(band) {
    if (band===NOAA_ENC_AID_BANDS.harbour) return NOAA_ENC_AID_BANDS.approach;
    if (band===NOAA_ENC_AID_BANDS.approach) return NOAA_ENC_AID_BANDS.coastal;
    if (band===NOAA_ENC_AID_BANDS.coastal) return NOAA_ENC_AID_BANDS.general;
    return null;
  }

  function noaaAidColour(props) {
    const raw=String((props&&props.COLOUR)||'').trim();
    const vals=raw.split(',').map(v=>v.trim()).filter(Boolean);
    const hasRed=vals.includes('3'), hasGreen=vals.includes('4'), hasYellow=vals.includes('6');
    if (hasRed && hasGreen) return 'linear-gradient(90deg,#e53935 0 50%,#1db954 50% 100%)';
    if (hasRed) return '#e53935';
    if (hasGreen) return '#1db954';
    if (hasYellow) return '#ffd447';
    if (vals.includes('2')) return '#1d2630';
    return '#ffd447';
  }

  function noaaAidColourName(props) {
    const raw=String((props&&props.COLOUR)||'').trim();
    const mapNames={'2':'Black','3':'Red','4':'Green','6':'Yellow','1':'White'};
    if (!raw) return '';
    return raw.split(',').map(v=>mapNames[v.trim()]||v.trim()).join(' / ');
  }

  function encText(v) {
    return String(v==null?'':v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }

  function renderNoaaNavAids(features, bandName) {
    if (!map) return;
    if (!noaaAidsLayer) noaaAidsLayer=L.layerGroup().addTo(map);
    noaaAidsLayer.clearLayers();
    const zoom=map.getZoom();
    const showLabels=zoom>=13;
    features.forEach(f=>{
      if (!f || !f.geometry || f.geometry.type!=='Point' || !Array.isArray(f.geometry.coordinates)) return;
      const lon=Number(f.geometry.coordinates[0]), lat=Number(f.geometry.coordinates[1]);
      if (!Number.isFinite(lat)||!Number.isFinite(lon)) return;
      const p=f.properties||{};
      const kind=p.__kind||'buoy';
      const name=(p.OBJNAM||p.INFORM||'').toString().trim();
      const label=showLabels && name ? '<span class="encAidLabel">'+encText(name)+'</span>' : '';
      const html='<div class="encAidWrap '+kind+'"><div class="encAidShape" style="background:'+noaaAidColour(p)+'"></div>'+label+'</div>';
      const icon=L.divIcon({className:'encAidIcon',html,iconSize:[22,22],iconAnchor:[11,11]});
      const marker=L.marker([lat,lon],{icon,keyboard:false,riseOnHover:true});
      const typeLabel=kind==='buoy'?'Buoy':kind==='beacon'?'Beacon':kind==='daymark'?'Daymark':'Light';
      const parts=['<div class="encAidPopup"><strong>'+encText(name||typeLabel)+'</strong>','<div>'+typeLabel+' • NOAA ENC '+encText(bandName)+'</div>'];
      const cn=noaaAidColourName(p); if (cn) parts.push('<div>Color: '+encText(cn)+'</div>');
      if (p.SORDAT) parts.push('<div>Source date: '+encText(p.SORDAT)+'</div>');
      if (p.DSNM) parts.push('<div>ENC: '+encText(p.DSNM)+'</div>');
      if (p.INFORM && p.INFORM!==name) parts.push('<div>'+encText(p.INFORM)+'</div>');
      parts.push('<div style="margin-top:4px;font-size:10px;opacity:.72">ENC Direct to GIS feature data; informational display, not a certified navigation chart.</div></div>');
      marker.bindPopup(parts.join(''));
      marker.addTo(noaaAidsLayer);
    });
  }

  function updateNoaaAidsUi(text) {
    if ($('quickNoaaAidsToggle')) $('quickNoaaAidsToggle').checked=noaaAidsEnabled;
    if ($('quickNoaaAidsStatus') && text) $('quickNoaaAidsStatus').textContent=text;
  }

  function setNoaaNavAids(on) {
    noaaAidsEnabled=!!on;
    localStorage.setItem(STORAGE_NOAA_AIDS,noaaAidsEnabled?'1':'0');
    updateNoaaAidsUi(noaaAidsEnabled?'NOAA ENC-derived aids enabled. Zoom into covered waters to load.':'NOAA navigation aids off.');
    if (!noaaAidsEnabled) {
      if (noaaAidsLayer) noaaAidsLayer.clearLayers();
      return;
    }
    scheduleNoaaNavAidsRefresh(true);
  }

  function scheduleNoaaNavAidsRefresh(force) {
    if (!noaaAidsEnabled || offlineMode || mapMode!=='2d' || !map) return;
    clearTimeout(noaaAidsTimer);
    noaaAidsTimer=setTimeout(()=>refreshNoaaNavAids(!!force),force?80:520);
  }

  async function queryNoaaAidBand(band,bounds,requestId) {
    const geom=[bounds.west,bounds.south,bounds.east,bounds.north].map(v=>Number(v).toFixed(7)).join(',');
    const batches=await Promise.all(band.layers.map(async ([layerId,kind])=>{
      if (requestId!==noaaAidsRequest) return [];
      const base='https://encdirect.noaa.gov/arcgis/rest/services/encdirect/'+band.service+'/MapServer/'+layerId+'/query';
      const url=base+'?where=1%3D1&geometry='+encodeURIComponent(geom)+'&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=*&returnGeometry=true&outSR=4326&f=geojson&resultRecordCount=1000';
      try {
        const resp=await fetch(url);
        if (!resp.ok) return [];
        const gj=await resp.json();
        const fs=gj&&Array.isArray(gj.features)?gj.features:[];
        fs.forEach(f=>{ f.properties=Object.assign({},f.properties||{},{__kind:kind,__band:band.name}); });
        return fs;
      } catch(e) { return []; }
    }));
    return batches.flat();
  }

  async function refreshNoaaNavAids(force) {
    if (!noaaAidsEnabled || offlineMode || mapMode!=='2d' || !map) return;
    const z=Number(map.getZoom());
    if (z<9) { updateNoaaAidsUi('Zoom in to show NOAA navigation aids.'); if(noaaAidsLayer) noaaAidsLayer.clearLayers(); return; }
    const raw=map.getBounds();
    const lonSpan=Math.abs(raw.getEast()-raw.getWest()), latSpan=Math.abs(raw.getNorth()-raw.getSouth());
    if (Math.max(lonSpan,latSpan)>3.0) { updateNoaaAidsUi('Zoom in to show NOAA navigation aids.'); return; }
    const pad=z>=14?0.30:(z>=12?0.22:0.16);
    const b={west:raw.getWest()-lonSpan*pad,east:raw.getEast()+lonSpan*pad,south:raw.getSouth()-latSpan*pad,north:raw.getNorth()+latSpan*pad};
    const band=noaaAidBandForZoom(z);
    const bandKey=band.service;
    const inside=noaaAidsCoverage && raw.getWest()>=noaaAidsCoverage.west && raw.getEast()<=noaaAidsCoverage.east && raw.getSouth()>=noaaAidsCoverage.south && raw.getNorth()<=noaaAidsCoverage.north;
    if (!force && inside && noaaAidsZoomBand===bandKey && Date.now()-noaaAidsLastFetch<4*60*1000) return;
    const requestId=++noaaAidsRequest;
    updateNoaaAidsUi('Loading NOAA '+band.name+' navigation aids…');
    let features=await queryNoaaAidBand(band,b,requestId);
    let usedBand=band;
    if (requestId!==noaaAidsRequest) return;
    if (!features.length) {
      const broader=noaaAidBroaderBand(band);
      if (broader) { features=await queryNoaaAidBand(broader,b,requestId); usedBand=broader; }
    }
    if (requestId!==noaaAidsRequest) return;
    const seen=new Set(), clean=[];
    features.forEach(f=>{
      if (!f||!f.geometry||!Array.isArray(f.geometry.coordinates)) return;
      const p=f.properties||{}, c=f.geometry.coordinates;
      const key=[Number(c[0]).toFixed(5),Number(c[1]).toFixed(5),p.__kind||'',String(p.OBJNAM||''),String(p.COLOUR||'')].join('|');
      if (seen.has(key)) return; seen.add(key); clean.push(f);
    });
    noaaAidsCoverage=b; noaaAidsZoomBand=bandKey; noaaAidsLastFetch=Date.now();
    renderNoaaNavAids(clean,usedBand.name);
    updateNoaaAidsUi(clean.length ? clean.length+' NOAA '+usedBand.name+' aids on the normal map.' : 'No NOAA ENC navigation aids found in this view.');
  }

'''
s=s.replace(anchor,helpers+anchor,1)

# Refresh on settled map movement, independently of the raster chart overlay.
move="    map.on('moveend', scheduleDepthShadeRefresh);"
if move not in s: raise SystemExit('moveend anchor missing')
s=s.replace(move,move+"\n    map.on('moveend', () => scheduleNoaaNavAidsRefresh(false));",1)

# Toggle wiring and startup.
wire="    $('quickPerspectiveToggle').addEventListener('change', e => setNavigationPerspective(e.target.checked));"
if wire not in s: raise SystemExit('perspective toggle wire missing')
s=s.replace(wire,wire+"\n    $('quickNoaaAidsToggle').addEventListener('change', e => setNoaaNavAids(e.target.checked));",1)
startup="    updateNavigationPerspectiveUi();"
# Use the last startup occurrence to avoid altering helper functions.
pos=s.rfind(startup)
if pos<0: raise SystemExit('startup perspective ui call missing')
pos_end=pos+len(startup)
s=s[:pos_end]+"\n    updateNoaaAidsUi(noaaAidsEnabled?'NOAA ENC-derived aids enabled. Zoom into covered waters to load.':'NOAA navigation aids off.');\n    if (noaaAidsEnabled) setTimeout(()=>scheduleNoaaNavAidsRefresh(true),900);"+s[pos_end:]

p.write_text(s)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.24 features' not in r:
    insert='''\n## Version 0.24 features\n\n### NOAA feature data on the normal LakeNav map\n- Adds a separate `NOAA navigation aids` layer that displays ENC-derived buoys, lateral/safe-water/special-purpose markers, beacons, daymarks, and lights directly on LakeNav's normal 2D basemap. The NOAA chart raster/texture does not need to be enabled.\n- Uses NOAA ENC Direct to GIS feature services and automatically selects Harbour, Approach, Coastal, or General scale-band data based on map zoom. If a detailed scale returns no features, LakeNav falls back one scale band.\n- Lateral-aid colors are rendered from NOAA `COLOUR` attributes, including red, green, yellow, black, and split red/green. Named aids receive labels at closer zoom levels.\n- Tapping an aid opens its NOAA-derived name/type, color, source date, ENC identifier, and informational text when available.\n- Requests are debounced, padded beyond the screen edge, cached for four minutes while the current view remains inside the fetched area, and only run when the map is sufficiently zoomed in.\n- The feature layer is independent of the older NOAA raster chart overlay and independent of OpenSeaMap seamark tiles, allowing LakeNav's own colors and depth styling to stay visible.\n- NOAA ENC Direct to GIS is derived from official NOAA ENCs but is not certified for navigation; LakeNav displays that distinction in aid popups.\n'''
    pos=r.find('\n## Version 0.23 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 24/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.24.0'/" app/build.gradle
grep -q 'v0.24' app/src/main/assets/index.html
grep -q 'quickNoaaAidsToggle' app/src/main/assets/index.html
grep -q 'NOAA feature data on the normal LakeNav map' README.md
printf 'LakeNav WI v0.24 NOAA navigation-aid feature layer applied.\n'
