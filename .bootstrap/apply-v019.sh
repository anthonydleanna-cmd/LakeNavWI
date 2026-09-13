#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v019.patch.gz.b64.part00 .bootstrap/v019.patch.gz.b64.part01 .bootstrap/v019.patch.gz.b64.part02 | base64 -d | gzip -d > /tmp/lakenav-v019.patch
patch -p1 < /tmp/lakenav-v019.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 19/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.19.0'/" app/build.gradle
grep -q 'v0.19' app/src/main/assets/index.html
grep -q 'Automatic 3D water-depth coloring' README.md
printf 'LakeNav WI v0.19 automatic stable 3D depth coloring applied.\n'
