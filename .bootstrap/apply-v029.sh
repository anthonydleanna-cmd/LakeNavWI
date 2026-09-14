#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.29</span></div>', s, count=1)

# Track a course calculated from actual GPS displacement. This is intentionally separate
# from the Android-reported bearing so we can weight real movement much more heavily.
state_anchor="  let gpsBearingAccuracy = null;"
if state_anchor not in s:
    raise SystemExit('gpsBearingAccuracy state anchor not found')
s=s.replace(state_anchor, state_anchor+"\n  let movementCourse = null;\n  let movementCourseAt = 0;\n  let movementCourseConfidence = 0;",1)

old_heading=r'''  function headingInputs() {
    const gpsBearing = currentLoc && Number.isFinite(Number(currentLoc.bearing)) && Number(currentLoc.bearing) >= 0 ? normalizeDegrees(currentLoc.bearing) : null;
    const speed = currentLoc && Number.isFinite(Number(currentLoc.speed)) ? Number(currentLoc.speed) : -1;
    const gpsTrusted = gpsBearing != null && speed >= 1.8 && (gpsBearingAccuracy == null || gpsBearingAccuracy < 35);
    const gpsUsable = gpsBearing != null && speed >= 1.2 && (gpsBearingAccuracy == null || gpsBearingAccuracy < 50);
    const compass = nativeTrueHeading != null ? normalizeDegrees(nativeTrueHeading) : null;
    return { gpsBearing, speed, gpsTrusted, gpsUsable, compass };
  }

  function activeHeading() {
    const h = headingInputs();
    if (headingMode === 'gps') {
      if (h.gpsUsable) return { degrees: h.gpsBearing, source: 'GPS course' };
      return null;
    }
    if (headingMode === 'compass') {
      return h.compass != null ? { degrees: h.compass, source: 'True compass' } : null;
    }
    if (h.gpsTrusted) return { degrees: h.gpsBearing, source: 'GPS course' };
    if (h.compass != null) return { degrees: h.compass, source: 'True compass' };
    if (h.gpsUsable) return { degrees: h.gpsBearing, source: 'GPS course' };
    return null;
  }
'''
new_heading=r'''  function weightedHeading(parts) {
    let x=0, y=0, total=0;
    (parts||[]).forEach(part => {
      if (!part || part.deg == null || !Number.isFinite(Number(part.weight)) || Number(part.weight) <= 0) return;
      const r=normalizeDegrees(part.deg)*Math.PI/180;
      const w=Number(part.weight);
      x+=Math.cos(r)*w; y+=Math.sin(r)*w; total+=w;
    });
    if (!total || (Math.abs(x)<1e-8 && Math.abs(y)<1e-8)) return null;
    return normalizeDegrees(Math.atan2(y,x)*180/Math.PI);
  }

  function updateMovementCourse(previousLoc, nextLoc) {
    if (!previousLoc || !nextLoc) return;
    const dtRaw=(Number(nextLoc.timestamp)-Number(previousLoc.timestamp))/1000;
    const dt=Number.isFinite(dtRaw) && dtRaw>0 ? dtRaw : 1;
    if (dt>8) return;
    const moved=distanceMeters(previousLoc.lat,previousLoc.lon,nextLoc.lat,nextLoc.lon);
    const a1=Number.isFinite(Number(previousLoc.accuracy)) && Number(previousLoc.accuracy)>0 ? Number(previousLoc.accuracy) : 8;
    const a2=Number.isFinite(Number(nextLoc.accuracy)) && Number(nextLoc.accuracy)>0 ? Number(nextLoc.accuracy) : 8;
    const accuracy=Math.max(a1,a2);
    const reportedSpeed=Number.isFinite(Number(nextLoc.speed)) ? Math.max(0,Number(nextLoc.speed)) : 0;
    const derivedSpeed=moved/Math.max(.25,dt);
    const effectiveSpeed=Math.max(reportedSpeed,derivedSpeed);
    const minMove=Math.max(2.5,Math.min(8,accuracy*.38));
    if (moved<minMove || effectiveSpeed<0.55) return;
    const raw=bearingDegrees(previousLoc.lat,previousLoc.lon,nextLoc.lat,nextLoc.lon);
    if (!Number.isFinite(raw)) return;
    const alpha=effectiveSpeed>=3 ? .52 : (effectiveSpeed>=1.5 ? .40 : .28);
    if (movementCourse == null || !Number.isFinite(movementCourse)) movementCourse=normalizeDegrees(raw);
    else movementCourse=normalizeDegrees(movementCourse + shortestSignedAngle(movementCourse,raw)*alpha);
    movementCourseAt=Date.now();
    movementCourseConfidence=Math.max(.35,Math.min(1,(moved/minMove)*.32 + effectiveSpeed*.16));
  }

  function headingInputs() {
    const gpsBearing = currentLoc && Number.isFinite(Number(currentLoc.bearing)) && Number(currentLoc.bearing) >= 0 ? normalizeDegrees(currentLoc.bearing) : null;
    const speed = currentLoc && Number.isFinite(Number(currentLoc.speed)) ? Math.max(0,Number(currentLoc.speed)) : 0;
    const gpsTrusted = gpsBearing != null && speed >= 1.0 && (gpsBearingAccuracy == null || gpsBearingAccuracy < 45);
    const gpsUsable = gpsBearing != null && speed >= 0.65 && (gpsBearingAccuracy == null || gpsBearingAccuracy < 65);
    const compass = nativeTrueHeading != null ? normalizeDegrees(nativeTrueHeading) : null;
    const movementAge=movementCourseAt ? Date.now()-movementCourseAt : 1e9;
    const movement = movementCourse != null && movementAge < 15000 ? normalizeDegrees(movementCourse) : null;
    return { gpsBearing, speed, gpsTrusted, gpsUsable, compass, movement, movementAge, movementConfidence:movementCourseConfidence };
  }

  function activeHeading() {
    const h = headingInputs();
    if (headingMode === 'compass') {
      return h.compass != null ? { degrees: h.compass, source: 'True compass' } : null;
    }

    // Forced GPS still uses displacement-derived course first: it is the clearest expression
    // of where the boat is actually traveling, then Android's GPS bearing is blended in lightly.
    if (headingMode === 'gps') {
      if (h.movement != null) {
        const deg=weightedHeading([{deg:h.movement,weight:.86},{deg:h.gpsBearing,weight:h.gpsUsable?.14:0}]);
        return deg == null ? null : { degrees:deg, source:'GPS movement' };
      }
      if (h.gpsUsable) return { degrees:h.gpsBearing, source:'GPS course' };
      return null;
    }

    // AUTO: once the device is actually moving, phone orientation should have almost no say
    // in the navigation camera. Real displacement is ~85%, Android GPS bearing ~15%.
    if (h.movement != null && (h.speed >= .55 || h.movementAge < 6500)) {
      const deg=weightedHeading([
        {deg:h.movement,weight:.85},
        {deg:h.gpsBearing,weight:h.gpsUsable?.15:0}
      ]);
      if (deg != null) return { degrees:deg, source:'GPS movement' };
    }
    if (h.gpsTrusted) {
      const deg=weightedHeading([{deg:h.gpsBearing,weight:.92},{deg:h.compass,weight:h.speed<1.0?.08:0}]);
      return { degrees:deg == null ? h.gpsBearing : deg, source:'GPS course' };
    }
    // When stopped, keep the last traveled course briefly rather than spinning the map with
    // every phone movement. Compass becomes the fallback only after movement course is stale.
    if (h.movement != null && h.movementAge < 15000) return { degrees:h.movement, source:'GPS movement' };
    if (h.compass != null) return { degrees:h.compass, source:'True compass' };
    if (h.gpsUsable) return { degrees:h.gpsBearing, source:'GPS course' };
    return null;
  }
'''
if old_heading not in s:
    raise SystemExit('headingInputs/activeHeading block not found')
s=s.replace(old_heading,new_heading,1)

# Motion-based headings get responsive but damped smoothing. Compass is deliberately much slower.
old_smooth=r'''    const deadband = source === 'GPS course' ? 1.0 : 2.2;
    if (Math.abs(delta) < deadband) return renderedHeading;

    // The phone compass can jump indoors or near metal. Limit how much one sample can move the visual arrow.
    const maxStep = source === 'GPS course' ? 18 : 8;
    delta = Math.max(-maxStep, Math.min(maxStep, delta));
    const alpha = source === 'GPS course' ? 0.34 : 0.18;
'''
new_smooth=r'''    const motionBased = source === 'GPS course' || source === 'GPS movement';
    const deadband = motionBased ? 1.3 : 3.5;
    if (Math.abs(delta) < deadband) return renderedHeading;

    // Movement course is allowed to react; phone compass is intentionally damped heavily so
    // rotating/tilting the handset does not whip the whole navigation chart around.
    const maxStep = motionBased ? 14 : 5;
    delta = Math.max(-maxStep, Math.min(maxStep, delta));
    const alpha = motionBased ? 0.30 : 0.10;
'''
if old_smooth not in s:
    raise SystemExit('smoothDisplayHeading block not found')
s=s.replace(old_smooth,new_smooth,1)

# Update movement course before replacing currentLoc so each GPS fix can be compared to the last one.
old_loc=r'''  window.onNativeLocation = function (lat, lon, accuracy, speed, bearing, timestamp, bearingAccuracy) {
    gpsBearingAccuracy = Number.isFinite(Number(bearingAccuracy)) && Number(bearingAccuracy) >= 0 ? Number(bearingAccuracy) : null;
    currentLoc = { lat, lon, accuracy, speed, bearing, timestamp, bearingAccuracy: gpsBearingAccuracy };
'''
new_loc=r'''  window.onNativeLocation = function (lat, lon, accuracy, speed, bearing, timestamp, bearingAccuracy) {
    const previousLoc=currentLoc ? Object.assign({},currentLoc) : null;
    gpsBearingAccuracy = Number.isFinite(Number(bearingAccuracy)) && Number(bearingAccuracy) >= 0 ? Number(bearingAccuracy) : null;
    const nextLoc={ lat, lon, accuracy, speed, bearing, timestamp, bearingAccuracy: gpsBearingAccuracy };
    updateMovementCourse(previousLoc,nextLoc);
    currentLoc = nextLoc;
'''
if old_loc not in s:
    raise SystemExit('onNativeLocation anchor not found')
s=s.replace(old_loc,new_loc,1)

# Put the GPS marker at a fixed lower-center screen anchor (~76% height) instead of varying
# its apparent screen position with speed/map overscan. Pixel scale is derived from Leaflet zoom.
pattern=r"  function perspectiveCenterLatLng\(\) \{.*?\n  \}\n\n  function ensureOperationalCourseUp\(\) \{"
match=re.search(pattern,s,flags=re.S)
if not match:
    raise SystemExit('perspectiveCenterLatLng block not found')
replacement=r'''  function perspectiveCenterLatLng() {
    if (!map || !currentLoc || !navigationPerspectiveActive()) return currentLoc ? [currentLoc.lat,currentLoc.lon] : null;
    const h=activeHeading();
    if (!h) return [currentLoc.lat,currentLoc.lon];
    let aheadM=220;
    try {
      const wrap=$('mapWrap');
      const z=map.getZoom();
      const c=map.getCenter();
      const cp=map.project(c,z);
      const north=map.unproject(L.point(cp.x,cp.y-100),z);
      const metersPerPx=Math.max(.01,distanceMeters(c.lat,c.lng,north.lat,north.lng)/100);
      const visibleHeight=wrap ? Math.max(320,wrap.clientHeight) : Math.max(320,map.getSize().y);
      const aheadPx=visibleHeight*.26; // GPS marker stays near 76% of the visible screen height.
      aheadM=Math.max(55,Math.min(1500,metersPerPx*aheadPx));
    } catch(e) {}
    const end=destinationPoint(currentLoc.lat,currentLoc.lon,h.degrees,aheadM);
    return [end[0],end[1]];
  }

  function ensureOperationalCourseUp() {'''
s=s[:match.start()]+replacement+s[match.end():]

# When the user manually drags a rotated Leaflet map, CSS rotation makes touch direction feel wrong.
# Temporarily render manual free-pan North Up; pressing GPS/Center restores Course Up follow.
s=s.replace("    const target = orientationMode === 'courseup' && displayHeading != null ? displayHeading : 0;",
            "    const courseUpVisual = orientationMode === 'courseup' && !(operationalNavigationActive() && !navFollowMode);\n    const target = courseUpVisual && displayHeading != null ? displayHeading : 0;",1)
s=s.replace("    const visualAngle = orientationMode === 'courseup' ? mapRotationDeg : 0;",
            "    const visualAngle = courseUpVisual ? mapRotationDeg : 0;",1)
s=s.replace("    map.on('dragstart', () => { navFollowMode=false; });",
            "    map.on('dragstart', () => { navFollowMode=false; applyMapOrientationWithHeading(null); if($('chartChip')) $('chartChip').textContent='Free pan • tap GPS to resume'; });",1)

# Smooth the follow translation between GPS fixes instead of jumping the chart.
s=s.replace("    if (target) map.panTo(target,{animate:false,noMoveStart:true});",
            "    if (target) map.panTo(target,{animate:true,duration:.48,easeLinearity:.20,noMoveStart:true});",1)

# Keep the GPS anchor fixed while the oversized map rotates. With -34% inset / 168% canvas,
# 65.5% of the map element corresponds to about 76% down the visible map wrapper.
css='''
/* v0.29 stable lower-center navigation anchor */
#mapWrap.courseUp2d #map,
#mapWrap.navPerspective2d #map { transform-origin:50% 65.5%; }
'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

# Updated heading-source explanation.
s=s.replace('Auto is recommended: GPS course is used when moving fast enough for a stable course; the phone true-heading compass is used while slow or stopped. Forced GPS intentionally waits for movement instead of pretending a stationary GPS bearing is reliable.',
            'Auto is recommended: actual GPS displacement is the primary heading while moving, with Android GPS bearing blended in lightly. Phone compass is mainly a stopped/last-resort fallback so rotating the handset does not whip the navigation map around.',1)
s=s.replace('Wind overlay off. Auto heading uses GPS course when moving and the true compass when slow/stopped.',
            'Wind overlay off. Auto heading prioritizes actual GPS movement; phone compass is mainly a stopped fallback.',1)

p.write_text(s)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.29 features' not in r:
    insert='''\n## Version 0.29 features\n\n### Stable movement-first navigation camera\n- Course Up now derives its primary heading from actual displacement between GPS fixes. While moving, that movement course carries about 85% of the heading decision and Android GPS bearing provides a light secondary input; phone compass is largely removed from the moving camera.\n- The last reliable movement course is held briefly when slowing or stopping so the chart does not spin simply because the phone is turned in the user's hand.\n- Heading smoothing is tuned separately for movement and compass data: movement remains responsive, while compass-driven changes are heavily damped.\n- The GPS navigation marker is targeted to a fixed lower-center screen anchor around 76% of map height. The perspective center is calculated in screen pixels at the current Leaflet zoom so the vessel stays in a consistent place while more water remains visible ahead.\n- The oversized Course Up chart now rotates around that same lower-center anchor, reducing the sideways orbit of the vessel as heading changes.\n- Follow translation animates between GPS fixes instead of snapping.\n- Manual map dragging temporarily becomes an upright free-pan view so the map moves in the same direction as the finger; tapping GPS/Center resumes Course Up follow.\n'''
    pos=r.find('\n## Version 0.28 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 29/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.29.0'/" app/build.gradle
grep -q 'v0.29' app/src/main/assets/index.html
grep -q 'movementCourse' app/src/main/assets/index.html
grep -q '65.5%' app/src/main/assets/index.html
grep -q 'Version 0.29 features' README.md
printf 'LakeNav WI v0.29 stable movement navigation camera applied.\n'
