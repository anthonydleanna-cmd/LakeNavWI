#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import re

p=Path('app/src/main/assets/index.html')
s=p.read_text()

s=re.sub(r'<div id="brand">LakeNav WI <span class="versionPill">v0\.\d+</span></div>', '<div id="brand">LakeNav WI <span class="versionPill">v0.33</span></div>', s, count=1)

# Track a short render-sync burst so the screen-fixed navigation arrow can follow the EXACT
# rendered center of the Leaflet GPS accuracy circle while the map pans/rotates underneath it.
state_anchor="  let navFilterHeading = null;"
if state_anchor not in s:
    raise SystemExit('navFilterHeading state anchor not found')
s=s.replace(state_anchor, state_anchor+"\n  let navArrowSyncRaf = 0;\n  let navArrowSyncUntil = 0;",1)

# Insert visual-lock helpers immediately before navigationAnchorLocation. Using getBoundingClientRect
# on the rendered Leaflet accuracy circle automatically includes every CSS map rotation, pan and
# overscan transform, which is more reliable than calculating a second independent screen point.
anchor="  function navigationAnchorLocation() {"
helpers=r'''  function syncNavigationArrowToGpsCircle() {
    const arrow=$('navGpsAnchor');
    const wrap=$('mapWrap');
    if (!arrow || !wrap || !wrap.classList.contains('navGpsPinned')) return false;

    let rect=null;
    try {
      // Preferred source: the rendered accuracy circle. Its bounding-box center is the exact
      // geographic GPS point after Leaflet positioning AND the outer Course Up CSS transform.
      if (accuracyCircle && accuracyCircle._path) {
        const r=accuracyCircle._path.getBoundingClientRect();
        if (r && r.width>=0 && r.height>=0) rect=r;
      }
      // Fallback to the Leaflet position marker DOM if the SVG circle is not available yet.
      if (!rect && positionMarker && positionMarker._icon) {
        const r=positionMarker._icon.getBoundingClientRect();
        if (r && r.width>=0 && r.height>=0) rect=r;
      }
    } catch(e) {}
    if (!rect) return false;

    const wr=wrap.getBoundingClientRect();
    const x=(rect.left + rect.width/2) - wr.left;
    const y=(rect.top + rect.height/2) - wr.top;
    if (!Number.isFinite(x) || !Number.isFinite(y)) return false;
    arrow.style.left=x.toFixed(2)+'px';
    arrow.style.top=y.toFixed(2)+'px';
    return true;
  }

  function runNavigationArrowSyncBurst(ms=760) {
    navArrowSyncUntil=Math.max(navArrowSyncUntil,Date.now()+Math.max(120,Number(ms)||760));
    if (navArrowSyncRaf) return;
    const tick=()=>{
      navArrowSyncRaf=0;
      syncNavigationArrowToGpsCircle();
      if (Date.now()<navArrowSyncUntil && $('mapWrap') && $('mapWrap').classList.contains('navGpsPinned')) {
        navArrowSyncRaf=requestAnimationFrame(tick);
      }
    };
    navArrowSyncRaf=requestAnimationFrame(tick);
  }

'''
if anchor not in s:
    raise SystemExit('navigationAnchorLocation anchor not found')
s=s.replace(anchor,helpers+anchor,1)

# Every time the filtered geographic point moves, immediately keep the visual arrow with it.
old_tail="""    if (navCourseAcquired) {
      const filtered=navigationAnchorLocation() || currentLoc;
      if (filtered) {
        if (positionMarker) positionMarker.setLatLng([filtered.lat,filtered.lon]);
        if (accuracyCircle) accuracyCircle.setLatLng([filtered.lat,filtered.lon]);
      }
    }
    updateNavigationPerspectiveUi();
"""
new_tail="""    if (navCourseAcquired) {
      const filtered=navigationAnchorLocation() || currentLoc;
      if (filtered) {
        if (positionMarker) positionMarker.setLatLng([filtered.lat,filtered.lon]);
        if (accuracyCircle) accuracyCircle.setLatLng([filtered.lat,filtered.lon]);
        runNavigationArrowSyncBurst(820);
      }
    } else {
      runNavigationArrowSyncBurst(420);
    }
    updateNavigationPerspectiveUi();
"""
if old_tail not in s:
    raise SystemExit('v0.32 filtered marker tail not found')
s=s.replace(old_tail,new_tail,1)

# Whenever Course Up UI state changes, reset the arrow's CSS fallback first and then lock it to
# the real rendered GPS circle as soon as Leaflet has painted the new frame.
old_ui="""      $('mapWrap').classList.toggle('navGpsPinned', pinned);
    }
"""
new_ui="""      $('mapWrap').classList.toggle('navGpsPinned', pinned);
      if (!pinned && $('navGpsAnchor')) {
        $('navGpsAnchor').style.left='50%';
        $('navGpsAnchor').style.top='76%';
      }
      if (pinned) runNavigationArrowSyncBurst(900);
    }
"""
if old_ui not in s:
    raise SystemExit('updateNavigationPerspectiveUi pinned class anchor not found')
s=s.replace(old_ui,new_ui,1)

# Keep arrow locked through Leaflet's animated pan. move fires throughout panTo; zoom/moveend cover
# user zoom and final tile re-layout. These listeners do not change follow behavior.
map_event_anchor="""    map.on('dragstart', () => { navFollowMode=false; updateNavigationPerspectiveUi(); applyMapOrientationWithHeading(null); if($('chartChip')) $('chartChip').textContent='Free pan • tap GPS to resume'; });
"""
if map_event_anchor not in s:
    raise SystemExit('map dragstart anchor not found')
s=s.replace(map_event_anchor,map_event_anchor+"    map.on('move zoom moveend zoomend', () => { if($('mapWrap') && $('mapWrap').classList.contains('navGpsPinned')) runNavigationArrowSyncBurst(180); });\n",1)

# Map heading changes are CSS transforms outside Leaflet's own move events. Start a sync burst after
# every orientation render so the arrow follows the GPS circle during the transform animation too.
orient_anchor="""    updateCourseUpPerspectiveScale();
  }
"""
# Use the first occurrence after applyMapOrientationWithHeading by locating function range.
pos=s.find("  function applyMapOrientationWithHeading")
if pos<0:
    raise SystemExit('applyMapOrientationWithHeading not found')
end=s.find("\n  }",pos)
# safer targeted replacement after pos
idx=s.find(orient_anchor,pos)
if idx<0:
    raise SystemExit('orientation scale tail not found')
s=s[:idx]+"    updateCourseUpPerspectiveScale();\n    if ($('mapWrap') && $('mapWrap').classList.contains('navGpsPinned')) runNavigationArrowSyncBurst(720);\n  }\n"+s[idx+len(orient_anchor):]

# The overlay halo should not visually compete with the real Leaflet GPS accuracy circle. The arrow
# itself remains crisp while its center is physically locked to the circle beneath it.
css='''
/* v0.33 arrow-to-GPS-circle visual lock */
#mapWrap.navGpsPinned #navGpsAnchor { transition:none !important; }
#mapWrap.navGpsPinned #navGpsAnchor .navGpsHalo {
  opacity:.28;
  width:34px;
  height:34px;
}
'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.33 features' not in r:
    insert='''\n## Version 0.33 features\n\n### Navigation arrow locked to the rendered GPS circle\n- The Course Up navigation arrow no longer uses an independently calculated bottom-center screen position once GPS is available. It reads the exact rendered center of the Leaflet GPS accuracy circle and places the arrow directly on that pixel.\n- The visual lock uses the rendered SVG circle after Leaflet positioning and Course Up CSS rotation, so pan, rotation, overscan and map transforms cannot create a gap between the arrow and the GPS circle.\n- Adds short requestAnimationFrame sync bursts during GPS updates, map pans, zooms and Course Up rotation animations so the arrow remains attached to the circle throughout motion, not only after the map settles.\n- Keeps v0.32's direction-aware GPS filtering unchanged. The geographic GPS point remains stabilized; v0.33 only removes the remaining visual separation/jump between that point and the navigation arrow.\n'''
    pos=r.find('\n## Version 0.32 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)

p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 33/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.33.0'/" app/build.gradle
grep -q 'v0.33' app/src/main/assets/index.html
grep -q 'syncNavigationArrowToGpsCircle' app/src/main/assets/index.html
grep -q 'runNavigationArrowSyncBurst' app/src/main/assets/index.html
grep -q 'Version 0.33 features' README.md
printf 'LakeNav WI v0.33 arrow-to-GPS-circle lock applied.\n'
