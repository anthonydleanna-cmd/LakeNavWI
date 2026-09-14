#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v038.patch.gz.b64 | gzip -d > /tmp/lakenav-v038.patch
patch -p1 < /tmp/lakenav-v038.patch
python3 - <<'PY'
from pathlib import Path
rp=Path('README.md')
r=rp.read_text()
if '## Version 0.38 features' not in r:
    insert="""
## Version 0.38 features

### Navigate to the closest public boat launch
- Lake Search now includes a **Navigate to launch** action both on each search result and on the selected-lake card.
- LakeNav queries the Wisconsin DNR public boat-access layer around the selected lake shoreline, matches the access site to the selected waterbody, prefers a true ramp when one is available, and chooses the closest qualifying launch to the phone's current GPS position.
- The selected launch is handed off to the Android phone's external/default maps navigation through a geo destination intent, with a Google Maps web fallback outside Android.
- The lake search screen reports which launch was selected, its access type, and approximate straight-line distance from the current GPS position before opening navigation.
"""
    pos=r.find('\n## Version 0.37 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 38/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.38.0'/" app/build.gradle
grep -q 'v0.38' app/src/main/assets/index.html
grep -q 'navigateToClosestBoatLaunch' app/src/main/assets/index.html
grep -q 'LF_DNR_BOAT_BoatAccess_WTM_Ext' app/src/main/assets/index.html
grep -q 'Version 0.38 features' README.md
printf 'LakeNav WI v0.38 closest boat launch navigation applied.\n'
