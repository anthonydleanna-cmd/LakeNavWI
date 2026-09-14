#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat > /tmp/lakenav-v037.patch <<'PATCH'
--- a/app/src/main/assets/index.html
+++ b/app/src/main/assets/index.html
@@ -618,6 +618,21 @@
 .trackHistoryColor { display:flex; align-items:center; gap:6px; color:#71818a; font-size:10px; font-weight:700; }
 .trackHistoryColor input[type=color] { width:34px; height:28px; padding:0; border:0; background:transparent; }
 
+/* v0.37 Track menu, trip log, and route popups */
+.trackMenuStatusRow { display:flex; align-items:center; justify-content:space-between; gap:12px; }
+.trackMenuStatusRow strong { display:block; color:#15384c; font-size:15px; }
+.trackRecDot { width:13px; height:13px; border-radius:50%; background:#b8c7ce; box-shadow:0 0 0 5px rgba(184,199,206,.18); flex:0 0 auto; }
+.trackRecDot.on { background:#d92d20; box-shadow:0 0 0 5px rgba(217,45,32,.13); }
+.trackLogItem { display:flex; align-items:center; justify-content:space-between; gap:10px; padding:12px 0; border-bottom:1px solid rgba(20,58,78,.09); }
+.trackLogTop { display:flex; align-items:flex-start; gap:9px; min-width:0; }
+.trackLogTop strong { display:block; color:#15384c; font-size:13px; }
+.trackLogTop small { display:block; color:#71818a; margin-top:3px; font-size:11px; }
+.trackColorDot { width:12px; height:12px; border-radius:50%; margin-top:3px; flex:0 0 auto; box-shadow:0 0 0 2px rgba(20,58,78,.08); }
+.trackPopup strong { display:block; margin-bottom:7px; font-size:14px; color:#15384c; }
+.trackPopupGrid { display:grid; grid-template-columns:auto 1fr; gap:4px 10px; font-size:12px; min-width:190px; }
+.trackPopupGrid span { color:#71818a; }
+.trackPopupGrid b { color:#15384c; font-weight:700; }
+
 </style>
 <script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js" onerror="window.leafletFailed=true"></script>
 <script src="maplibre-gl.js" onerror="window.maplibreFailed=true"></script>
@@ -626,7 +641,7 @@
 <div id="app">
   <div id="statusbar">
     <div>
-      <div id="brand">LakeNav WI <span class="versionPill">v0.36</span></div>
+      <div id="brand">LakeNav WI <span class="versionPill">v0.37</span></div>
       <div id="gpsState">Waiting for GPS...</div>
     </div>
     <div id="gpsNumbers">
@@ -760,6 +775,27 @@
 
 
 
+<div class="sheetBackdrop" id="trackSheet">
+  <div class="sheet">
+    <div class="sheetHeader"><h2>Track</h2><button class="closeBtn" data-close="trackSheet">x</button></div>
+    <div class="card" style="margin:0 0 12px">
+      <div class="trackMenuStatusRow"><div><strong id="trackMenuStatus">Not recording</strong><div class="muted" id="trackMenuDetail">Start a new trip track or review previous tracks.</div></div><span class="trackRecDot" id="trackMenuDot"></span></div>
+    </div>
+    <div class="btnRow">
+      <button class="btn" id="trackActionBtn">Start tracking</button>
+      <button class="btn secondary" id="trackLogBtn">View track log</button>
+    </div>
+  </div>
+</div>
+
+<div class="sheetBackdrop" id="trackLogSheet">
+  <div class="sheet">
+    <div class="sheetHeader"><h2>Track log</h2><button class="closeBtn" data-close="trackLogSheet">x</button></div>
+    <p class="muted">Completed tracking sessions are saved here. Tap Show on map to display a track; tap the soft route line on the map for trip details.</p>
+    <div id="trackLogList"></div>
+  </div>
+</div>
+
 <div class="sheetBackdrop" id="waypointEditSheet">
   <div class="sheet">
     <div class="sheetHeader"><h2 id="waypointEditTitle">Waypoint details</h2><button class="closeBtn" data-close="waypointEditSheet">x</button></div>
@@ -1149,6 +1185,8 @@
   let navArrowSyncRaf = 0;
   let navArrowSyncUntil = 0;
   let navFreePanHeading = null;
+  let northUpUserOverride = false;
+  let lastNorthUpFollowAt = 0;
   let currentLoc = null;
   let firstFix = true;
   let addMode = false;
@@ -1279,6 +1317,78 @@
     return trackHistory.filter(h=>h && h.visible!==false && Number(h.endTime||0)>=minTime && Array.isArray(h.points) && h.points.length>1);
   }
 
+  function historyTripDate(h) {
+    const d=new Date(Number(h&&h.startTime)||Date.now());
+    return d.toLocaleDateString([], {weekday:'short',month:'short',day:'numeric',year:'numeric'});
+  }
+
+  function historyTripTime(ts) {
+    if (!Number.isFinite(Number(ts))) return '--';
+    return new Date(Number(ts)).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'});
+  }
+
+  function trackHistoryPopupHtml(h) {
+    const dist=formatHistoryDistance(h.distanceM||trackHistoryDistance(h.points||[]));
+    return '<div class="trackPopup"><strong>'+escapeHtml(h.name||'Tracked route')+'</strong>'+ 
+      '<div class="trackPopupGrid"><span>Date</span><b>'+escapeHtml(historyTripDate(h))+'</b>'+ 
+      '<span>Start</span><b>'+escapeHtml(historyTripTime(h.startTime))+'</b>'+ 
+      '<span>End</span><b>'+escapeHtml(historyTripTime(h.endTime))+'</b>'+ 
+      '<span>Distance</span><b>'+escapeHtml(dist)+'</b></div></div>';
+  }
+
+  function showHistoryTrack(id) {
+    const h=trackHistory.find(x=>x.id===id);
+    if (!h || !map || !Array.isArray(h.points) || h.points.length<2) return;
+    h.visible=true;
+    trackHistoryEnabled=true;
+    localStorage.setItem(STORAGE_TRACK_HISTORY_ENABLED,'1');
+    saveTrackHistory();
+    renderTrackHistoryOverlays();
+    renderTrackHistorySettings();
+    renderTrackLog();
+    closeSheets();
+    const pts=h.points.map(pt=>[Number(pt.lat),Number(pt.lon)]).filter(pt=>Number.isFinite(pt[0])&&Number.isFinite(pt[1]));
+    if (pts.length<2) return;
+    const bounds=L.latLngBounds(pts);
+    map.fitBounds(bounds,{padding:[45,70],maxZoom:16,animate:true,duration:.45});
+    setTimeout(()=>{
+      const mid=pts[Math.floor(pts.length/2)];
+      L.popup({maxWidth:280,closeButton:true}).setLatLng(mid).setContent(trackHistoryPopupHtml(h)).openOn(map);
+    },520);
+  }
+
+  function renderTrackMenu() {
+    const status=$('trackMenuStatus'), detail=$('trackMenuDetail'), action=$('trackActionBtn'), dot=$('trackMenuDot');
+    if (!status || !detail || !action) return;
+    if (recording) {
+      status.textContent='Tracking now';
+      detail.textContent='Current distance: '+(trackDistanceMeters()*M_TO_MI).toFixed(2)+' mi • '+trackPoints.length+' points';
+      action.textContent='Stop tracking';
+      action.classList.add('danger');
+      if (dot) dot.classList.add('on');
+    } else {
+      status.textContent='Not recording';
+      detail.textContent=trackHistory.length ? trackHistory.length+' saved track'+(trackHistory.length===1?'':'s')+' in the log' : 'Start a new trip track or review previous tracks.';
+      action.textContent='Start tracking';
+      action.classList.remove('danger');
+      if (dot) dot.classList.remove('on');
+    }
+  }
+
+  function renderTrackLog() {
+    const holder=$('trackLogList');
+    if (!holder) return;
+    if (!trackHistory.length) {
+      holder.innerHTML='<div class="muted" style="padding:12px 0">No completed tracks yet.</div>';
+      return;
+    }
+    holder.innerHTML=[...trackHistory].sort((a,b)=>Number(b.startTime||0)-Number(a.startTime||0)).map(h=>{
+      const dist=formatHistoryDistance(h.distanceM||trackHistoryDistance(h.points||[]));
+      return '<div class="trackLogItem"><div class="trackLogTop"><span class="trackColorDot" style="background:'+escapeHtml(h.color||'#147aa6')+'"></span><div><strong>'+escapeHtml(historyTripDate(h))+'</strong><small>'+escapeHtml(historyTripTime(h.startTime))+' – '+escapeHtml(historyTripTime(h.endTime))+' • '+escapeHtml(dist)+'</small></div></div><button class="btn small secondary" data-track-log-show="'+escapeHtml(h.id)+'">Show on map</button></div>';
+    }).join('');
+    holder.querySelectorAll('[data-track-log-show]').forEach(btn=>btn.addEventListener('click',()=>showHistoryTrack(btn.dataset.trackLogShow)));
+  }
+
   function renderTrackHistoryOverlays() {
     if (!map) return;
     if (trackHistoryLayerGroup) { try { map.removeLayer(trackHistoryLayerGroup); } catch(e) {} trackHistoryLayerGroup=null; }
@@ -1287,7 +1397,11 @@
     activeTrackHistory().forEach(h=>{
       const pts=h.points.map(p=>[Number(p.lat),Number(p.lon)]).filter(p=>Number.isFinite(p[0])&&Number.isFinite(p[1]));
       if (pts.length<2) return;
-      L.polyline(pts,{color:h.color||'#147aa6',weight:3,opacity:.28,interactive:false,lineCap:'round',lineJoin:'round'}).addTo(trackHistoryLayerGroup);
+      const popup=trackHistoryPopupHtml(h);
+      const visible=L.polyline(pts,{color:h.color||'#147aa6',weight:3,opacity:.28,interactive:true,lineCap:'round',lineJoin:'round'}).addTo(trackHistoryLayerGroup);
+      visible.bindPopup(popup,{maxWidth:280});
+      const hit=L.polyline(pts,{color:h.color||'#147aa6',weight:18,opacity:.01,interactive:true,lineCap:'round',lineJoin:'round'}).addTo(trackHistoryLayerGroup);
+      hit.bindPopup(popup,{maxWidth:280});
     });
   }
 
@@ -2286,7 +2400,7 @@
   }
 
   function ensureOperationalCourseUp() {
-    if (!operationalNavigationActive() || routeDrawMode || mapMode!=='2d') return;
+    if (!operationalNavigationActive() || routeDrawMode || mapMode!=='2d' || northUpUserOverride) return;
     if (orientationMode !== 'courseup') {
       orientationMode='courseup';
       navFollowMode=true;
@@ -2305,8 +2419,31 @@
   }
 
   function maybeFollowPrimaryNavigation() {
+    if (!map || !currentLoc || routeDrawMode || mapMode!=='2d') return;
+
+    // Preserve the automatic Course Up behavior unless the user explicitly selected North Up.
+    if (orientationMode==='northup' && !northUpUserOverride) ensureOperationalCourseUp();
+
+    // North Up is a centered moving map. While meaningful GPS movement is present, the combined
+    // GPS point/arrow stays exactly in the middle of the view and the map moves underneath it.
+    if (orientationMode==='northup') {
+      const speed=Number.isFinite(Number(currentLoc.speed)) ? Math.max(0,Number(currentLoc.speed)) : 0;
+      if (speed>=0.55) {
+        navFollowMode=true;
+        const now=performance.now();
+        if (now-lastNorthUpFollowAt>=300) {
+          lastNorthUpFollowAt=now;
+          const target=[Number(currentLoc.lat),Number(currentLoc.lon)];
+          if (positionMarker) positionMarker.setLatLng(target);
+          if (accuracyCircle) accuracyCircle.setLatLng(target);
+          map.panTo(target,{animate:false,noMoveStart:true});
+        }
+      }
+      return;
+    }
+
     ensureOperationalCourseUp();
-    if (!navFollowMode || !navigationPerspectiveActive() || !map || !currentLoc || routeDrawMode) return;
+    if (!navFollowMode || !navigationPerspectiveActive()) return;
     const now=performance.now();
     if (now-lastNavFollowAt < 420) return;
     lastNavFollowAt=now;
@@ -2383,8 +2520,9 @@
       return;
     }
     orientationMode = orientationMode === 'courseup' ? 'northup' : 'courseup';
+    northUpUserOverride = orientationMode==='northup';
     if (orientationMode==='courseup' && navPerspectiveEnabled) { navFollowMode=true; resetCourseUpAcquisition(); }
-    else { navCourseAcquired=false; navStableFix=null; navFilteredFix=null; navFilterHeading=null; navFreePanHeading=null; }
+    else { navFollowMode=true; navCourseAcquired=false; navStableFix=null; navFilteredFix=null; navFilterHeading=null; navFreePanHeading=null; }
     const h = activeHeading();
     mapRotationDeg = orientationMode === 'courseup' && h ? h.degrees : 0;
     localStorage.setItem(STORAGE_ORIENTATION, orientationMode);
@@ -2591,9 +2729,11 @@
     recording = on;
     $('trackBtn').classList.toggle('recording', on);
     const trackLabel = $('trackBtn').lastElementChild;
-    if (trackLabel) trackLabel.textContent = on ? 'Stop' : 'Track';
+    if (trackLabel) trackLabel.textContent = 'Track';
     $('trackChip').style.display = on ? 'block' : 'none';
     updateTrackUi();
+    renderTrackMenu();
+    renderTrackLog();
     if (window.Android && Android.keepScreenOn) Android.keepScreenOn(on || !!targetId || !!activeRouteId);
     if (window.Android && Android.toast) Android.toast(on ? 'New track recording started' : (trackPoints.length>=2 ? 'Track saved to history' : 'Track recording stopped'));
   }
@@ -2604,6 +2744,7 @@
     $('trackDistance').textContent = text;
     $('trackDistanceMore').textContent = text;
     $('trackPointCount').textContent = trackPoints.length;
+    if ($('trackSheet') && $('trackSheet').classList.contains('open')) renderTrackMenu();
   }
 
   function trackDistanceMeters() {
@@ -3356,6 +3497,8 @@
 
   function openSheet(id) {
     renderWaypointList();
+    if (id==='trackSheet') renderTrackMenu();
+    if (id==='trackLogSheet') renderTrackLog();
     $(id).classList.add('open');
   }
 
@@ -5237,7 +5380,9 @@
     $('markBtn').addEventListener('click', addCurrentWaypoint);
     $('searchBtn').addEventListener('click', () => { renderOfflineLakeList(); openSheet('searchSheet'); });
     $('waypointsBtn').addEventListener('click', () => openSheet('waypointSheet'));
-    $('trackBtn').addEventListener('click', () => setRecording(!recording));
+    $('trackBtn').addEventListener('click', () => openSheet('trackSheet'));
+    $('trackActionBtn').addEventListener('click', () => { setRecording(!recording); closeSheets(); });
+    $('trackLogBtn').addEventListener('click', () => { renderTrackLog(); closeSheets(); $('trackLogSheet').classList.add('open'); });
     $('moreBtn').addEventListener('click', () => openSheet('moreSheet'));
     $('settingsBtn').addEventListener('click', () => { loadSettingsUi(); closeSheets(); $('settingsSheet').classList.add('open'); });
     $('layersQuickBtn').addEventListener('click', e => { e.stopPropagation(); toggleQuickLayers(); });
@@ -5345,6 +5490,8 @@
   renderOfflineLakeList();
   updateTrackUi();
   renderTrackHistorySettings();
+  renderTrackMenu();
+  renderTrackLog();
 })();
 </script>
 </body>
PATCH
patch -p1 < /tmp/lakenav-v037.patch

python3 - <<'PY2'
from pathlib import Path
rp=Path('README.md')
r=rp.read_text()
if '## Version 0.37 features' not in r:
    insert='\n## Version 0.37 features\n\n### Track menu, trip log, tappable history, and North Up center follow\n- The bottom Track button now opens a menu instead of immediately toggling recording. The menu provides a dedicated Start/Stop Tracking action and a View Track Log action.\n- The Track Log lists completed sessions with date, start time, end time, distance, and a color indicator. Each saved trip can be shown directly on the map.\n- Soft historical track overlays are now tappable. Tapping a displayed historical route opens a popup with the trip date, start time, end time, and distance. A wider transparent touch target makes the soft overlay easier to select without making it visually heavier.\n- When North Up is explicitly selected and GPS movement is detected, the GPS arrow/circle stays centered in the visible map and the map moves underneath it. Automatic Course Up remains the default for active navigation/tracking unless the user manually chooses North Up.\n'
    pos=r.find('\n## Version 0.36 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY2

sed -i "s/versionCode [0-9][0-9]*/versionCode 37/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.37.0'/" app/build.gradle
grep -q 'v0.37' app/src/main/assets/index.html
grep -q 'id="trackSheet"' app/src/main/assets/index.html
grep -q 'trackHistoryPopupHtml' app/src/main/assets/index.html
grep -q 'northUpUserOverride' app/src/main/assets/index.html
grep -q 'Version 0.37 features' README.md
printf 'LakeNav WI v0.37 track menu, trip log, route popups, and North Up center follow applied.\n'
