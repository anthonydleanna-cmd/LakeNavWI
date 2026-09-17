#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

python3 - <<'PY'
from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()

def replace_once(old,new,label):
    global s
    if old not in s:
        raise SystemExit(f'v0.84 anchor not found: {label}')
    s=s.replace(old,new,1)

replace_once(
    '<div id="brand">LakeNav WI <span class="versionPill">v0.83</span></div>',
    '<div id="brand">LakeNav WI <span class="versionPill">v0.84</span></div>',
    'brand')

replace_once(
'''      <div class="tripSummaryHero"><div><strong>Track saved</strong><div class="muted" id="tripSummaryDate">--</div></div><span class="trackRecDot"></span></div>''',
'''      <div class="tripSummaryHero"><div><strong id="tripSummaryState">Track saved</strong><div class="muted" id="tripSummaryDate">--</div><div class="muted" id="tripSummarySaveNote"></div></div><span class="trackRecDot"></span></div>''',
    'trip summary status')

old_already='''  function trackAlreadyArchived(points) {
    if (!points || points.length<2 || !trackHistory.length) return false;
    const first=points[0], last=points[points.length-1];
    return trackHistory.some(h=>Math.abs(Number(h.startTime)-Number(first.time||0))<1500 && Math.abs(Number(h.endTime)-Number(last.time||0))<1500);
  }
'''
new_already='''  function trackAlreadyArchived(points) {
    if (!points || points.length<2 || !trackHistory.length) return false;
    const first=points[0], last=points[points.length-1];
    const firstTime=Number(first&&first.time)||0, lastTime=Number(last&&last.time)||0;
    return trackHistory.some(h=>{
      const hp=Array.isArray(h&&h.points)?h.points:(Array.isArray(h&&h.pts)?h.pts:[]);
      if (hp.length<2) return false;
      const hf=hp[0], hl=hp[hp.length-1];
      const hFirstTime=Number(h.pointStartTime)||Number(hf&&hf.time)||Number(h.startTime)||0;
      const hLastTime=Number(h.pointEndTime)||Number(hl&&hl.time)||Number(h.endTime)||0;
      const timeMatch=(!firstTime||!hFirstTime||Math.abs(hFirstTime-firstTime)<5000) && (!lastTime||!hLastTime||Math.abs(hLastTime-lastTime)<5000);
      if (!timeMatch) return false;
      const startNear=Number.isFinite(Number(hf&&hf.lat))&&Number.isFinite(Number(hf&&hf.lon)) ? distanceMeters(Number(hf.lat),Number(hf.lon),Number(first.lat),Number(first.lon))<35 : true;
      const endNear=Number.isFinite(Number(hl&&hl.lat))&&Number.isFinite(Number(hl&&hl.lon)) ? distanceMeters(Number(hl.lat),Number(hl.lon),Number(last.lat),Number(last.lon))<35 : true;
      return startNear&&endNear;
    });
  }
'''
replace_once(old_already,new_already,'trackAlreadyArchived')

old_archive='''  function archiveCurrentTrack(summary=null) {
    if (!trackPoints || trackPoints.length<2 || trackAlreadyArchived(trackPoints)) { currentTrackArchived=true; return; }
    const pts=compactHistoryPoints(trackPoints);
    if (pts.length<2) return;
    const start=Number(summary&&summary.startTime)||recordingStartedAt||Number(trackPoints[0].time)||Date.now();
    const end=Number(summary&&summary.endTime)||Number(trackPoints[trackPoints.length-1].time)||Date.now();
    trackHistory.push({
      id:'th'+end+'_'+Math.random().toString(36).slice(2,7),
      name:new Date(start).toLocaleDateString([], {month:'short',day:'numeric',year:'numeric'})+' • '+new Date(start).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'}),
      startTime:start,
      endTime:end,
      distanceM:Number(summary&&summary.distanceM)||trackHistoryDistance(trackPoints),
      elapsedMs:Number(summary&&summary.elapsedMs)||Math.max(0,end-start),
      movingTimeMs:Number(summary&&summary.movingTimeMs)||0,
      pausedTimeMs:Number(summary&&summary.pausedTimeMs)||0,
      stoppedTimeMs:Number(summary&&summary.stoppedTimeMs)||0,
      avgMovingSpeedMps:Number(summary&&summary.avgMovingSpeedMps)||0,
      maxSpeedMps:Number(summary&&summary.maxSpeedMps)||0,
      color:trackHistoryPalette(trackHistory.length),
      visible:true,
      points:pts
    });
    currentTrackArchived=true;
    saveTrackHistory();
    renderTrackHistoryOverlays();
    renderTrackHistorySettings();
    if ($('lakeLibrarySheet') && $('lakeLibrarySheet').classList.contains('open')) setTimeout(()=>syncRecentlyBoatedFromTrackLogs(false),0);
  }
'''
new_archive='''  function archiveCurrentTrack(summary=null) {
    if (!trackPoints || trackPoints.length<2) { currentTrackArchived=false; return null; }
    if (trackAlreadyArchived(trackPoints)) { currentTrackArchived=true; return {existing:true}; }
    const pts=compactHistoryPoints(trackPoints);
    if (pts.length<2) { currentTrackArchived=false; return null; }
    const pointStartTime=Number(trackPoints[0]&&trackPoints[0].time)||0;
    const pointEndTime=Number(trackPoints[trackPoints.length-1]&&trackPoints[trackPoints.length-1].time)||0;
    const start=Number(summary&&summary.startTime)||recordingStartedAt||pointStartTime||Date.now();
    const end=Number(summary&&summary.endTime)||pointEndTime||Date.now();
    const item={
      id:'th'+end+'_'+Math.random().toString(36).slice(2,7),
      name:new Date(start).toLocaleDateString([], {month:'short',day:'numeric',year:'numeric'})+' • '+new Date(start).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'}),
      startTime:start,
      endTime:end,
      pointStartTime:pointStartTime||start,
      pointEndTime:pointEndTime||end,
      distanceM:Number(summary&&summary.distanceM)||trackHistoryDistance(trackPoints),
      elapsedMs:Number(summary&&summary.elapsedMs)||Math.max(0,end-start),
      movingTimeMs:Number(summary&&summary.movingTimeMs)||0,
      pausedTimeMs:Number(summary&&summary.pausedTimeMs)||0,
      stoppedTimeMs:Number(summary&&summary.stoppedTimeMs)||0,
      avgMovingSpeedMps:Number(summary&&summary.avgMovingSpeedMps)||0,
      maxSpeedMps:Number(summary&&summary.maxSpeedMps)||0,
      color:trackHistoryPalette(trackHistory.length),
      visible:true,
      points:pts
    };
    trackHistory.push(item);
    currentTrackArchived=true;
    saveTrackHistory();
    renderTrackHistoryOverlays();
    renderTrackHistorySettings();
    if ($('lakeLibrarySheet') && $('lakeLibrarySheet').classList.contains('open')) setTimeout(()=>syncRecentlyBoatedFromTrackLogs(false),0);
    return item;
  }

  function normalizeTrackHistoryEntries() {
    const legacy=loadJson('trackLog', []);
    const source=(Array.isArray(trackHistory)?trackHistory:[]).concat(legacy);
    const normalized=[];
    source.forEach((raw,index)=>{
      if (!raw) return;
      const sourcePts=Array.isArray(raw.points)?raw.points:(Array.isArray(raw.pts)?raw.pts:[]);
      const pts=compactHistoryPoints(sourcePts);
      if (pts.length<2) return;
      const pointStartTime=Number(raw.pointStartTime)||Number(pts[0]&&pts[0].time)||0;
      const pointEndTime=Number(raw.pointEndTime)||Number(pts[pts.length-1]&&pts[pts.length-1].time)||0;
      const start=Number(raw.startTime)||pointStartTime||Number(raw.savedAt)||Date.now();
      const end=Number(raw.endTime)||pointEndTime||Number(raw.savedAt)||start;
      const item={
        id:String(raw.id||('th'+end+'_m'+index)),
        name:String(raw.name||new Date(start).toLocaleDateString([], {month:'short',day:'numeric',year:'numeric'})+' • '+new Date(start).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'})),
        startTime:start,
        endTime:end,
        pointStartTime:pointStartTime||start,
        pointEndTime:pointEndTime||end,
        distanceM:Number(raw.distanceM)||trackHistoryDistance(pts),
        elapsedMs:Number(raw.elapsedMs)||Math.max(0,end-start),
        movingTimeMs:Number(raw.movingTimeMs)||0,
        pausedTimeMs:Number(raw.pausedTimeMs)||0,
        stoppedTimeMs:Number(raw.stoppedTimeMs)||0,
        avgMovingSpeedMps:Number(raw.avgMovingSpeedMps)||0,
        maxSpeedMps:Number(raw.maxSpeedMps)||0,
        color:raw.color||trackHistoryPalette(normalized.length),
        visible:raw.visible!==false,
        points:pts
      };
      const duplicate=normalized.some(existing=>{
        const ep=existing.points||[];
        if(ep.length<2) return false;
        const a=ep[0], b=ep[ep.length-1], c=pts[0], d=pts[pts.length-1];
        const timeMatch=Math.abs(Number(existing.pointStartTime||existing.startTime)-Number(item.pointStartTime||item.startTime))<5000 && Math.abs(Number(existing.pointEndTime||existing.endTime)-Number(item.pointEndTime||item.endTime))<5000;
        return timeMatch && distanceMeters(a.lat,a.lon,c.lat,c.lon)<35 && distanceMeters(b.lat,b.lon,d.lat,d.lon)<35;
      });
      if(!duplicate) normalized.push(item);
    });
    const changed=legacy.length>0 || normalized.length!==trackHistory.length || normalized.some((h,i)=>!trackHistory[i] || !Array.isArray(trackHistory[i].points) || !trackHistory[i].pointStartTime || !trackHistory[i].pointEndTime);
    trackHistory=normalized.slice(-120);
    if(changed) {
      saveTrackHistory();
      if(legacy.length) localStorage.removeItem('trackLog');
    }
  }

  function recoverUnarchivedTrack() {
    if (recording || !trackPoints || trackPoints.length<2 || trackAlreadyArchived(trackPoints)) return false;
    const start=Number(trackPoints[0]&&trackPoints[0].time)||Date.now();
    const end=Number(trackPoints[trackPoints.length-1]&&trackPoints[trackPoints.length-1].time)||start;
    const saved=archiveCurrentTrack({startTime:start,endTime:end,distanceM:trackHistoryDistance(trackPoints),elapsedMs:Math.max(0,end-start)});
    if(saved) {
      renderTrackLog();
      renderTrackMenu();
      return true;
    }
    return false;
  }
'''
replace_once(old_archive,new_archive,'archiveCurrentTrack')

old_render='''  function renderTripSummary(summary) {
    if (!summary) return;
    lastTripSummary=summary;
    setTextIfChanged('tripSummaryDate',new Date(summary.startTime).toLocaleDateString([], {weekday:'short',month:'short',day:'numeric',year:'numeric'}));
'''
new_render='''  function renderTripSummary(summary) {
    if (!summary) return;
    lastTripSummary=summary;
    const saved=summary.savedToHistory!==false;
    setTextIfChanged('tripSummaryState',saved?'Track saved':'Track not saved');
    setTextIfChanged('tripSummarySaveNote',saved?'Saved in Track Log.':'Not enough accepted GPS points were recorded to create a completed track.');
    setTextIfChanged('tripSummaryDate',new Date(summary.startTime).toLocaleDateString([], {weekday:'short',month:'short',day:'numeric',year:'numeric'}));
'''
replace_once(old_render,new_render,'renderTripSummary')

old_set='''  function setRecording(on) {
    if (!!on === recording) return;
    let summary=null;
    if (on) {
      if (trackPoints.length>=2 && !trackAlreadyArchived(trackPoints)) archiveCurrentTrack();
      trackPoints=[];
      trackDistanceCache=0;
      saveTrack(true);
      if (trackLine) trackLine.setLatLngs([]);
      clearTrackAgeLines();
      if (trackLiveTail) trackLiveTail.setLatLngs([]);
      recordingStartedAt=Date.now();
      trackPaused=false;
      trackPauseStartedAt=0;
      trackPausedTotalMs=0;
      trackMovingMs=0;
      trackMaxSpeedMps=0;
      trackLastStatsAt=Date.now();
      trackResumeBreakPending=false;
      lastTripSummary=null;
      currentTrackArchived=false;
    } else {
      const endTime=Date.now();
      summary=buildTripSummary(endTime);
      if (trackPaused) finalizeActivePause(endTime);
      trackPaused=false;
      trackPauseStartedAt=0;
      trackLastStatsAt=0;
      trackResumeBreakPending=false;
      saveTrack(true);
      archiveCurrentTrack(summary);
      if (trackLine) trackLine.setLatLngs([]);
      clearTrackAgeLines();
      if (trackLiveTail) trackLiveTail.setLatLngs([]);
    }
    recording = on;
    if (on) resumeNavigationFollow('track-start',false);
    else syncNavigationState('track-stop');
    $('trackBtn').classList.toggle('recording', on);
    const trackLabel = $('trackBtn').lastElementChild;
    if (trackLabel) trackLabel.textContent = 'Track';
    $('trackChip').style.display = on ? 'block' : 'none';
    $('trackChip').classList.toggle('paused',false);
    setTextIfChanged('trackPauseChipText','');
    updateTrackUi();
    renderTrackMenu();
    renderTrackLog();
    if (window.Android && Android.keepScreenOn) Android.keepScreenOn(on || !!targetId || !!activeRouteId);
    if (window.Android && Android.toast) Android.toast(on ? 'New track recording started' : (trackPoints.length>=2 ? 'Track saved to history' : 'Track recording stopped'));
    if (!on && summary) setTimeout(()=>showTripSummary(summary),40);
  }
'''
new_set='''  function setRecording(on) {
    if (!!on === recording) return;
    let summary=null;
    let savedToHistory=false;
    if (on) {
      recoverUnarchivedTrack();
      trackPoints=[];
      trackDistanceCache=0;
      saveTrack(true);
      if (trackLine) trackLine.setLatLngs([]);
      clearTrackAgeLines();
      if (trackLiveTail) trackLiveTail.setLatLngs([]);
      recordingStartedAt=Date.now();
      trackPaused=false;
      trackPauseStartedAt=0;
      trackPausedTotalMs=0;
      trackMovingMs=0;
      trackMaxSpeedMps=0;
      trackLastStatsAt=Date.now();
      trackResumeBreakPending=false;
      lastTripSummary=null;
      currentTrackArchived=false;
      if (currentLoc && Number.isFinite(Number(currentLoc.lat)) && Number.isFinite(Number(currentLoc.lon))) {
        maybeAddTrackPoint(Number(currentLoc.lat),Number(currentLoc.lon),Number(currentLoc.accuracy)||0,Date.now());
      }
    } else {
      const endTime=Date.now();
      if (!trackPaused && currentLoc && Number.isFinite(Number(currentLoc.lat)) && Number.isFinite(Number(currentLoc.lon))) {
        maybeAddTrackPoint(Number(currentLoc.lat),Number(currentLoc.lon),Number(currentLoc.accuracy)||0,endTime);
      }
      summary=buildTripSummary(endTime);
      if (trackPaused) finalizeActivePause(endTime);
      trackPaused=false;
      trackPauseStartedAt=0;
      trackLastStatsAt=0;
      trackResumeBreakPending=false;
      saveTrack(true);
      const archived=archiveCurrentTrack(summary);
      savedToHistory=!!archived || trackAlreadyArchived(trackPoints);
      summary.savedToHistory=savedToHistory;
      if (trackLine) trackLine.setLatLngs([]);
      clearTrackAgeLines();
      if (trackLiveTail) trackLiveTail.setLatLngs([]);
    }
    recording = on;
    if (on) resumeNavigationFollow('track-start',false);
    else syncNavigationState('track-stop');
    $('trackBtn').classList.toggle('recording', on);
    const trackLabel = $('trackBtn').lastElementChild;
    if (trackLabel) trackLabel.textContent = 'Track';
    $('trackChip').style.display = on ? 'block' : 'none';
    $('trackChip').classList.toggle('paused',false);
    setTextIfChanged('trackPauseChipText','');
    updateTrackUi();
    renderTrackMenu();
    renderTrackLog();
    if (window.Android && Android.keepScreenOn) Android.keepScreenOn(on || !!targetId || !!activeRouteId);
    if (window.Android && Android.toast) Android.toast(on ? 'New track recording started' : (savedToHistory ? 'Track saved to history' : 'Track not saved - not enough GPS points'));
    if (!on && summary) setTimeout(()=>showTripSummary(summary),40);
  }
'''
replace_once(old_set,new_set,'setRecording')

replace_once(
'''    $('trackLogBtn').addEventListener('click', () => { renderTrackLog(); closeSheets(); $('trackLogSheet').classList.add('open'); });''',
'''    $('trackLogBtn').addEventListener('click', () => { recoverUnarchivedTrack(); closeSheets(); openSheet('trackLogSheet'); });''',
    'track log click')

replace_once(
'''  initMap();
  renderWaypointList();''',
'''  initMap();
  normalizeTrackHistoryEntries();
  recoverUnarchivedTrack();
  renderWaypointList();''',
    'startup recovery')

p.write_text(s)
PY

sed -i "s/versionCode [0-9][0-9]*/versionCode 84/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.84.0'/" app/build.gradle

node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v084-inline.js',s)"
node --check /tmp/lakenav-v084-inline.js

grep -q 'v0.84' app/src/main/assets/index.html
grep -q 'recoverUnarchivedTrack' app/src/main/assets/index.html
grep -q 'Track not saved - not enough GPS points' app/src/main/assets/index.html
grep -q 'pointStartTime' app/src/main/assets/index.html

printf 'LakeNav WI v0.84 track-log reliability and interrupted-track recovery applied.\n'
