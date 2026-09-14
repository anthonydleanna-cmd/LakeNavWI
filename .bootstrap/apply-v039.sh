#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v039.patch.gz.b64 | base64 -d | gzip -d > /tmp/v039.patch
patch -p1 < /tmp/v039.patch
python3 - <<'PY'
from pathlib import Path
rp=Path('README.md')
r=rp.read_text()
if '## Version 0.39 features' not in r:
    insert='''\n## Version 0.39 features\n\n### Lake launch navigation reliability + auto-close\n- Open Lake now closes the lake-search sheet immediately after the lake is loaded so the map is visible.\n- Navigate to launch now uses the current Wisconsin DNR public boat-access service and hands a normal Google Maps directions URL to Android instead of relying on a geo: URI.\n- If a precise DNR launch lookup fails, LakeNav now opens a Google Maps search for a boat launch for that lake rather than silently leaving the user at the lake view.\n'''
    pos=r.find('\n## Version 0.38 features')
    if pos<0: pos=0
    r=r[:pos]+insert+r[pos:]
rp.write_text(r)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 39/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.39.0'/" app/build.gradle
grep -q 'v0.39' app/src/main/assets/index.html
grep -q 'openLakeLaunchSearchFallback' app/src/main/assets/index.html
grep -q 'Version 0.39 features' README.md
printf 'LakeNav WI v0.39 launch navigation reliability patch applied.\n'
