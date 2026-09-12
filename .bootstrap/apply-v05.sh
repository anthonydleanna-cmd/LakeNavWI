#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v05.patch.part00 .bootstrap/v05.patch.part01 .bootstrap/v05.patch.part02 .bootstrap/v05.patch.part03 > /tmp/lakenav-v05.patch
set +e
patch -p1 < /tmp/lakenav-v05.patch
PATCH_RC=$?
set -e
# The v0.4 materializer can leave app/build.gradle at the repository baseline version,
# so normalize version metadata here even if that one patch hunk rejects.
sed -i "s/versionCode [0-9][0-9]*/versionCode 5/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.5.0'/" app/build.gradle
# Verify the functional v0.5 changes actually landed before allowing the build to continue.
grep -q 'LakeNav WI v0.5 visual refresh' app/src/main/assets/index.html
grep -q 'gpsCourseTrusted' app/src/main/assets/index.html
grep -q 'LakeNavWI/0.5' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'Version 0.5 features' README.md
printf 'LakeNav WI v0.5 UI and heading updates applied (patch rc=%s).\n' "$PATCH_RC"
