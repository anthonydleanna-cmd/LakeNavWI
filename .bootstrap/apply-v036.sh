#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat > /tmp/lakenav-v036.patch <<'PATCH'
--- a/app/src/main/assets/index.html
+++ b/app/src/main/assets/index.html
@@ -626,7 +626,7 @@
 <div id="app">
   <div id="statusbar">
     <div>
-      <div id="brand">LakeNav WI <span class="versionPill">v0.35</span></div>
+      <div id="brand">LakeNav WI <span class="versionPill">v0.36</span></div>
       <div id="gpsState">Waiting for GPS...</div>
     </div>
     <div id="gpsNumbers">
@@ -1139,6 +1139,7 @@
   let movementCourse = null;
   let movementCourseAt = 0;
   let movementCourseConfidence = 0;
+  let movementCourseRejected = 0;
   let movementCourseSamples = 0;
   let movementCourseSampleAt = 0;
   let navCourseAcquired = false;
@@ -1768,20 +1769,57 @@
     const effectiveSpeed=Math.max(reportedSpeed,derivedSpeed);
     const minMove=Math.max(2.5,Math.min(8,accuracy*.38));
     if (moved<minMove || effectiveSpeed<0.55) return;
+
     const raw=bearingDegrees(previousLoc.lat,previousLoc.lon,nextLoc.lat,nextLoc.lon);
     if (!Number.isFinite(raw)) return;
-    const alpha=effectiveSpeed>=3 ? .52 : (effectiveSpeed>=1.5 ? .40 : .28);
-    if (movementCourse == null || !Number.isFinite(movementCourse)) movementCourse=normalizeDegrees(raw);
-    else movementCourse=normalizeDegrees(movementCourse + shortestSignedAngle(movementCourse,raw)*alpha);
+    const reportedBearing=Number.isFinite(Number(nextLoc.bearing)) && Number(nextLoc.bearing)>=0 ? normalizeDegrees(nextLoc.bearing) : null;
+    const reportedBearingGood=reportedBearing!=null && reportedSpeed>=1.1 && (gpsBearingAccuracy==null || gpsBearingAccuracy<50);
+
+    // At useful speed the Android/GNSS course is much harder for one lateral position error to corrupt
+    // than a bearing calculated from two raw lat/lon samples. Blend toward GNSS increasingly with speed.
+    let candidate=normalizeDegrees(raw);
+    if (reportedBearingGood) {
+      const disagreement=Math.abs(shortestSignedAngle(reportedBearing,raw));
+      if (reportedSpeed>=8) {
+        candidate=disagreement>35 ? reportedBearing : weightedHeading([{deg:reportedBearing,weight:.94},{deg:raw,weight:.06}]);
+      } else if (reportedSpeed>=3) {
+        candidate=disagreement>50 ? reportedBearing : weightedHeading([{deg:reportedBearing,weight:.82},{deg:raw,weight:.18}]);
+      } else {
+        candidate=disagreement>75 ? reportedBearing : weightedHeading([{deg:reportedBearing,weight:.42},{deg:raw,weight:.58}]);
+      }
+    }
+    if (candidate==null) return;
+
+    if (movementCourse == null || !Number.isFinite(movementCourse)) {
+      movementCourse=normalizeDegrees(candidate);
+      movementCourseRejected=0;
+    } else {
+      let delta=shortestSignedAngle(movementCourse,candidate);
+      const prevGps=Number.isFinite(Number(previousLoc.bearing)) && Number(previousLoc.bearing)>=0 ? normalizeDegrees(previousLoc.bearing) : null;
+      const gpsTurn=(reportedBearingGood && prevGps!=null) ? Math.abs(shortestSignedAngle(prevGps,reportedBearing)) : 999;
+
+      // A single fix cannot reverse the map while speed/GNSS still says we are traveling the same way.
+      if (effectiveSpeed>=2.5 && Math.abs(delta)>80 && reportedBearingGood && gpsTurn<35) {
+        movementCourseRejected=Math.min(8,movementCourseRejected+1);
+        return;
+      }
+      movementCourseRejected=0;
+
+      // Physically plausible turn-rate gate. It still permits real turns, but never a one-sample flip.
+      const maxRate=effectiveSpeed>=8 ? 14 : (effectiveSpeed>=3 ? 22 : 40); // deg/sec
+      const maxDelta=Math.max(5,maxRate*Math.max(.35,Math.min(2.5,dt)));
+      delta=Math.max(-maxDelta,Math.min(maxDelta,delta));
+      const alpha=effectiveSpeed>=8 ? .55 : (effectiveSpeed>=3 ? .48 : .38);
+      movementCourse=normalizeDegrees(movementCourse + delta*alpha);
+    }
+
     const sampleNow=Date.now();
     if (!movementCourseSampleAt || sampleNow-movementCourseSampleAt>4500) movementCourseSamples=0;
     movementCourseSamples=Math.min(8,movementCourseSamples+1);
     movementCourseSampleAt=sampleNow;
     movementCourseAt=sampleNow;
-    movementCourseConfidence=Math.max(.35,Math.min(1,(moved/minMove)*.32 + effectiveSpeed*.16));
-    if (orientationMode==='courseup' && navFollowMode && movementCourseSamples>=2) {
-      navCourseAcquired=true;
-    }
+    movementCourseConfidence=Math.max(.35,Math.min(1,(moved/minMove)*.24 + effectiveSpeed*.18 + (reportedBearingGood?.22:0)));
+    if (orientationMode==='courseup' && navFollowMode && movementCourseSamples>=2) navCourseAcquired=true;
   }
 
   function headingInputs() {
@@ -1797,39 +1835,34 @@
 
   function activeHeading() {
     const h = headingInputs();
-    if (headingMode === 'compass') {
-      return h.compass != null ? { degrees: h.compass, source: 'True compass' } : null;
+    if (headingMode === 'compass') return h.compass != null ? { degrees:h.compass, source:'True compass' } : null;
+
+    // At moderate/high speed, GNSS bearing becomes the primary course signal. This prevents one bad
+    // left/right lat/lon fix from steering or reversing the Course Up camera.
+    if (h.gpsTrusted && h.speed>=4) {
+      const deg=weightedHeading([{deg:h.gpsBearing,weight:.94},{deg:h.movement,weight:h.movement!=null?.06:0}]);
+      return {degrees:deg==null?h.gpsBearing:deg,source:'GPS course'};
     }
 
-    // Forced GPS still uses displacement-derived course first: it is the clearest expression
-    // of where the boat is actually traveling, then Android's GPS bearing is blended in lightly.
     if (headingMode === 'gps') {
-      if (h.movement != null) {
-        const deg=weightedHeading([{deg:h.movement,weight:.86},{deg:h.gpsBearing,weight:h.gpsUsable?.14:0}]);
-        return deg == null ? null : { degrees:deg, source:'GPS movement' };
+      if (h.gpsUsable && h.speed>=2) {
+        const deg=weightedHeading([{deg:h.gpsBearing,weight:.78},{deg:h.movement,weight:h.movement!=null?.22:0}]);
+        return {degrees:deg==null?h.gpsBearing:deg,source:'GPS course'};
       }
-      if (h.gpsUsable) return { degrees:h.gpsBearing, source:'GPS course' };
+      if (h.movement != null) return {degrees:h.movement,source:'GPS movement'};
+      if (h.gpsUsable) return {degrees:h.gpsBearing,source:'GPS course'};
       return null;
     }
 
-    // AUTO: once the device is actually moving, phone orientation should have almost no say
-    // in the navigation camera. Real displacement is ~85%, Android GPS bearing ~15%.
     if (h.movement != null && (h.speed >= .55 || h.movementAge < 6500)) {
-      const deg=weightedHeading([
-        {deg:h.movement,weight:.85},
-        {deg:h.gpsBearing,weight:h.gpsUsable?.15:0}
-      ]);
-      if (deg != null) return { degrees:deg, source:'GPS movement' };
-    }
-    if (h.gpsTrusted) {
-      const deg=weightedHeading([{deg:h.gpsBearing,weight:.92},{deg:h.compass,weight:h.speed<1.0?.08:0}]);
-      return { degrees:deg == null ? h.gpsBearing : deg, source:'GPS course' };
-    }
-    // When stopped, keep the last traveled course briefly rather than spinning the map with
-    // every phone movement. Compass becomes the fallback only after movement course is stale.
-    if (h.movement != null && h.movementAge < 15000) return { degrees:h.movement, source:'GPS movement' };
-    if (h.compass != null) return { degrees:h.compass, source:'True compass' };
-    if (h.gpsUsable) return { degrees:h.gpsBearing, source:'GPS course' };
+      const gpsWeight=h.gpsUsable ? (h.speed>=2 ? .55 : .25) : 0;
+      const deg=weightedHeading([{deg:h.movement,weight:1-gpsWeight},{deg:h.gpsBearing,weight:gpsWeight}]);
+      if (deg != null) return {degrees:deg,source:h.speed>=2&&h.gpsUsable?'GPS course':'GPS movement'};
+    }
+    if (h.gpsTrusted) return {degrees:h.gpsBearing,source:'GPS course'};
+    if (h.movement != null && h.movementAge < 15000) return {degrees:h.movement,source:'GPS movement'};
+    if (h.compass != null) return {degrees:h.compass,source:'True compass'};
+    if (h.gpsUsable) return {degrees:h.gpsBearing,source:'GPS course'};
     return null;
   }
 
@@ -2304,7 +2337,7 @@
     const visualHeading = freePanHeading != null ? freePanHeading : displayHeading;
     const target = courseUpVisual && visualHeading != null ? visualHeading : 0;
     const delta = shortestSignedAngle(mapRotationDeg, target);
-    mapRotationDeg = normalizeDegrees(mapRotationDeg + delta * 0.18) || 0;
+    mapRotationDeg = Number.isFinite(Number(mapRotationDeg)) ? (Number(mapRotationDeg) + delta * 0.18) : target;
     const visualAngle = courseUpVisual ? mapRotationDeg : 0;
     let scale = visualAngle ? 1.12 : 1;
     if (visualAngle && mapMode==='2d' && $('mapWrap')) {
@@ -2511,15 +2544,33 @@
   };
 
   function maybeAddTrackPoint(lat, lon, accuracy, timestamp) {
-    const last = trackPoints.length ? trackPoints[trackPoints.length - 1] : null;
+    const raw={lat:Number(lat),lon:Number(lon),accuracy:Number(accuracy),time:Number(timestamp)||Date.now()};
+    const anchored=(orientationMode==='courseup' && navCourseAcquired && navFilteredFix) ? navFilteredFix : null;
+    const candidate=anchored ? {lat:Number(anchored.lat),lon:Number(anchored.lon),accuracy:raw.accuracy,time:raw.time} : raw;
+    if (!Number.isFinite(candidate.lat) || !Number.isFinite(candidate.lon)) return;
+
+    const last=trackPoints.length ? trackPoints[trackPoints.length-1] : null;
     if (last) {
-      const moved = distanceMeters(last.lat, last.lon, lat, lon);
-      if (moved < 2 && timestamp - last.time < 5000) return;
+      const dt=Math.max(.25,Math.min(8,(candidate.time-Number(last.time||candidate.time))/1000 || 1));
+      const moved=distanceMeters(last.lat,last.lon,candidate.lat,candidate.lon);
+      if (moved<2 && candidate.time-Number(last.time||0)<5000) return;
+
+      // Final safety net for the saved track: reject a single physically impossible jump instead of
+      // drawing a diagonal across the lake/road. Real movement resumes on following valid samples.
+      const speed=Number.isFinite(Number(currentLoc&&currentLoc.speed)) ? Math.max(0,Number(currentLoc.speed)) : 0;
+      const plausible=Math.max(35,speed*dt*2.2 + Math.max(8,raw.accuracy||0)*1.4);
+      if (moved>plausible) return;
+      if (movementCourse!=null && moved>8) {
+        const b=bearingDegrees(last.lat,last.lon,candidate.lat,candidate.lon);
+        const rel=Math.abs(shortestSignedAngle(movementCourse,b));
+        if (rel>75 && moved>Math.max(18,(raw.accuracy||8)*1.8)) return;
+      }
     }
-    trackPoints.push({ lat, lon, accuracy, time: timestamp || Date.now() });
-    if (trackPoints.length > 12000) trackPoints.splice(0, trackPoints.length - 12000);
+    trackPoints.push(candidate);
+    if (trackPoints.length>12000) trackPoints.splice(0,trackPoints.length-12000);
     saveTrack();
-    if (trackLine) trackLine.setLatLngs(trackPoints.map(p => [p.lat, p.lon]));
+    if (trackLine) trackLine.setLatLngs(trackPoints.map(p=>[p.lat,p.lon]));
+    syncNavigationTrackEndpoint();
     updateTrackUi();
     renderOfflineFallbackOverlays();
     sync3dNavigationData();
PATCH
patch -p1 < /tmp/lakenav-v036.patch

# Replace generated vector launcher with the user-provided LakeNav Wisconsin/compass/boat artwork.
rm -f app/src/main/res/drawable/app_icon.xml app/src/main/res/drawable/app_icon_round.xml
base64 -d .bootstrap/app_icon_v036.png.b64 > app/src/main/res/drawable/app_icon.png
cp app/src/main/res/drawable/app_icon.png app/src/main/res/drawable/app_icon_round.png

python3 - <<'PY'
from pathlib import Path
rp=Path('README.md')
r=rp.read_text()
if '## Version 0.36 features' not in r:
    insert='''\n## Version 0.36 features\n\n### Navigation stability + launcher icon\n- Course Up now strongly favors the Android/GNSS course bearing at moderate and high speed, where one sideways GPS position error should not be allowed to steer the chart.\n- Adds a turn-rate gate and rejects single-sample near-reversals when GNSS bearing still indicates steady travel. Genuine turns remain allowed over consecutive fixes.\n- Fixes the 359-degree to 0-degree wrap issue by keeping the internal map rotation continuous instead of normalizing it every frame, preventing the chart from animating the long way around and appearing to flip.\n- Live Track recording now stores the same stabilized Course Up navigation coordinate used by the GPS marker/arrow instead of immediately writing each raw GPS fix. A final plausibility filter rejects isolated impossible track jumps.\n- Replaces the generated LakeNav launcher icon with the supplied Wisconsin, compass, water, and boat artwork.\n'''
    pos=r.find('\n## Version 0.35 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY

sed -i "s/versionCode [0-9][0-9]*/versionCode 36/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.36.0'/" app/build.gradle
grep -q 'v0.36' app/src/main/assets/index.html
grep -q 'movementCourseRejected' app/src/main/assets/index.html
grep -q 'const anchored=' app/src/main/assets/index.html
test -s app/src/main/res/drawable/app_icon.png
grep -q 'Version 0.36 features' README.md
printf 'LakeNav WI v0.36 navigation stability and launcher icon applied.\n'
