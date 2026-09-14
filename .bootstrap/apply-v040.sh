#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v040.patch.gz.b64 | base64 -d | gzip -d > /tmp/lakenav-v040.patch
patch -p1 < /tmp/lakenav-v040.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 40/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.40.0'/" app/build.gradle
python3 .bootstrap/diagnostics-v040.py
node --check /tmp/lakenav-inline.js
python3 - <<'PY'
from pathlib import Path
p=Path('README.md')
s=p.read_text()
if '## Version 0.40 features' not in s:
    block='''\n## Version 0.40 features\n\n### Performance and diagnostics maintenance\n- Throttles heading/compass visual work so rapid sensor callbacks do not repeatedly redraw the map when the effective heading has barely changed.\n- Cuts the GPS-arrow synchronization loop down to short 30 FPS bursts only when position/rotation actually changes instead of repeatedly running long full-frame bursts.\n- Reworks live track rendering so accepted GPS points append incrementally and only the short live tail moves with the stabilized navigation anchor; the full historical polyline is no longer rebuilt on every GPS fix.\n- Caches current track distance instead of recalculating the full track for each UI refresh.\n- Debounces current-track localStorage writes while recording, then flushes immediately on stop/background/clear/import so trip data stays durable without serializing thousands of points every few seconds.\n- Reduces redundant high-frequency DOM text writes, heading-line redraws, navigation perspective refreshes, offline fallback work, and storm/lightning range-ring updates.\n- Adds a build-time diagnostic pass checking duplicate HTML IDs, missing direct DOM references, required v0.40 performance hooks, legacy hot-path patterns, and JavaScript syntax before Gradle builds the APK.\n'''
    pos=s.find('\n## Version 0.39 features')
    if pos < 0: pos=0
    s=s[:pos]+block+s[pos:]
p.write_text(s)
PY
grep -q 'v0.40' app/src/main/assets/index.html
grep -q 'versionCode 40' app/build.gradle
grep -q 'Version 0.40 features' README.md
printf 'LakeNav WI v0.40 performance maintenance and diagnostics applied.\n'
