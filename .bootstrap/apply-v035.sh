#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.35</span></div>', s, count=1)

const_anchor="  const STORAGE_TRACK = 'lakenav.track.v1';"
if const_anchor not in s: raise SystemExit('STORAGE_TRACK anchor not found')
s=s.replace(const_anchor, const_anchor+"\n  const STORAGE_TRACK_HISTORY = 'lakenav.trackhistory.v1';\n  const STORAGE_TRACK_HISTORY_RANGE = 'lakenav.trackhistory.range.v1';\n  const STORAGE_TRACK_HISTORY_ENABLED = 'lakenav.trackhistory.enabled.v1';",1)

state_anchor="  let trackPoints = loadJson(STORAGE_TRACK, []);"
if state_anchor not in s: raise SystemExit('trackPoints state anchor not found')
s=s.replace(state_anchor, state_anchor+"\n  let trackHistory = loadJson(STORAGE_TRACK_HISTORY, []);\n  let trackHistoryLayerGroup = null;\n  let trackHistoryEnabled = localStorage.getItem(STORAGE_TRACK_HISTORY_ENABLED) === '1';\n  let trackHistoryRange = ['day','week','month','year','all'].includes(localStorage.getItem(STORAGE_TRACK_HISTORY_RANGE)) ? localStorage.getItem(STORAGE_TRACK_HISTORY_RANGE) : 'week';\n  let recordingStartedAt = 0;\n  let currentTrackArchived = false;",1)

save_anchor="""  function saveTrack() {
    localStorage.setItem(STORAGE_TRACK, JSON.stringify(trackPoints.slice(-12000)));
  }
"""
if save_anchor not in s: raise SystemExit('saveTrack block not found')
s=s.replace(save_anchor, save_anchor+r'''

  function saveTrackHistory() {
    if (trackHistory.length > 120) trackHistory = trackHistory.slice(-120);
    localStorage.setItem(STORAGE_TRACK_HISTORY, JSON.stringify(trackHistory));
  }

  function compactHistoryPoints(points) {
    const src=(points||[]).filter(p=>Number.isFinite(Number(p.lat))&&Number.isFinite(Number(p.lon)));
    if (src.length <= 600) return src.map(p=>({lat:Number(p.lat),lon:Number(p.lon),time:Number(p.time)||Date.now()}));
    const step=Math.ceil((src.length-1)/599);
    const out=[];
    for(let i=0;i<src.length;i+=step) out.push({lat:Number(src[i].lat),lon:Number(src[i].lon),time:Number(src[i].time)||Date.now()});
    const last=src[src.length-1];
    if (!out.length || out[out.length-1].lat!==Number(last.lat) || out[out.length-1].lon!==Number(last.lon)) out.push({lat:Number(last.lat),lon:Number(last.lon),time:Number(last.time)||Date.now()});
    return out.slice(-600);
  }

  function trackHistoryPalette(index) {
    const palette=['#147aa6','#5b65c8','#168b74','#a25e22','#8b4fa8','#b64b66','#557a2b','#3d7188'];
    return palette[Math.abs(Number(index)||0)%palette.length];
  }

  function trackHistoryDistance(points) {
    let total=0;
    for(let i=1;i<(points||[]).length;i++) total+=distanceMeters(points[i-1].lat,points[i-1].lon,points[i].lat,points[i].lon);
    return total;
  }

  function trackAlreadyArchived(points) {
    if (!points || points.length<2 || !trackHistory.length) return false;
    const first=points[0], last=points[points.length-1];
    return trackHistory.some(h=>Math.abs(Number(h.startTime)-Number(first.time||0))<1500 && Math.abs(Number(h.endTime)-Number(last.time||0))<1500);
  }

  function archiveCurrentTrack() {
    if (!trackPoints || trackPoints.length<2 || trackAlreadyArchived(trackPoints)) { currentTrackArchived=true; return; }
    const pts=compactHistoryPoints(trackPoints);
    if (pts.length<2) return;
    const start=Number(trackPoints[0].time)||recordingStartedAt||Date.now();
    const end=Number(trackPoints[trackPoints.length-1].time)||Date.now();
    trackHistory.push({
      id:'th'+end+'_'+Math.random().toString(36).slice(2,7),
      name:new Date(start).toLocaleDateString([], {month:'short',day:'numeric',year:'numeric'})+' • '+new Date(start).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'}),
      startTime:start,
      endTime:end,
      distanceM:trackHistoryDistance(trackPoints),
      color:trackHistoryPalette(trackHistory.length),
      visible:true,
      points:pts
    });
    currentTrackArchived=true;
    saveTrackHistory();
    renderTrackHistoryOverlays();
    renderTrackHistorySettings();
  }

  function historyRangeStart() {
    const now=Date.now();
    if (trackHistoryRange==='day') return now-24*60*60*1000;
    if (trackHistoryRange==='week') return now-7*24*60*60*1000;
    if (trackHistoryRange==='month') return now-30*24*60*60*1000;
    if (trackHistoryRange==='year') return now-365*24*60*60*1000;
    return 0;
  }

  function activeTrackHistory() {
    const minTime=historyRangeStart();
    return trackHistory.filter(h=>h && h.visible!==false && Number(h.endTime||0)>=minTime && Array.isArray(h.points) && h.points.length>1);
  }

  function renderTrackHistoryOverlays() {
    if (!map) return;
    if (trackHistoryLayerGroup) { try { map.removeLayer(trackHistoryLayerGroup); } catch(e) {} trackHistoryLayerGroup=null; }
    if (!trackHistoryEnabled) return;
    trackHistoryLayerGroup=L.layerGroup().addTo(map);
    activeTrackHistory().forEach(h=>{
      const pts=h.points.map(p=>[Number(p.lat),Number(p.lon)]).filter(p=>Number.isFinite(p[0])&&Number.isFinite(p[1]));
      if (pts.length<2) return;
      L.polyline(pts,{color:h.color||'#147aa6',weight:3,opacity:.28,interactive:false,lineCap:'round',lineJoin:'round'}).addTo(trackHistoryLayerGroup);
    });
  }

  function formatHistoryDistance(m) {
    return ((Number(m)||0)*M_TO_MI).toFixed((Number(m)||0)*M_TO_MI<10?2:1)+' mi';
  }

  function renderTrackHistorySettings() {
    const box=$('trackHistoryList');
    if (!box) return;
    if ($('trackHistoryToggle')) $('trackHistoryToggle').checked=trackHistoryEnabled;
    document.querySelectorAll('[data-track-history-range]').forEach(btn=>btn.classList.toggle('active',btn.dataset.trackHistoryRange===trackHistoryRange));
    const visible=activeTrackHistory();
    if ($('trackHistorySummary')) $('trackHistorySummary').textContent=trackHistory.length ? visible.length+' shown • '+trackHistory.length+' saved' : 'No saved tracks yet';
    if (!trackHistory.length) { box.innerHTML='<div class="muted">Completed Track sessions will appear here automatically.</div>'; return; }
    const rows=[...trackHistory].sort((a,b)=>Number(b.endTime||0)-Number(a.endTime||0)).map(h=>{
      const d=new Date(Number(h.startTime)||Date.now());
      const when=d.toLocaleDateString([], {month:'short',day:'numeric',year:'numeric'})+' '+d.toLocaleTimeString([], {hour:'numeric',minute:'2-digit'});
      return '<div class="trackHistoryRow" data-history-id="'+escapeHtml(h.id)+'"><label class="trackHistoryShow"><input type="checkbox" data-history-visible="'+escapeHtml(h.id)+'" '+(h.visible===false?'':'checked')+' /> <span><strong>'+escapeHtml(h.name||'Saved track')+'</strong><small>'+escapeHtml(when)+' • '+formatHistoryDistance(h.distanceM||trackHistoryDistance(h.points||[]))+'</small></span></label><label class="trackHistoryColor"><span>Color</span><input type="color" data-history-color="'+escapeHtml(h.id)+'" value="'+escapeHtml(h.color||'#147aa6')+'" /></label></div>';
    }).join('');
    box.innerHTML=rows;
    box.querySelectorAll('[data-history-visible]').forEach(el=>el.addEventListener('change',()=>{
      const h=trackHistory.find(x=>x.id===el.dataset.historyVisible); if(!h)return; h.visible=!!el.checked; saveTrackHistory(); renderTrackHistoryOverlays(); renderTrackHistorySettings();
    }));
    box.querySelectorAll('[data-history-color]').forEach(el=>el.addEventListener('input',()=>{
      const h=trackHistory.find(x=>x.id===el.dataset.historyColor); if(!h)return; h.color=el.value; saveTrackHistory(); renderTrackHistoryOverlays();
    }));
  }
''',1)

track_init="""    trackLine = L.polyline(trackPoints.map(p => [p.lat, p.lon]), {
      color: '#d9271c',
      weight: 4,
      opacity: 0.85
    }).addTo(map);
"""
if track_init not in s: raise SystemExit('trackLine init not found')
s=s.replace(track_init, track_init+"\n    renderTrackHistoryOverlays();\n",1)

old_set=r'''  function setRecording(on) {
    recording = on;
    $('trackBtn').classList.toggle('recording', on);
    const trackLabel = $('trackBtn').lastElementChild;
    if (trackLabel) trackLabel.textContent = on ? 'Stop' : 'Track';
    $('trackChip').style.display = on ? 'block' : 'none';
    if (window.Android && Android.keepScreenOn) Android.keepScreenOn(on || !!targetId || !!activeRouteId);
    if (window.Android && Android.toast) Android.toast(on ? 'Track recording started' : 'Track recording stopped');
  }
'''
new_set=r'''  function setRecording(on) {
    if (!!on === recording) return;
    if (on) {
      if (trackPoints.length>=2 && !trackAlreadyArchived(trackPoints)) archiveCurrentTrack();
      trackPoints=[];
      saveTrack();
      if (trackLine) trackLine.setLatLngs([]);
      recordingStartedAt=Date.now();
      currentTrackArchived=false;
    } else {
      archiveCurrentTrack();
    }
    recording = on;
    $('trackBtn').classList.toggle('recording', on);
    const trackLabel = $('trackBtn').lastElementChild;
    if (trackLabel) trackLabel.textContent = on ? 'Stop' : 'Track';
    $('trackChip').style.display = on ? 'block' : 'none';
    updateTrackUi();
    if (window.Android && Android.keepScreenOn) Android.keepScreenOn(on || !!targetId || !!activeRouteId);
    if (window.Android && Android.toast) Android.toast(on ? 'New track recording started' : (trackPoints.length>=2 ? 'Track saved to history' : 'Track recording stopped'));
  }
'''
if old_set not in s: raise SystemExit('setRecording block not found')
s=s.replace(old_set,new_set,1)

old_toggle="""    localStorage.setItem(STORAGE_ORIENTATION, orientationMode);
    updateNavigationPerspectiveUi();
    applyMapOrientation();
"""
new_toggle="""    localStorage.setItem(STORAGE_ORIENTATION, orientationMode);
    if (orientationMode==='northup' && currentLoc) {
      if (positionMarker) positionMarker.setLatLng([currentLoc.lat,currentLoc.lon]);
      if (accuracyCircle) accuracyCircle.setLatLng([currentLoc.lat,currentLoc.lon]);
      syncNavigationTrackEndpoint();
      updateHeadingLine(activeHeading() ? activeHeading().degrees : null);
    }
    updateNavigationPerspectiveUi();
    applyMapOrientation();
"""
if old_toggle not in s: raise SystemExit('orientation toggle update anchor not found')
s=s.replace(old_toggle,new_toggle,1)

settings_anchor='''    <div class="card">\n      <h3>Storm alert range</h3>'''
if settings_anchor not in s: raise SystemExit('settings storm card anchor not found')
settings_card='''    <div class="card" id="trackHistorySettingsCard">\n      <h3>Track history overlays</h3>\n      <label class="switchLine"><input type="checkbox" id="trackHistoryToggle" /> Show previous tracked routes</label>\n      <div class="muted" style="margin-top:6px">Saved tracks appear as soft lines under the live route so you can compare how you traveled the same water over time.</div>\n      <div class="trackRangeButtons" id="trackRangeButtons">\n        <button type="button" data-track-history-range="day">DAY</button><button type="button" data-track-history-range="week">WEEK</button><button type="button" data-track-history-range="month">MONTH</button><button type="button" data-track-history-range="year">YEAR</button><button type="button" data-track-history-range="all">ALL</button>\n      </div>\n      <div id="trackHistorySummary" class="muted" style="margin:8px 0">No saved tracks yet</div>\n      <div id="trackHistoryList"></div>\n    </div>\n\n'''
s=s.replace(settings_anchor,settings_card+settings_anchor,1)

more_anchor='''      <div class="btnRow">\n        <button class="btn danger" id="clearTrackBtn">Clear current track</button>\n      </div>\n    </div>'''
if more_anchor not in s: raise SystemExit('More track card anchor not found')
more_new='''      <div class="btnRow">\n        <button class="btn danger" id="clearTrackBtn">Clear current track</button>\n        <button class="btn secondary" id="trackHistorySettingsBtn">Track history</button>\n      </div>\n      <div class="muted" style="margin-top:8px">Completed track sessions are saved automatically and can be overlaid by day, week, month, or year.</div>\n    </div>'''
s=s.replace(more_anchor,more_new,1)

old_gpx="""    const trkXml = trackPoints.length ? '<trk><name>LakeNav WI Track</name><trkseg>\\n' + trackPoints.map(p => '<trkpt lat="' + p.lat + '" lon="' + p.lon + '"><time>' + new Date(p.time || Date.now()).toISOString() + '</time></trkpt>').join('\\n') + '\\n</trkseg></trk>' : '';
    const gpx = '<?xml version="1.0" encoding="UTF-8"?>\\n<gpx version="1.1" creator="LakeNav WI" xmlns="http://www.topografix.com/GPX/1/1">\\n' + wptXml + '\\n' + rteXml + '\\n' + trkXml + '\\n</gpx>\\n';
"""
new_gpx="""    const historyTrkXml = trackHistory.map(h => '<trk><name>' + esc(h.name || 'LakeNav saved track') + '</name><trkseg>\\n' + (h.points||[]).map(p => '<trkpt lat="' + p.lat + '" lon="' + p.lon + '"><time>' + new Date(p.time || h.startTime || Date.now()).toISOString() + '</time></trkpt>').join('\\n') + '\\n</trkseg></trk>').join('\\n');
    const trkXml = trackPoints.length ? '<trk><name>LakeNav WI Current Track</name><trkseg>\\n' + trackPoints.map(p => '<trkpt lat="' + p.lat + '" lon="' + p.lon + '"><time>' + new Date(p.time || Date.now()).toISOString() + '</time></trkpt>').join('\\n') + '\\n</trkseg></trk>' : '';
    const gpx = '<?xml version="1.0" encoding="UTF-8"?>\\n<gpx version="1.1" creator="LakeNav WI" xmlns="http://www.topografix.com/GPX/1/1">\\n' + wptXml + '\\n' + rteXml + '\\n' + historyTrkXml + '\\n' + trkXml + '\\n</gpx>\\n';
"""
if old_gpx not in s: raise SystemExit('GPX track block not found')
s=s.replace(old_gpx,new_gpx,1)

bind_anchor="    $('clearTrackBtn').addEventListener('click', clearTrack);"
if bind_anchor not in s: raise SystemExit('clearTrack binding anchor not found')
s=s.replace(bind_anchor, bind_anchor+"\n    $('trackHistorySettingsBtn').addEventListener('click', () => { loadSettingsUi(); closeSheets(); $('settingsSheet').classList.add('open'); setTimeout(()=>{ const c=$('trackHistorySettingsCard'); if(c&&c.scrollIntoView)c.scrollIntoView({behavior:'smooth',block:'start'}); },80); });\n    $('trackHistoryToggle').addEventListener('change', e => { trackHistoryEnabled=!!e.target.checked; localStorage.setItem(STORAGE_TRACK_HISTORY_ENABLED,trackHistoryEnabled?'1':'0'); renderTrackHistoryOverlays(); renderTrackHistorySettings(); });\n    document.querySelectorAll('[data-track-history-range]').forEach(btn=>btn.addEventListener('click',()=>{ trackHistoryRange=btn.dataset.trackHistoryRange; localStorage.setItem(STORAGE_TRACK_HISTORY_RANGE,trackHistoryRange); renderTrackHistoryOverlays(); renderTrackHistorySettings(); }));",1)

load_settings_tail="""    $('xweatherSecretInput').value = xweatherSecret;
    updateLiveLightningStatus();
  }
"""
if load_settings_tail not in s: raise SystemExit('loadSettingsUi tail not found')
s=s.replace(load_settings_tail,"""    $('xweatherSecretInput').value = xweatherSecret;
    updateLiveLightningStatus();
    renderTrackHistorySettings();
  }
""",1)

init_tail="""  renderRouteList();
  renderOfflineLakeList();
})();
"""
if init_tail not in s: raise SystemExit('startup tail not found')
s=s.replace(init_tail,"""  renderRouteList();
  renderOfflineLakeList();
  updateTrackUi();
  renderTrackHistorySettings();
})();
""",1)

css='''
/* v0.35 Track History overlays */
.trackRangeButtons { display:grid; grid-template-columns:repeat(5,1fr); gap:6px; margin-top:10px; }
.trackRangeButtons button { border:1px solid rgba(10,53,85,.16); background:#eef5f8; color:#173f57; border-radius:10px; padding:9px 4px; font-size:11px; font-weight:800; }
.trackRangeButtons button.active { background:#0a5d7d; color:#fff; border-color:#0a5d7d; box-shadow:0 3px 10px rgba(10,93,125,.18); }
.trackHistoryRow { display:flex; align-items:center; justify-content:space-between; gap:10px; padding:10px 0; border-top:1px solid rgba(20,58,78,.09); }
.trackHistoryShow { display:flex; align-items:flex-start; gap:8px; min-width:0; flex:1; }
.trackHistoryShow span { min-width:0; display:block; }
.trackHistoryShow strong { display:block; font-size:13px; color:#15384c; }
.trackHistoryShow small { display:block; color:#71818a; margin-top:2px; font-size:11px; }
.trackHistoryColor { display:flex; align-items:center; gap:6px; color:#71818a; font-size:10px; font-weight:700; }
.trackHistoryColor input[type=color] { width:34px; height:28px; padding:0; border:0; background:transparent; }
'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.35 features' not in r:
    insert='''\n## Version 0.35 features\n\n### Track History overlays\n- Completed Track sessions are saved automatically as separate historical routes instead of being merged into one endless current track.\n- Settings now includes Track History overlays with Day, Week, Month, Year, and All time windows.\n- Each saved track can be individually shown/hidden and assigned its own color. Historical tracks render as soft 28% opacity lines underneath the current route.\n- Track history is compacted for long-term on-device storage (up to 120 saved sessions, with each overlay route simplified to at most 600 points).\n- Starting a new Track session safely archives the previous current track if needed and begins a fresh live route.\n- GPX export now includes saved historical tracks plus the current track.\n- North Up now immediately aligns the GPS arrow/circle, heading line, and current track endpoint when selected rather than waiting for a later free-pan/GPS event.\n'''
    pos=r.find('\n## Version 0.34 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)

p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 35/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.35.0'/" app/build.gradle
grep -q 'v0.35' app/src/main/assets/index.html
grep -q 'STORAGE_TRACK_HISTORY' app/src/main/assets/index.html
grep -q 'Track history overlays' app/src/main/assets/index.html
grep -q 'Version 0.35 features' README.md
printf 'LakeNav WI v0.35 Track History overlays applied.\n'
