#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v016.patch.gz.b64 | gzip -d > /tmp/lakenav-v016.patch
set +e
patch -p1 < /tmp/lakenav-v016.patch
PATCH_RC=$?
set -e
sed -i "s/versionCode [0-9][0-9]*/versionCode 16/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.16.0'/" app/build.gradle
grep -q 'v0.16' app/src/main/assets/index.html
grep -q 'downloadOffline3dTerrain' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'ACCESS_NETWORK_STATE' app/src/main/AndroidManifest.xml
grep -q 'Version 0.16 features' README.md
printf 'LakeNav WI v0.16 Wi-Fi and offline 3D lake updates applied (patch rc=%s).\n' "$PATCH_RC"
