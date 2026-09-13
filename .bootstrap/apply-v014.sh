#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v014.patch.gz.b64 | gzip -d > /tmp/lakenav-v014.patch
set +e
patch -p1 < /tmp/lakenav-v014.patch
PATCH_RC=$?
set -e
sed -i "s/versionCode [0-9][0-9]*/versionCode 14/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.14.0'/" app/build.gradle
grep -q 'v0.14' app/src/main/assets/index.html
grep -q 'weatherQuickPanel' app/src/main/assets/index.html
grep -q 'drawWindSpeedLabels' app/src/main/assets/index.html
grep -q 'navCruiseHud' app/src/main/assets/index.html
printf 'LakeNav WI v0.14 chartplotter weather and marine display updates applied (patch rc=%s).\n' "$PATCH_RC"
