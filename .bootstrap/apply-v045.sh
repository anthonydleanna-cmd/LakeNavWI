#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.45</span></div>', s, count=1)

# GPS quality state. Recent rejections are time-windowed so an old bad fix does not permanently
# lower the indicator for the rest of the trip.
state_anchor="  let gpsTransientOutliersRejected = 0;\n  let trackDirectionalOutliersRejected = 0;"
if state_anchor not in s:
    raise SystemExit('GPS rejection state anchor not found')
s=s.replace(state_anchor, state_anchor+"\n  let gpsLastAcceptedAt = 0;\n  let gpsRecentRejectTimes = [];\n  let gpsRecentTrackRejectTimes = [];\n  let gpsQualityState = 'NO FIX';\n  let gpsQualityTimer = null;",1)

# Compact quality pill in the main status bar.
html_anchor='''      <div id="gpsState">Waiting for GPS...</div>\n'''
html_new='''      <div id="gpsState">Waiting for GPS...</div>\n      <button id="gpsQualityChip" class="gpsQualityChip noFix" type="button" aria-label="GPS quality"><span class="gpsQualityDot"></span><span id="gpsQualityText">NO FIX</span></button>\n'''
if html_anchor not in s:
    raise SystemExit('gpsState HTML anchor not found')
s=s.replace(html_anchor,html_new,1)

# Detail sheet opened by tapping the pill.
sheet_anchor='<div class="sheetBackdrop" id="trackSheet">'
gps_sheet='''<div class="sheetBackdrop" id="gpsQualitySheet">\n  <div class="sheet">\n    <div class="sheetHeader"><h2>GPS quality</h2><button class="closeBtn" data-close="gpsQualitySheet">x</button></div>\n    <div class="card" style="margin:0 0 12px">\n      <div class="gpsQualityHero"><span class="gpsQualityDot" id="gpsQualityHeroDot"></span><div><strong id="gpsQualityHeroText">NO FIX</strong><div class="muted" id="gpsQualityReason">Waiting for a current GPS fix.</div></div></div>\n    </div>\n    <div class="card gpsQualityDetails" style="margin:0">\n      <div><span>Accuracy</span><strong id="gpsQualityAccuracy">--</strong></div>\n      <div><span>Fix age</span><strong id="gpsQualityAge">--</strong></div>\n      <div><span>Speed</span><strong id="gpsQualitySpeed">--</strong></div>\n      <div><span>Bearing accuracy</span><strong id="gpsQualityBearing">--</strong></div>\n      <div><span>Course stability</span><strong id="gpsQualityCourse">--</strong></div>\n      <div><span>Rejected fixes (30 sec)</span><strong id="gpsQualityRejects">0</strong></div>\n      <div><span>Track outliers (30 sec)</span><strong id="gpsQualityTrackRejects">0</strong></div>\n    </div>\n    <p class="muted" style="margin-top:10px">Quality is estimated from Android location accuracy, fix freshness, course stability, and recent rejected GPS jumps. It is not a satellite-count meter.</p>\n  </div>\n</div>\n\n'''
if sheet_anchor not in s:
    raise SystemExit('trackSheet anchor not found')
s=s.replace(sheet_anchor,gps_sheet+sheet_anchor,1)

# GPS quality calculation and UI. GOOD requires a fresh accurate fix; recent rejected position jumps
# or degraded bearing/course stability lower the state without making a single old event permanent.
func_anchor='  window.onNativeLocation = function (lat, lon, accuracy, speed, bearing, timestamp, bearingAccuracy) {'
quality_funcs=r'''  function pruneGpsQualityRejects(now=Date.now()) {
    const cutoff=now-30000;
    gpsRecentRejectTimes=gpsRecentRejectTimes.filter(t=>t>=cutoff);
    gpsRecentTrackRejectTimes=gpsRecentTrackRejectTimes.filter(t=>t>=cutoff);
  }

  function recordGpsQualityReject(kind) {
    const now=Date.now();
    if (kind==='track') gpsRecentTrackRejectTimes.push(now);
    else gpsRecentRejectTimes.push(now);
    pruneGpsQualityRejects(now);
    updateGpsQualityUi(true);
  }

  function gpsQualitySnapshot() {
    const now=Date.now();
    pruneGpsQualityRejects(now);
    const hasFix=!!currentLoc && gpsLastAcceptedAt>0;
    const ageSec=hasFix ? Math.max(0,(now-gpsLastAcceptedAt)/1000) : Infinity;
    const accuracyM=hasFix && Number.isFinite(Number(currentLoc.accuracy)) && Number(currentLoc.accuracy)>=0 ? Number(currentLoc.accuracy) : Infinity;
    const speedMps=hasFix && Number.isFinite(Number(currentLoc.speed)) && Number(currentLoc.speed)>=0 ? Number(currentLoc.speed) : 0;
    const bearingAcc=Number.isFinite(Number(gpsBearingAccuracy)) && Number(gpsBearingAccuracy)>=0 ? Number(gpsBearingAccuracy) : null;
    const movementFresh=movementCourseAt && now-movementCourseAt<6000;
    const courseConfidence=movementFresh ? Math.max(0,Math.min(1,Number(movementCourseConfidence)||0)) : null;
    const recentRejects=gpsRecentRejectTimes.length;
    const recentTrackRejects=gpsRecentTrackRejectTimes.length;

    let state='GOOD';
    let reason='Fresh, accurate GPS fix.';
    if (!hasFix || ageSec>12) {
      state='NO FIX'; reason=!hasFix ? 'Waiting for a current GPS fix.' : 'GPS fix is stale.';
    } else if (ageSec>6 || accuracyM>25 || recentRejects>=3 || (speedMps>1.5 && bearingAcc!=null && bearingAcc>80)) {
      state='POOR';
      if (recentRejects>=3) reason='Several GPS jumps were rejected recently.';
      else if (accuracyM>25) reason='Reported GPS accuracy is low.';
      else if (ageSec>6) reason='GPS updates are arriving too slowly.';
      else reason='Course/bearing quality is unstable.';
    } else if (ageSec>3 || accuracyM>12 || recentRejects>=1 || (speedMps>1.5 && bearingAcc!=null && bearingAcc>50) || (speedMps>1.5 && courseConfidence!=null && courseConfidence<.45)) {
      state='FAIR';
      if (recentRejects>=1) reason='A recent GPS jump was rejected.';
      else if (accuracyM>12) reason='Usable fix, but position accuracy could be better.';
      else if (ageSec>3) reason='Fix is usable but not very fresh.';
      else reason='Course/bearing stability is moderate.';
    }
    return {state,reason,ageSec,accuracyM,speedMps,bearingAcc,courseConfidence,recentRejects,recentTrackRejects};
  }

  function updateGpsQualityUi(force=false) {
    const snap=gpsQualitySnapshot();
    if (!force && !appPageVisible && !($('gpsQualitySheet') && $('gpsQualitySheet').classList.contains('open'))) return;
    gpsQualityState=snap.state;
    const chip=$('gpsQualityChip');
    if (chip) {
      chip.classList.remove('good','fair','poor','noFix');
      chip.classList.add(snap.state==='GOOD'?'good':snap.state==='FAIR'?'fair':snap.state==='POOR'?'poor':'noFix');
      chip.title='GPS '+snap.state+' • '+snap.reason;
    }
    setTextIfChanged('gpsQualityText',snap.state);
    const hero=$('gpsQualityHeroText'); if(hero) hero.textContent=snap.state;
    const reason=$('gpsQualityReason'); if(reason) reason.textContent=snap.reason;
    const heroDot=$('gpsQualityHeroDot');
    if (heroDot) {
      heroDot.className='gpsQualityDot '+(snap.state==='GOOD'?'good':snap.state==='FAIR'?'fair':snap.state==='POOR'?'poor':'noFix');
    }
    const acc=$('gpsQualityAccuracy'); if(acc) acc.textContent=Number.isFinite(snap.accuracyM)?Math.round(snap.accuracyM*M_TO_FT)+' ft':'--';
    const age=$('gpsQualityAge'); if(age) age.textContent=Number.isFinite(snap.ageSec)?(snap.ageSec<10?snap.ageSec.toFixed(1):Math.round(snap.ageSec))+' sec':'--';
    const spd=$('gpsQualitySpeed'); if(spd) spd.textContent=(snap.speedMps*MPS_TO_MPH).toFixed(snap.speedMps*MPS_TO_MPH<10?1:0)+' mph';
    const ba=$('gpsQualityBearing'); if(ba) ba.textContent=snap.bearingAcc==null?'--':Math.round(snap.bearingAcc)+'°';
    const cc=$('gpsQualityCourse'); if(cc) cc.textContent=snap.courseConfidence==null?'--':Math.round(snap.courseConfidence*100)+'%';
    const rr=$('gpsQualityRejects'); if(rr) rr.textContent=String(snap.recentRejects);
    const tr=$('gpsQualityTrackRejects'); if(tr) tr.textContent=String(snap.recentTrackRejects);
  }

'''
if func_anchor not in s:
    raise SystemExit('onNativeLocation anchor not found')
s=s.replace(func_anchor,quality_funcs+func_anchor,1)

# A rejected raw GPS fix immediately contributes to the quality state.
old_reject="""    if (previousLoc && isTransientGpsOutlier(previousLoc,nextLoc)) {
      gpsTransientOutliersRejected++;
      if (window.console && console.debug) console.debug('LakeNav ignored transient GPS outlier', gpsTransientOutliersRejected);
      return;
    }
"""
new_reject="""    if (previousLoc && isTransientGpsOutlier(previousLoc,nextLoc)) {
      gpsTransientOutliersRejected++;
      recordGpsQualityReject('gps');
      if (window.console && console.debug) console.debug('LakeNav ignored transient GPS outlier', gpsTransientOutliersRejected);
      return;
    }
"""
if old_reject not in s:
    raise SystemExit('transient rejection block not found')
s=s.replace(old_reject,new_reject,1)

# Mark the time the accepted location actually reached LakeNav, then refresh the quality pill.
accept_anchor="""    updateMovementCourse(previousLoc,nextLoc);
    currentLoc = nextLoc;
    updateNavigationFilteredFix(nextLoc);
"""
accept_new="""    updateMovementCourse(previousLoc,nextLoc);
    currentLoc = nextLoc;
    gpsLastAcceptedAt=Date.now();
    updateNavigationFilteredFix(nextLoc);
    updateGpsQualityUi(true);
"""
if accept_anchor not in s:
    raise SystemExit('accepted GPS fix anchor not found')
s=s.replace(accept_anchor,accept_new,1)

# Track-only vertex rejection is useful diagnostic context, but is displayed separately so it does
# not automatically downgrade the core GPS indicator as strongly as a rejected raw location fix.
track_reject="""        trackDirectionalOutliersRejected++;
        if (window.console && console.debug) console.debug('LakeNav rejected track vertex outlier', trackDirectionalOutliersRejected);
        return;
"""
track_new="""        trackDirectionalOutliersRejected++;
        recordGpsQualityReject('track');
        if (window.console && console.debug) console.debug('LakeNav rejected track vertex outlier', trackDirectionalOutliersRejected);
        return;
"""
if track_reject not in s:
    raise SystemExit('track rejection block not found')
s=s.replace(track_reject,track_new,1)

# Bind tap-to-details and a light 1 Hz freshness refresh so stale-fix status changes even if no new
# location callback arrives.
bind_anchor="""    $('orientationBtn').addEventListener('click', toggleOrientationMode);
"""
bind_new="""    $('orientationBtn').addEventListener('click', toggleOrientationMode);
    $('gpsQualityChip').addEventListener('click', () => { updateGpsQualityUi(true); openSheet('gpsQualitySheet'); });
"""
if bind_anchor not in s:
    raise SystemExit('orientation binding anchor not found')
s=s.replace(bind_anchor,bind_new,1)

startup_anchor="""  renderTrackLog();
  syncNavigationState('startup');
})();
"""
startup_new="""  renderTrackLog();
  updateGpsQualityUi(true);
  if (gpsQualityTimer) clearInterval(gpsQualityTimer);
  gpsQualityTimer=setInterval(()=>updateGpsQualityUi(false),1000);
  syncNavigationState('startup');
})();
"""
if startup_anchor not in s:
    raise SystemExit('startup anchor not found')
s=s.replace(startup_anchor,startup_new,1)

css='''
/* v0.45 GPS quality indicator */
.gpsQualityChip { margin-top:5px; display:inline-flex; align-items:center; gap:6px; border:1px solid rgba(255,255,255,.28); border-radius:999px; padding:4px 8px; background:rgba(4,28,43,.28); color:#fff; font-size:10px; font-weight:900; letter-spacing:.06em; line-height:1; }
.gpsQualityChip .gpsQualityDot,.gpsQualityHero .gpsQualityDot { width:8px; height:8px; border-radius:50%; background:#9eabb2; box-shadow:0 0 0 3px rgba(158,171,178,.16); flex:0 0 auto; }
.gpsQualityChip.good .gpsQualityDot,.gpsQualityDot.good { background:#2fc36b; box-shadow:0 0 0 3px rgba(47,195,107,.17); }
.gpsQualityChip.fair .gpsQualityDot,.gpsQualityDot.fair { background:#f0ad2e; box-shadow:0 0 0 3px rgba(240,173,46,.17); }
.gpsQualityChip.poor .gpsQualityDot,.gpsQualityDot.poor { background:#e55345; box-shadow:0 0 0 3px rgba(229,83,69,.17); }
.gpsQualityChip.noFix .gpsQualityDot,.gpsQualityDot.noFix { background:#9eabb2; box-shadow:0 0 0 3px rgba(158,171,178,.16); }
.gpsQualityHero { display:flex; align-items:center; gap:12px; }
.gpsQualityHero .gpsQualityDot { width:15px; height:15px; }
.gpsQualityHero strong { font-size:21px; color:#15384c; }
.gpsQualityDetails { display:grid; grid-template-columns:1fr; gap:0; }
.gpsQualityDetails>div { display:flex; justify-content:space-between; gap:14px; padding:9px 0; border-bottom:1px solid rgba(20,58,78,.08); }
.gpsQualityDetails>div:last-child { border-bottom:0; }
.gpsQualityDetails span { color:#71818a; font-size:12px; }
.gpsQualityDetails strong { color:#15384c; font-size:12px; }
'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.45 features' not in r:
    insert='''\n## Version 0.45 features\n\n### GPS quality indicator\n- Adds a compact GOOD / FAIR / POOR / NO FIX GPS quality pill to the main status bar.\n- Quality considers reported horizontal accuracy, age of the last accepted fix, bearing/course stability while moving, and recent raw GPS jumps rejected by LakeNav.\n- Tapping the indicator opens a diagnostic sheet with accuracy, fix age, speed, bearing accuracy, course stability, recent rejected fixes, and recent track-outlier rejections.\n- Recent rejection history is limited to a rolling 30-second window so one old GPS glitch does not permanently lower the quality state.\n- The quality display is diagnostic only; it does not change the v0.41 GPS filtering, v0.42 free-pan behavior, or v0.44 cross-track guidance.\n'''
    pos=r.find('\n## Version 0.44 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)

p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 45/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.45.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v045-inline.js',s)"
node --check /tmp/lakenav-v045-inline.js
grep -q 'v0.45' app/src/main/assets/index.html
grep -q 'gpsQualitySnapshot' app/src/main/assets/index.html
grep -q 'gpsQualityChip' app/src/main/assets/index.html
grep -q 'Version 0.45 features' README.md
printf 'LakeNav WI v0.45 GPS quality indicator applied.\n'
