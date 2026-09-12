#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v013.patch.gz.b64 | gzip -d > /tmp/lakenav-v013.patch
set +e
patch -p1 < /tmp/lakenav-v013.patch
PATCH_RC=$?
set -e
sed -i "s/versionCode [0-9][0-9]*/versionCode 13/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.13.0'/" app/build.gradle
grep -q 'v0.13' app/src/main/assets/index.html
grep -q 'fetchLightningStrikes' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'POST_NOTIFICATIONS' app/src/main/AndroidManifest.xml
grep -q 'Version 0.13 features' README.md
printf 'LakeNav WI v0.13 contact-picker and live-lightning updates applied (patch rc=%s).\n' "$PATCH_RC"
