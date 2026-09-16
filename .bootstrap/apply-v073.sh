#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
python3 - <<'PY'
from pathlib import Path
p=Path('app/src/main/assets/index.html')
h=p.read_text()
def rep(old,new,count=1):
    global h
    if old not in h:
        raise SystemExit('v0.73 marker missing: '+old[:120])
    h=h.replace(old,new,count)
rep('<span class="versionPill">v0.72</span>','<span class="versionPill">v0.73</span>')
marker='#selectedLakeChip strong { display: inline-block; max-width: 190px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; vertical-align: bottom; }'
css='''
#lakeDiscoveryCard { position:absolute; z-index:775; left:50%; bottom:14px; width:min(520px,calc(100% - 24px)); transform:translateX(-50%); display:none; background:rgba(250,253,255,.97); border:1px solid rgba(255,255,255,.90); border-radius:22px; box-shadow:0 18px 42px rgba(3,37,55,.26); backdrop-filter:blur(22px) saturate(150%); -webkit-backdrop-filter:blur(22px) saturate(150%); padding:12px 13px 11px; color:#153949; }
#lakeDiscoveryCard.open { display:block; animation:lakeDiscoveryIn .18s cubic-bezier(.22,.61,.36,1); }
@keyframes lakeDiscoveryIn { from { opacity:0; transform:translateX(-50%) translateY(10px) scale(.98); } to { opacity:1; transform:translateX(-50%) translateY(0) scale(1); } }
.lakeDiscoveryTop { display:flex; align-items:flex-start; gap:9px; }
.lakeDiscoveryCopy { min-width:0; flex:1; }
.lakeDiscoveryEyebrow { display:block; color:#16708f; font-size:8px; font-weight:950; letter-spacing:.09em; text-transform:uppercase; margin-bottom:2px; }
#lakeDiscoveryName { display:block; font-size:17px; line-height:1.12; letter-spacing:-.025em; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
#lakeDiscoveryMeta { margin-top:3px; color:#667d89; font-size:10px; line-height:1.3; }
#lakeDiscoveryClose { flex:0 0 auto; width:30px; height:30px; border:0; border-radius:50%; background:#e9f2f5; color:#244b5c; font-size:17px; font-weight:800; }
.lakeDiscoveryBadges { display:flex; flex-wrap:wrap; gap:5px; margin-top:9px; }
.lakeDiscoveryBadge { display:inline-flex; align-items:center; min-height:23px; padding:4px 8px; border-radius:999px; background:#e8f4f8; color:#175c75; border:1px solid rgba(29,112,143,.10); font-size:8px; font-weight:900; letter-spacing:.045em; text-transform:uppercase; }
.lakeDiscoveryBadge.good { background:#e4f7f0; color:#17664c; }
.lakeDiscoveryBadge.warn { background:#fff1d9; color:#865214; }
.lakeDiscoveryBadge.mutedBadge { background:#eef2f4; color:#61737c; }
.lakeDiscoveryActions { display:grid; grid-template-columns:1fr auto; gap:8px; margin-top:10px; }
#lakeDiscoveryExploreBtn { min-height:40px; border:0; border-radius:14px; background:linear-gradient(145deg,#0c88bc,#096a98); color:#fff; font-size:11px; font-weight:900; letter-spacing:.025em; }
#lakeDiscoveryLaunchBtn { min-height:40px; border:1px solid #c7dbe4; border-radius:14px; padding:0 12px; background:#f4f9fb; color:#1c566e; font-size:10px; font-weight:850; }
#lakeDiscoveryLoading { display:none; margin-top:7px; font-size:9px; color:#6c818b; }
#lakeDiscoveryCard.loading #lakeDiscoveryLoading { display:block; }
.selectedLakeGlowPath { filter:drop-shadow(0 0 3px rgba(55,214,235,.90)) drop-shadow(0 0 7px rgba(18,139,189,.46)); }
#mapWrap.navStatePlanning #lakeDiscoveryCard, #mapWrap.navigating #lakeDiscoveryCard { display:none!important; }
.lakeDiscoveryHero { padding:14px; border-radius:20px; background:linear-gradient(145deg,rgba(16,119,157,.13),rgba(30,194,207,.06)); border:1px solid rgba(43,143,174,.14); }
.lakeDiscoveryHero h3 { margin:2px 0 4px; font-size:22px; letter-spacing:-.035em; }
.lakeDiscoverySheetMeta { color:var(--muted); font-size:11px; }
.lakeDiscoveryGrid { display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-top:12px; }
.lakeDiscoveryStat { padding:10px 11px; border-radius:15px; background:#f3f8fa; border:1px solid #dfebf0; }
.lakeDiscoveryStat span { display:block; color:var(--muted); font-size:8px; font-weight:850; letter-spacing:.06em; text-transform:uppercase; }
.lakeDiscoveryStat strong { display:block; margin-top:3px; color:#173b4b; font-size:14px; }
.lakeDiscoveryDataRow { display:flex; flex-wrap:wrap; gap:6px; margin-top:10px; }
'''
rep(marker,marker+css)
marker='html.darkMode body .map-chip { background:rgba(8,31,44,.93); color:#e9f5f8; border:1px solid rgba(111,190,218,.16); }'
dark='''
html.darkMode body #lakeDiscoveryCard { background:rgba(9,31,43,.97); color:#eaf6f8; border-color:rgba(119,196,221,.18); box-shadow:0 18px 44px rgba(0,0,0,.42); }
html.darkMode body #lakeDiscoveryMeta, html.darkMode body #lakeDiscoveryLoading { color:#9fb5bf; }
html.darkMode body #lakeDiscoveryClose { background:#173b4a; color:#dff4f8; }
html.darkMode body #lakeDiscoveryLaunchBtn { background:#123440; color:#d9f0f5; border-color:#2b5362; }
html.darkMode body .lakeDiscoveryBadge { background:#153b4a; color:#bfeefa; border-color:#285566; }
html.darkMode body .lakeDiscoveryBadge.good { background:#153f37; color:#b9efdd; }
html.darkMode body .lakeDiscoveryBadge.warn { background:#4a3820; color:#ffe0a3; }
html.darkMode body .lakeDiscoveryBadge.mutedBadge { background:#243841; color:#b3c6cd; }
html.darkMode body .lakeDiscoveryHero { background:linear-gradient(145deg,rgba(22,112,144,.20),rgba(17,87,109,.10)); border-color:#294c5b; }
html.darkMode body .lakeDiscoveryStat { background:#102f3c; border-color:#244957; }
html.darkMode body .lakeDiscoveryStat strong { color:#e6f5f8; }
'''
rep(marker,marker+dark)
marker='    <div id="selectedLakeChip" class="map-chip">Lake: <strong id="selectedLakeChipName">--</strong></div>'
card='''
    <div id="lakeDiscoveryCard" role="region" aria-label="Wisconsin lake discovery">
      <div class="lakeDiscoveryTop">
        <div class="lakeDiscoveryCopy"><span class="lakeDiscoveryEyebrow">Wisconsin lake</span><strong id="lakeDiscoveryName">--</strong><div id="lakeDiscoveryMeta">Tap a lake to identify it.</div></div>
        <button id="lakeDiscoveryClose" type="button" aria-label="Close lake discovery">×</button>
      </div>
      <div class="lakeDiscoveryBadges"><span class="lakeDiscoveryBadge mutedBadge" id="lakeDiscoveryDepthBadge">DEPTH • CHECKING</span><span class="lakeDiscoveryBadge" id="lakeDiscoverySourceBadge">DNR HYDRO</span></div>
      <div id="lakeDiscoveryLoading">Loading Wisconsin DNR lake information…</div>
      <div class="lakeDiscoveryActions"><button id="lakeDiscoveryExploreBtn" type="button">EXPLORE LAKE</button><button id="lakeDiscoveryLaunchBtn" type="button">LAUNCH</button></div>
    </div>'''
rep(marker,marker+card)
marker='<div class="sheetBackdrop" id="bathymetrySheet">'
sheet='''<div class="sheetBackdrop" id="lakeDiscoverySheet">
  <div class="sheet">
    <div class="sheetHeader"><h2>Lake discovery</h2><button class="closeBtn" data-close="lakeDiscoverySheet">x</button></div>
    <div class="lakeDiscoveryHero">
      <span class="lakeDiscoveryEyebrow">Wisconsin DNR waterbody</span>
      <h3 id="lakeDiscoverySheetTitle">Selected lake</h3>
      <div class="lakeDiscoverySheetMeta" id="lakeDiscoverySheetMeta">--</div>
      <div class="lakeDiscoveryDataRow"><span class="lakeDiscoveryBadge mutedBadge" id="lakeDiscoverySheetDepthBadge">DEPTH • CHECKING</span><span class="lakeDiscoveryBadge" id="lakeDiscoverySheetSourceBadge">DNR HYDRO</span></div>
    </div>
    <div class="lakeDiscoveryGrid">
      <div class="lakeDiscoveryStat"><span>County</span><strong id="lakeDiscoveryCounty">--</strong></div>
      <div class="lakeDiscoveryStat"><span>Surface area</span><strong id="lakeDiscoveryAcres">--</strong></div>
      <div class="lakeDiscoveryStat"><span>WBIC</span><strong id="lakeDiscoveryWbic">--</strong></div>
      <div class="lakeDiscoveryStat"><span>Reported max depth</span><strong id="lakeDiscoveryMaxDepth">--</strong></div>
    </div>
    <div class="btnRow" style="margin-top:12px">
      <button class="btn" id="lakeDiscoverySheetLaunchBtn">Navigate to launch</button>
      <button class="btn secondary" id="lakeDiscoverySheetBathyBtn">Bathymetry</button>
      <button class="btn secondary" id="lakeDiscoverySheetOfflineBtn">Save offline</button>
      <button class="btn secondary" id="lakeDiscoverySheetDnrBtn">DNR details</button>
    </div>
    <div id="lakeDiscoverySheetStatus" class="muted" style="margin-top:10px">Tap any Wisconsin lake on the map to identify it. LakeNav uses Wisconsin DNR hydrography and reports only data it can verify.</div>
  </div>
</div>

'''
rep(marker,sheet+marker)
rep('  let selectedLake = null;\n  let selectedLakeLayer = null;','  let selectedLake = null;\n  let selectedLakeLayer = null;\n  let lakeDiscoveryRequestId = 0;')
old='''    map.on('click', function (e) {
      if (routeDrawMode) {
        if (routeDrawTapContinue) addDrawRoutePoint(e.latlng.lat, e.latlng.lng, false);
        return;
      }
      if (!addMode) return;
      addMode = false;
      $('tapChip').style.display = 'none';
      addWaypointAt(e.latlng.lat, e.latlng.lng, 'Waypoint');
    });'''
new='''    map.on('click', function (e) {
      if (routeDrawMode) {
        if (routeDrawTapContinue) addDrawRoutePoint(e.latlng.lat, e.latlng.lng, false);
        return;
      }
      if (addMode) {
        addMode = false;
        $('tapChip').style.display = 'none';
        addWaypointAt(e.latlng.lat, e.latlng.lng, 'Waypoint');
        return;
      }
      discoverLakeAt(e.latlng.lat, e.latlng.lng);
    });'''
rep(old,new)
rep('    addMode = true;\n    closeSheets();','    addMode = true;\n    setLakeDiscoveryCardVisible(false);\n    closeSheets();')
rep('    routeDrawMode = true;\n    navFollowMode=false;','    routeDrawMode = true;\n    setLakeDiscoveryCardVisible(false);\n    navFollowMode=false;')
old="""    const refBtn=$('depthReferenceBtn');
    if (refBtn) refBtn.style.display=(state==='reference'&&selectedLake)?'block':'none';
  }"""
new="""    const refBtn=$('depthReferenceBtn');
    if (refBtn) refBtn.style.display=(state==='reference'&&selectedLake)?'block':'none';
    if (selectedLake) {
      selectedLake.depthState=state;
      selectedLake.depthStateLabel=label||'';
      updateLakeDiscoveryUi();
    }
  }"""
rep(old,new)
marker="""  function dnrLakeQueryBase() {
    return 'https://dnrmaps.wi.gov/arcgis/rest/services/ER_Biotics/ER_Biotics_WGS84_Hydro/MapServer/0/query?';
  }
"""
funcs=r'''

  function dnrCountyQueryBase() {
    return 'https://dnrmaps.wi.gov/arcgis/rest/services/ER_Biotics/ER_Biotics_WGS84_County_TRS_MCDs/MapServer/0/query?';
  }

  function setLakeDiscoveryCardVisible(on) {
    const card=$('lakeDiscoveryCard');
    if (!card) return;
    card.classList.toggle('open',!!on);
    if (!on) card.classList.remove('loading');
  }

  function formatLakeAcres(value) {
    const n=Number(value);
    if (!Number.isFinite(n) || n<=0) return 'Not reported';
    if (n<10) return n.toFixed(1)+' acres';
    return Math.round(n).toLocaleString()+' acres';
  }

  function lakeDiscoveryDepthInfo() {
    if (!selectedLake) return {text:'DEPTH • CHECKING',cls:'mutedBadge'};
    if (selectedLake.depthState==='available') return {text:'VERIFIED DEPTH',cls:'good'};
    if (selectedLake.detail && selectedLake.detail.contourUrl) return {text:'DNR DEPTH REFERENCE',cls:'warn'};
    if (selectedLake.depthState==='fallback') return {text:'NO VERIFIED DEPTH',cls:'mutedBadge'};
    return {text:'DEPTH • CHECKING',cls:'mutedBadge'};
  }

  function applyDiscoveryBadge(el,info) {
    if (!el) return;
    el.textContent=info.text;
    el.className='lakeDiscoveryBadge '+(info.cls||'');
  }

  function updateLakeDiscoveryUi() {
    if (!selectedLake) return;
    const depth=lakeDiscoveryDepthInfo();
    const acres=formatLakeAcres(selectedLake.acres);
    const county=selectedLake.county ? selectedLake.county+' County' : 'County checking…';
    const wbic=selectedLake.wbic ? String(selectedLake.wbic) : 'Not assigned';
    const maxDepth=selectedLake.detail && Number.isFinite(Number(selectedLake.detail.maxDepthFt)) ? Math.round(Number(selectedLake.detail.maxDepthFt))+' ft' : 'Not reported';
    const meta=[county,acres].filter(Boolean).join(' • ');
    if ($('lakeDiscoveryName')) $('lakeDiscoveryName').textContent=selectedLake.name||'Unnamed Lake';
    if ($('lakeDiscoveryMeta')) $('lakeDiscoveryMeta').textContent=meta;
    applyDiscoveryBadge($('lakeDiscoveryDepthBadge'),depth);
    applyDiscoveryBadge($('lakeDiscoverySheetDepthBadge'),depth);
    if ($('lakeDiscoverySourceBadge')) $('lakeDiscoverySourceBadge').textContent=selectedLake.wbic?'DNR • WBIC MATCH':'DNR • HYDRO ONLY';
    if ($('lakeDiscoverySheetSourceBadge')) $('lakeDiscoverySheetSourceBadge').textContent=selectedLake.wbic?'DNR • WBIC MATCH':'DNR • HYDRO ONLY';
    if ($('lakeDiscoverySheetTitle')) $('lakeDiscoverySheetTitle').textContent=selectedLake.name||'Unnamed Lake';
    if ($('lakeDiscoverySheetMeta')) $('lakeDiscoverySheetMeta').textContent=meta;
    if ($('lakeDiscoveryCounty')) $('lakeDiscoveryCounty').textContent=selectedLake.county ? selectedLake.county+' County' : 'Checking…';
    if ($('lakeDiscoveryAcres')) $('lakeDiscoveryAcres').textContent=acres;
    if ($('lakeDiscoveryWbic')) $('lakeDiscoveryWbic').textContent=wbic;
    if ($('lakeDiscoveryMaxDepth')) $('lakeDiscoveryMaxDepth').textContent=maxDepth;
    const hasWbic=!!selectedLake.wbic;
    if ($('lakeDiscoveryExploreBtn')) $('lakeDiscoveryExploreBtn').disabled=false;
    if ($('lakeDiscoveryLaunchBtn')) $('lakeDiscoveryLaunchBtn').disabled=false;
    ['lakeDiscoverySheetBathyBtn','lakeDiscoverySheetOfflineBtn','lakeDiscoverySheetDnrBtn'].forEach(id=>{ const el=$(id); if(el) el.disabled=!hasWbic; });
    if ($('lakeDiscoverySheetStatus')) {
      $('lakeDiscoverySheetStatus').textContent=hasWbic ? 'Lake identity and shoreline are matched to Wisconsin DNR WBIC '+wbic+'. Depth is shown only when LakeNav has a verified vector source or an official DNR reference.' : 'This waterbody is present in Wisconsin DNR hydrography but does not expose a WBIC here, so WBIC-linked details and offline packages are unavailable.';
    }
  }

  function showLakeDiscoveryLoading(name) {
    const card=$('lakeDiscoveryCard');
    if (!card) return;
    if ($('lakeDiscoveryName')) $('lakeDiscoveryName').textContent=name||'Identifying lake…';
    if ($('lakeDiscoveryMeta')) $('lakeDiscoveryMeta').textContent='Wisconsin DNR hydrography';
    if ($('lakeDiscoveryDepthBadge')) { $('lakeDiscoveryDepthBadge').textContent='DEPTH • CHECKING'; $('lakeDiscoveryDepthBadge').className='lakeDiscoveryBadge mutedBadge'; }
    if ($('lakeDiscoverySourceBadge')) $('lakeDiscoverySourceBadge').textContent='DNR • LOOKUP';
    if ($('lakeDiscoveryExploreBtn')) $('lakeDiscoveryExploreBtn').disabled=true;
    if ($('lakeDiscoveryLaunchBtn')) $('lakeDiscoveryLaunchBtn').disabled=true;
    card.classList.add('loading','open');
  }

  async function queryLakeCounty(lat,lon) {
    try {
      const url=dnrCountyQueryBase()+
        'where=1%3D1&geometry='+encodeURIComponent(Number(lon).toFixed(7)+','+Number(lat).toFixed(7))+
        '&geometryType=esriGeometryPoint&inSR=4326&spatialRel=esriSpatialRelIntersects'+
        '&outFields=COUNTY_NAME&returnGeometry=false&f=json';
      const resp=await fetch(url);
      if (!resp.ok) return null;
      const json=await resp.json();
      const f=json && json.features && json.features[0];
      return f && f.attributes && f.attributes.COUNTY_NAME ? titleCaseWords(String(f.attributes.COUNTY_NAME).replace(/\s+COUNTY$/i,'').trim()) : null;
    } catch(e) { return null; }
  }

  function ringAreaSqMeters(ring) {
    if (!Array.isArray(ring) || ring.length<3) return 0;
    const R=6378137;
    let area=0;
    for (let i=0;i<ring.length;i++) {
      const a=ring[i], b=ring[(i+1)%ring.length];
      if (!a||!b) continue;
      const lon1=Number(a[0])*Math.PI/180, lon2=Number(b[0])*Math.PI/180;
      const lat1=Number(a[1])*Math.PI/180, lat2=Number(b[1])*Math.PI/180;
      area+=(lon2-lon1)*(2+Math.sin(lat1)+Math.sin(lat2));
    }
    return Math.abs(area*R*R/2);
  }

  function featureAreaSqMeters(feature) {
    const g=feature&&feature.geometry;
    if (!g||!Array.isArray(g.coordinates)) return 0;
    const polygonArea=poly=>{
      if (!Array.isArray(poly)||!poly.length) return 0;
      let a=ringAreaSqMeters(poly[0]);
      for(let i=1;i<poly.length;i++) a-=ringAreaSqMeters(poly[i]);
      return Math.max(0,a);
    };
    if (g.type==='Polygon') return polygonArea(g.coordinates);
    if (g.type==='MultiPolygon') return g.coordinates.reduce((sum,poly)=>sum+polygonArea(poly),0);
    return 0;
  }

  function geojsonAcres(geojson) {
    const sqm=(geojson && Array.isArray(geojson.features) ? geojson.features : []).reduce((sum,f)=>sum+featureAreaSqMeters(f),0);
    return sqm>0 ? sqm/4046.8564224 : null;
  }

  function titleCaseWords(value) {
    return String(value||'').toLowerCase().replace(/\b([a-z])/g,m=>m.toUpperCase());
  }

  function geojsonCenter(geojson) {
    let minLat=90,maxLat=-90,minLon=180,maxLon=-180,found=false;
    const walk=c=>{
      if (!Array.isArray(c)) return;
      if (c.length>=2 && typeof c[0]==='number' && typeof c[1]==='number') { minLon=Math.min(minLon,c[0]); maxLon=Math.max(maxLon,c[0]); minLat=Math.min(minLat,c[1]); maxLat=Math.max(maxLat,c[1]); found=true; return; }
      c.forEach(walk);
    };
    (geojson && geojson.features || []).forEach(f=>{ if(f&&f.geometry) walk(f.geometry.coordinates); });
    return found ? {lat:(minLat+maxLat)/2,lon:(minLon+maxLon)/2} : null;
  }

  async function loadLakeDiscovery(item,anchor,fit,sourceFeature) {
    const wbic=item && item.wbic ? String(item.wbic) : '';
    let geojson=null;
    if (wbic) {
      const where='WATERBODY_WBIC='+encodeURIComponent(wbic);
      const url=dnrLakeQueryBase()+'where='+where+
        '&outFields='+encodeURIComponent('WATERBODY_NAME,WATERBODY_ROW_NAME,WATERBODY_WBIC,HYDROTYPE')+
        '&returnGeometry=true&outSR=4326&f=geojson';
      const resp=await fetch(url);
      if (!resp.ok) throw new Error('DNR geometry HTTP '+resp.status);
      geojson=await resp.json();
      if (!geojson.features || !geojson.features.length) throw new Error('No shoreline geometry returned.');
    } else if (sourceFeature) {
      geojson={type:'FeatureCollection',features:[sourceFeature]};
    } else throw new Error('No DNR waterbody identifier returned.');
    const props=(geojson.features[0]&&geojson.features[0].properties)||{};
    const name=(item&&item.name)||props.WATERBODY_NAME||props.WATERBODY_ROW_NAME||'Unnamed Lake';
    resetVerifiedDepthSurface();
    selectedLake={name,wbic,geometry:geojson,detail:null,acres:geojsonAcres(geojson),county:null,depthState:null,discoveredBy:item&&item.discoveredBy||'map'};
    showSelectedLakeOnMap(!!fit);
    updateSelectedLakeUi();
    updateLakeDiscoveryUi();
    setLakeDiscoveryCardVisible(true);
    if (opticalShallowsEnabled) refreshOpticalShallows(true);
    if (depthShadeEnabled) scheduleDepthShadeRefresh();
    const anchorPoint=anchor||geojsonCenter(geojson);
    if (anchorPoint) {
      const selectionWbic=selectedLake.wbic, selectionName=selectedLake.name;
      queryLakeCounty(anchorPoint.lat,anchorPoint.lon).then(county=>{
        if (!selectedLake || selectedLake.name!==selectionName || selectedLake.wbic!==selectionWbic) return;
        selectedLake.county=county;
        updateSelectedLakeUi();
        updateLakeDiscoveryUi();
      });
    }
    if (wbic && window.Android && Android.loadLakeDetail) Android.loadLakeDetail(wbic);
  }

  async function discoverLakeAt(lat,lon) {
    if (!map || offlineMode || routeDrawMode || addMode || mapMode!=='2d') return;
    const requestId=++lakeDiscoveryRequestId;
    showLakeDiscoveryLoading('Identifying lake…');
    try {
      const where='HYDROTYPE IN (706,707,710)';
      const url=dnrLakeQueryBase()+'where='+encodeURIComponent(where)+
        '&geometry='+encodeURIComponent(Number(lon).toFixed(7)+','+Number(lat).toFixed(7))+
        '&geometryType=esriGeometryPoint&inSR=4326&spatialRel=esriSpatialRelIntersects'+
        '&outFields='+encodeURIComponent('OBJECTID,WATERBODY_NAME,WATERBODY_ROW_NAME,WATERBODY_WBIC,HYDROTYPE')+
        '&returnGeometry=true&outSR=4326&f=geojson&resultRecordCount=12';
      const resp=await fetch(url);
      if (!resp.ok) throw new Error('DNR lake lookup HTTP '+resp.status);
      const json=await resp.json();
      if (requestId!==lakeDiscoveryRequestId) return;
      const features=(json&&json.features)||[];
      if (!features.length) { if(selectedLake){ updateLakeDiscoveryUi(); setLakeDiscoveryCardVisible(true); } else setLakeDiscoveryCardVisible(false); return; }
      const priority=t=>Number(t)===706?0:(Number(t)===707?1:2);
      features.sort((a,b)=>priority(a.properties&&a.properties.HYDROTYPE)-priority(b.properties&&b.properties.HYDROTYPE)||featureAreaSqMeters(a)-featureAreaSqMeters(b));
      const f=features[0], p=f.properties||{};
      const wbic=p.WATERBODY_WBIC ? String(p.WATERBODY_WBIC) : '';
      const name=p.WATERBODY_NAME||p.WATERBODY_ROW_NAME||'Unnamed Lake';
      showLakeDiscoveryLoading(name);
      await loadLakeDiscovery({name,wbic,discoveredBy:'tap'},{lat:Number(lat),lon:Number(lon)},false,f);
      if (requestId!==lakeDiscoveryRequestId) return;
      const card=$('lakeDiscoveryCard'); if(card) card.classList.remove('loading');
    } catch(e) {
      if (requestId!==lakeDiscoveryRequestId) return;
      setLakeDiscoveryCardVisible(false);
      if (window.Android && Android.toast) Android.toast('Lake lookup unavailable');
    }
  }

  function openLakeDiscoverySheet() {
    if (!selectedLake) return;
    updateLakeDiscoveryUi();
    openSheet('lakeDiscoverySheet');
  }
'''
rep(marker,marker+funcs)
old='''  async function selectLakeResult(index) {
    const item = lakeSearchResults[index];
    if (!item) return;
    $('lakeSearchStatus').innerHTML = '<div class="muted">Loading ' + escapeHtml(item.name) + ' shoreline...</div>';
    try {
      const where = 'WATERBODY_WBIC=' + encodeURIComponent(String(item.wbic));
      const url = dnrLakeQueryBase() + 'where=' + where +
        '&outFields=WATERBODY_NAME,WATERBODY_WBIC&returnGeometry=true&outSR=4326&f=geojson';
      const resp = await fetch(url);
      if (!resp.ok) throw new Error('DNR geometry HTTP ' + resp.status);
      const geojson = await resp.json();
      if (!geojson.features || !geojson.features.length) throw new Error('No shoreline geometry returned.');
      resetVerifiedDepthSurface();
      selectedLake = { name: item.name, wbic: String(item.wbic), geometry: geojson, detail: null };
      showSelectedLakeOnMap(true);
      updateSelectedLakeUi();
      if (opticalShallowsEnabled) refreshOpticalShallows(true);
      closeSheets();
      $('lakeSearchStatus').innerHTML = '<div class="good muted">Lake loaded from Wisconsin DNR hydrography.</div>';
      if (window.Android && Android.loadLakeDetail) Android.loadLakeDetail(selectedLake.wbic);
    } catch (e) {
      $('lakeSearchStatus').innerHTML = '<div class="error">Could not load lake: ' + escapeHtml(e.message || String(e)) + '</div>';
    }
  }'''
new='''  async function selectLakeResult(index) {
    const item=lakeSearchResults[index];
    if (!item) return;
    $('lakeSearchStatus').innerHTML='<div class="muted">Loading '+escapeHtml(item.name)+' shoreline...</div>';
    try {
      await loadLakeDiscovery({name:item.name,wbic:String(item.wbic),discoveredBy:'search'},null,true,null);
      closeSheets();
      $('lakeSearchStatus').innerHTML='<div class="good muted">Lake loaded from Wisconsin DNR hydrography.</div>';
    } catch(e) {
      $('lakeSearchStatus').innerHTML='<div class="error">Could not load lake: '+escapeHtml(e.message||String(e))+'</div>';
    }
  }'''
rep(old,new)
rep("""    selectedLakeLayer = L.geoJSON(selectedLake.geometry, {
      style: { color: '#0b607f', weight: 3, fillColor: '#56a6c3', fillOpacity: offlineMode ? 0.34 : 0.15 }
    }).addTo(map);""","""    selectedLakeLayer = L.geoJSON(selectedLake.geometry, {
      style: { color: '#20c7e6', weight: 4, opacity: .96, fillColor: '#56c4d8', fillOpacity: offlineMode ? 0.34 : 0.12, className:'selectedLakeGlowPath' }
    }).addTo(map);""")
rep("""    let meta = 'WBIC: ' + selectedLake.wbic;
    if (selectedLake.detail && Number.isFinite(Number(selectedLake.detail.maxDepthFt))) meta += ' | Max depth: ' + Number(selectedLake.detail.maxDepthFt) + ' ft';
    $('selectedLakeMeta').textContent = meta;""","""    const metaBits=[];
    if (selectedLake.county) metaBits.push(selectedLake.county+' County');
    if (Number.isFinite(Number(selectedLake.acres))) metaBits.push(formatLakeAcres(selectedLake.acres));
    metaBits.push('WBIC: '+(selectedLake.wbic||'not assigned'));
    if (selectedLake.detail && Number.isFinite(Number(selectedLake.detail.maxDepthFt))) metaBits.push('Max depth: '+Number(selectedLake.detail.maxDepthFt)+' ft');
    $('selectedLakeMeta').textContent=metaBits.join(' | ');""")
rep("""    if (selectedLake.detail && selectedLake.detail.contourUrl) {
      $('selectedLakeDetailStatus').innerHTML = 'Wisconsin DNR lists an official contour map for this lake.';""","""    if (!selectedLake.wbic) {
      $('selectedLakeDetailStatus').innerHTML = 'Wisconsin DNR hydrography identifies this waterbody, but no WBIC is exposed here for linked lake details.';
    } else if (selectedLake.detail && selectedLake.detail.contourUrl) {
      $('selectedLakeDetailStatus').innerHTML = 'Wisconsin DNR lists an official contour map for this lake.';""")
rep("""    selectedLake.detail = detail;
    updateSelectedLakeUi();
    if (depthShadeEnabled) scheduleDepthShadeRefresh();""","""    selectedLake.detail = detail;
    updateSelectedLakeUi();
    updateLakeDiscoveryUi();
    if (depthShadeEnabled) scheduleDepthShadeRefresh();""")
rep("Search uses Wisconsin DNR hydrography names and WBICs. Open a lake in LakeNav or send the closest public boat launch for that lake to your phone navigation app.","Search by name, or close this sheet and tap directly on almost any Wisconsin lake. LakeNav uses Wisconsin DNR hydrography to identify the waterbody and its WBIC when available.")
old="""    $('searchBtn').addEventListener('click', () => { renderOfflineLakeList(); openSheet('searchSheet'); });
    $('navigateLaunchBtn').addEventListener('click', navigateToClosestBoatLaunch);"""
new="""    $('searchBtn').addEventListener('click', () => { renderOfflineLakeList(); openSheet('searchSheet'); });
    $('lakeDiscoveryClose').addEventListener('click', () => setLakeDiscoveryCardVisible(false));
    $('lakeDiscoveryExploreBtn').addEventListener('click', openLakeDiscoverySheet);
    $('lakeDiscoveryLaunchBtn').addEventListener('click', navigateToClosestBoatLaunch);
    $('lakeDiscoverySheetLaunchBtn').addEventListener('click', navigateToClosestBoatLaunch);
    $('lakeDiscoverySheetBathyBtn').addEventListener('click', openSelectedBathymetry);
    $('lakeDiscoverySheetOfflineBtn').addEventListener('click', saveSelectedLakeOffline);
    $('lakeDiscoverySheetDnrBtn').addEventListener('click', () => { if(selectedLake&&selectedLake.wbic) openExternal('https://apps.dnr.wi.gov/lakes/lakepages/LakeDetail.aspx?wbic='+encodeURIComponent(selectedLake.wbic)); });
    $('navigateLaunchBtn').addEventListener('click', navigateToClosestBoatLaunch);"""
rep(old,new)
rep("$('depthReferenceBtn').addEventListener('click', () => { if(selectedLake) openBathymetryForWbic(selectedLake.wbic,selectedLake.name); });","$('depthReferenceBtn').addEventListener('click', () => { if(selectedLake&&selectedLake.wbic) openBathymetryForWbic(selectedLake.wbic,selectedLake.name); });")
p.write_text(h)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 73/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.73.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v073-inline.js',s)"
node --check /tmp/lakenav-v073-inline.js
grep -q 'v0.73' app/src/main/assets/index.html
grep -q 'discoverLakeAt' app/src/main/assets/index.html
grep -q 'lakeDiscoverySheet' app/src/main/assets/index.html
grep -q 'ER_Biotics_WGS84_County_TRS_MCDs' app/src/main/assets/index.html
printf 'LakeNav WI v0.73 Wisconsin Lake Discovery foundation applied.\n'
