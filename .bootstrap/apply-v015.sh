#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v015.patch.gz.b64.part00 .bootstrap/v015.patch.gz.b64.part01 .bootstrap/v015.patch.gz.b64.part02 | base64 -d | gzip -d > /tmp/lakenav-v015.patch
set +e
patch -p1 < /tmp/lakenav-v015.patch
PATCH_RC=$?
set -e
sed -i "s/versionCode [0-9][0-9]*/versionCode 15/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.15.0'/" app/build.gradle
grep -q 'v0.15' app/src/main/assets/index.html
grep -q 'function init3dMap' app/src/main/assets/index.html
grep -q 'quick3dToggle' app/src/main/assets/index.html
grep -q 'Version 0.15 features' README.md
printf 'LakeNav WI v0.15 3D chart preview applied (patch rc=%s).\n' "$PATCH_RC"
