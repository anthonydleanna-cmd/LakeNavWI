#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.32</span></div>', s, count=1)

# Direction-aware navigation-position filter. The fixed vessel graphic stays on screen while this
# filtered geographic coordinate controls how the chart moves beneath it.
state_anchor="  let navStableFix = null;"
if state_anchor not in s:
    raise SystemExit('navStableFix state anchor not found')
s=s.replace(state_anchor, state_anchor+"\n  let navFilteredFix = null;\n  let navFilterHeading = null;",1)

# Preserve the acquisition fix long enough for the filter to use it as its starting point.
s=s.replace("      navCourseAcquired=true;\n      navStableFix=null;", "      navCourseAcquired=true;",1)

# Reset all navigation-position filtering whenever Course Up is freshly acquired/recentered.
old_reset="""  function resetCourseUpAcquisition() {
    navCourseAcquired=false;
    movementCourseSamples=0;
    movementCourseSampleAt=0;
    navStableFix=currentLoc ? {lat:currentLoc.lat,lon:currentLoc.lon,accuracy:currentLoc.accuracy} : null;
  }
"""
new_reset="""  function resetCourseUpAcquisition() {
    navCourseAcquired=false;
    movementCourseSamples=0;
    movementCourseSampleAt=0;
    navStableFix=currentLoc ? {lat:currentLoc.lat,lon:currentLoc.lon,accuracy:currentLoc.accuracy} : null;
    navFilteredFix=null;
    navFilterHeading=null;
  }
"""
if old_reset not in s:
    raise SystemExit('resetCourseUpAcquisition block not found')
s=s.replace(old_reset,new_reset,1)

# Replace the Course Up anchor selector and add the directional GPS filter.
old_anchor="""  function navigationAnchorLocation() {
    if (orientationMode==='courseup' && navFollowMode && !navCourseAcquired) {
      if (!navStableFix && currentLoc) navStableFix={lat:currentLoc.lat,lon:currentLoc.lon,accuracy:currentLoc.accuracy};
      return navStableFix || currentLoc;
    }
    return currentLoc;
  }

"""
new_anchor=r'''  function signedDestinationPoint(lat,lon,bearingDeg,meters) {
    const d=Number(meters)||0;
    if (Math.abs(d)<0.01) return [lat,lon];
    const b=d>=0 ? normalizeDegrees(bearingDeg) : normalizeDegrees(bearingDeg+180);
    return destinationPoint(lat,lon,b,Math.abs(d));
  }

  function updateNavigationFilteredFix(rawLoc) {
    if (!rawLoc || orientationMode!=='courseup' || !navFollowMode || !navCourseAcquired) return;
    const course=movementCourse != null && Number.isFinite(Number(movementCourse)) ? normalizeDegrees(movementCourse) : null;
    if (course == null) return;

    if (!navFilteredFix) {
      const seed=navStableFix || rawLoc;
      navFilteredFix={
        lat:Number(seed.lat), lon:Number(seed.lon),
        accuracy:Number.isFinite(Number(rawLoc.accuracy)) ? Number(rawLoc.accuracy) : null,
        timestamp:Number(rawLoc.timestamp)||Date.now()
      };
      navFilterHeading=course;
    }

    const gap=distanceMeters(navFilteredFix.lat,navFilteredFix.lon,rawLoc.lat,rawLoc.lon);
    if (!Number.isFinite(gap) || gap<0.05) {
      navFilteredFix.accuracy=rawLoc.accuracy;
      navFilteredFix.timestamp=rawLoc.timestamp;
      navStableFix=null;
      return;
    }

    const rawBearing=bearingDegrees(navFilteredFix.lat,navFilteredFix.lon,rawLoc.lat,rawLoc.lon);
    if (!Number.isFinite(rawBearing)) return;
    const relative=shortestSignedAngle(course,rawBearing);
    const rr=relative*Math.PI/180;
    const along=gap*Math.cos(rr);
    const cross=gap*Math.sin(rr);
    const accuracy=Number.isFinite(Number(rawLoc.accuracy)) && Number(rawLoc.accuracy)>0 ? Number(rawLoc.accuracy) : 8;
    const speed=Number.isFinite(Number(rawLoc.speed)) && Number(rawLoc.speed)>0 ? Number(rawLoc.speed) : 0;
    const prevTime=Number(navFilteredFix.timestamp)||Number(rawLoc.timestamp)||Date.now();
    const nowTime=Number(rawLoc.timestamp)||Date.now();
    const dt=Math.max(.25,Math.min(3.0,Math.abs(nowTime-prevTime)/1000 || 1));

    // Side-to-side GPS movement inside this corridor is ignored completely. The corridor grows
    // modestly when reported GPS accuracy is poor, so a 20 ft accuracy fix cannot shove the vessel
    // 15 ft sideways even though the boat is actually traveling straight.
    const lateralDeadband=Math.max(2.4,Math.min(7.5,accuracy*.28));
    const headingChange=navFilterHeading == null ? 0 : Math.abs(shortestSignedAngle(navFilterHeading,course));
    const deliberateTurn=headingChange>=6;
    const crossExcess=Math.max(0,Math.abs(cross)-lateralDeadband);
    const crossGain=deliberateTurn ? .42 : .16;
    const crossCap=deliberateTurn ? Math.max(2.5,speed*dt*.55) : Math.max(1.2,speed*dt*.20);
    const crossAdjust=Math.sign(cross)*Math.min(crossCap,crossExcess*crossGain);

    // Forward progress is trusted much more strongly than lateral movement. Backward GPS jumps are
    // heavily damped, and a single fix cannot pull the navigation position an unrealistic distance.
    let alongAdjust=along>=0 ? along*(speed>=3 ? .82 : .72) : along*.18;
    const forwardCap=Math.max(4.0,speed*dt*1.65 + accuracy*.15);
    alongAdjust=Math.max(-1.5,Math.min(forwardCap,alongAdjust));

    let pt=signedDestinationPoint(navFilteredFix.lat,navFilteredFix.lon,course,alongAdjust);
    pt=signedDestinationPoint(pt[0],pt[1],normalizeDegrees(course+90),crossAdjust);
    navFilteredFix={lat:pt[0],lon:pt[1],accuracy:rawLoc.accuracy,timestamp:rawLoc.timestamp};
    navFilterHeading=course;
    navStableFix=null;
  }

  function navigationAnchorLocation() {
    if (orientationMode==='courseup' && navFollowMode) {
      if (!navCourseAcquired) {
        if (!navStableFix && currentLoc) navStableFix={lat:currentLoc.lat,lon:currentLoc.lon,accuracy:currentLoc.accuracy};
        return navStableFix || currentLoc;
      }
      return navFilteredFix || currentLoc;
    }
    return currentLoc;
  }

'''
if old_anchor not in s:
    raise SystemExit('navigationAnchorLocation block not found')
s=s.replace(old_anchor,new_anchor,1)

# Run the filter immediately after the new raw GPS fix becomes current. updateMovementCourse has
# already run at this point, so a newly acquired course can begin filtering on the same location fix.
old_current="""    updateMovementCourse(previousLoc,nextLoc);
    currentLoc = nextLoc;
"""
new_current="""    updateMovementCourse(previousLoc,nextLoc);
    currentLoc = nextLoc;
    updateNavigationFilteredFix(nextLoc);
"""
if old_current not in s:
    raise SystemExit('onNativeLocation currentLoc anchor not found')
s=s.replace(old_current,new_current,1)

# v0.31 intentionally snapped the geographic marker to every raw fix after acquisition. Replace
# that with the filtered coordinate so the real GPS circle and pinned vessel remain one object.
old_tail="""    if (navCourseAcquired) {
      navStableFix=null;
      if (positionMarker) positionMarker.setLatLng([lat,lon]);
      if (accuracyCircle) accuracyCircle.setLatLng([lat,lon]);
    }
    updateNavigationPerspectiveUi();
"""
new_tail="""    if (navCourseAcquired) {
      const filtered=navigationAnchorLocation() || currentLoc;
      if (filtered) {
        if (positionMarker) positionMarker.setLatLng([filtered.lat,filtered.lon]);
        if (accuracyCircle) accuracyCircle.setLatLng([filtered.lat,filtered.lon]);
      }
    }
    updateNavigationPerspectiveUi();
"""
if old_tail not in s:
    raise SystemExit('v0.31 raw marker tail not found')
s=s.replace(old_tail,new_tail,1)

# When manually leaving Course Up, discard the old filter so a later navigation session cannot
# inherit a stale smoothed coordinate.
s=s.replace("    else { navCourseAcquired=false; navStableFix=null; }",
            "    else { navCourseAcquired=false; navStableFix=null; navFilteredFix=null; navFilterHeading=null; }",1)

# Slightly lengthen camera interpolation; position filtering handles accuracy while this only makes
# the remaining chart translation visually continuous between GPS fixes.
s=s.replace("map.panTo(target,{animate:true,duration:.48,easeLinearity:.20,noMoveStart:true})",
            "map.panTo(target,{animate:true,duration:.58,easeLinearity:.18,noMoveStart:true})",1)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.32 features' not in r:
    insert='''\n## Version 0.32 features\n\n### Direction-aware GPS stabilization\n- Adds a navigation-only filtered GPS coordinate for Course Up. The pinned vessel and geographic GPS circle both use this same filtered point, so small raw GPS corrections no longer jerk the chart sideways underneath the arrow.\n- Forward travel is trusted much more strongly than sideways movement. Normal forward progress is accepted quickly, while backward GPS jumps are heavily damped.\n- Adds an adaptive lateral deadband of roughly 2.4–7.5 meters depending on reported GPS accuracy. Side-to-side movement inside that corridor is ignored as positioning noise.\n- Lateral corrections outside the deadband are eased in slowly and capped per GPS update. When the measured movement heading is genuinely turning, the lateral filter automatically relaxes so LakeNav can follow a real course change instead of forcing the boat straight.\n- The v0.31 movement-acquisition gate remains intact: stationary compass changes still cannot start rotating the chart.\n- Follow-camera interpolation is slightly longer so the remaining accepted position changes flow continuously rather than stepping between GPS fixes.\n'''
    pos=r.find('\n## Version 0.31 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)

p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 32/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.32.0'/" app/build.gradle
grep -q 'v0.32' app/src/main/assets/index.html
grep -q 'updateNavigationFilteredFix' app/src/main/assets/index.html
grep -q 'lateralDeadband' app/src/main/assets/index.html
grep -q 'Version 0.32 features' README.md
printf 'LakeNav WI v0.32 directional GPS stabilization applied.\n'
