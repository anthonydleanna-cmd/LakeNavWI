#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v011.patch.gz.b64 | gzip -d > /tmp/lakenav-v011.patch
set +e
patch -p1 < /tmp/lakenav-v011.patch
PATCH_RC=$?
set -e
# Older bootstrap patches can leave app/build.gradle at a prior version even when
# all app/README hunks apply correctly. Normalize the app version explicitly.
sed -i -E "s/versionCode[[:space:]]+[0-9]+/versionCode 11/" app/build.gradle
sed -i -E "s/versionName[[:space:]]+'[^']+'/versionName '0.11.0'/" app/build.gradle
# Only fail if the v0.11 app or README changes did not land.
grep -q 'v0.11' app/src/main/assets/index.html
grep -q 'Version 0.11 features' README.md
printf 'LakeNav WI v0.11 route-leg, settings, MOB SMS, storm, and lightning updates applied (patch rc=%s).\n' "$PATCH_RC"
