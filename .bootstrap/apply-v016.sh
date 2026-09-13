#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v016.patch.gz.b64 | gzip -d > /tmp/lakenav-v016.patch
set +e
patch -p1 < /tmp/lakenav-v016.patch
PATCH_RC=$?
set -e
python3 - <<'PY'
from pathlib import Path
p = Path("app/src/main/java/com/lakenav/wi/MainActivity.java")
s = p.read_text()
old = '        return (int) Math.floor((1.0 - Math.asinh(Math.tan(latRad)) / Math.PI) / 2.0 * n);'
new = '        double t = Math.tan(latRad);\n        double asinh = Math.log(t + Math.sqrt(t * t + 1.0));\n        return (int) Math.floor((1.0 - asinh / Math.PI) / 2.0 * n);'
if old not in s:
    raise SystemExit("Expected Math.asinh tile calculation not found")
p.write_text(s.replace(old, new))
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 16/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.16.0'/" app/build.gradle
grep -q 'v0.16' app/src/main/assets/index.html
grep -q 'downloadOffline3dTerrain' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'ACCESS_NETWORK_STATE' app/src/main/AndroidManifest.xml
grep -q 'Version 0.16 features' README.md
printf 'LakeNav WI v0.16 Wi-Fi and offline 3D lake updates applied (patch rc=%s).\n' "$PATCH_RC"
