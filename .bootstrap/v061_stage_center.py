from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
a="if ($('mapWrap') && $('mapWrap').classList.contains('navGpsPinned') && Math.abs(shortestSignedAngle(previousRotation,mapRotationDeg))>.03) runNavigationArrowSyncBurst(390);"
b="if ($('mapWrap') && $('mapWrap').classList.contains('navGpsPinned') && Math.abs(shortestSignedAngle(previousRotation,mapRotationDeg))>.03) { runNavigationArrowSyncBurst(390); const gpsTarget=perspectiveCenterLatLng(); if (gpsTarget) try { map.panTo(gpsTarget,{animate:false,noMoveStart:true}); } catch(e) {} }"
if a not in s: raise SystemExit('rotation recenter anchor missing')
p.write_text(s.replace(a,b,1))
