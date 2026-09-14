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

state_anchor="  let navFilterHeading = null;"
if state_anchor not in s:
    raise SystemExit('navFilterHeading state anchor not found')
s=s.replace(state_anchor, state_anchor+"\n  let navArrowSyncRaf = 0;\n  let navArrowSyncUntil = 0;",1)

anchor="  function navigationAnchorLocation() {"
helpers=r'''  function syncNavigationArrowToGpsCircle() {
    const arrow=$('navGpsAnchor');
    const wrap=$('mapWrap');
    if (!arrow || !wrap || !wrap.classList.contains('navGpsPinned')) return false;
    let rect=null;
    try {
      if (accuracyCircle && accuracyCircle._path) {
        const r=accuracyCircle._path.getBoundingClientRect();
        if (r) rect=r;
      }
      if (!rect && positionMarker && positionMarker._icon) {
        const r=positionMarker._icon.getBoundingClientRect();
        if (r) rect=r;
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

map_event_anchor="""    map.on('dragstart', () => { navFollowMode=false; updateNavigationPerspectiveUi(); applyMapOrientationWithHeading(null); if($('chartChip')) $('chartChip').textContent='Free pan • tap GPS to resume'; });
"""
if map_event_anchor not in s:
    raise SystemExit('map dragstart anchor not found')
s=s.replace(map_event_anchor,map_event_anchor+"    map.on('move zoom moveend zoomend', () => { if($('mapWrap') && $('mapWrap').classList.contains('navGpsPinned')) runNavigationArrowSyncBurst(220); });\n",1)

# Heading changes can occur without Leaflet move events, so extend the sync burst whenever the
# heading visuals are refreshed while Course Up is pinned.
heading_anchor="""    const h = activeHeading();
"""
first=s.find(heading_anchor)
if first<0:
    raise SystemExit('heading refresh anchor not found')
s=s[:first]+heading_anchor+"    if ($('mapWrap') && $('mapWrap').classList.contains('navGpsPinned')) runNavigationArrowSyncBurst(520);\n"+s[first+len(heading_anchor):]

css='''
/* v0.33 arrow-to-GPS-circle visual lock */
#mapWrap.navGpsPinned #navGpsAnchor { transition:none !important; }
#mapWrap.navGpsPinned #navGpsAnchor .navGpsHalo { opacity:.28; width:34px; height:34px; }
'''
s=s.replace('\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"', css+'\n</style>\n<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"',1)

rp=Path('README.md')
r=rp.read_text()
if '## Version 0.33 features' not in r:
    insert='''\n## Version 0.33 features\n\n### Navigation arrow locked to the rendered GPS circle\n- The Course Up navigation arrow reads the exact rendered center of the Leaflet GPS accuracy circle and places itself directly on that pixel.\n- Pan, zoom and heading refreshes trigger short animation-frame sync bursts so the arrow stays attached to the circle throughout movement.\n- Keeps v0.32 direction-aware GPS filtering unchanged; this version only fixes the remaining visual separation between the stabilized GPS point and the navigation arrow.\n'''
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
