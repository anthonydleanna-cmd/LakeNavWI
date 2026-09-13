#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v018.patch.gz.b64 | gzip -d > /tmp/lakenav-v018.patch
patch -p1 < /tmp/lakenav-v018.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 18/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.18.0'/" app/build.gradle
grep -q 'buildOnline3dStyle' app/src/main/assets/index.html
grep -q 'USGSImageryOnly' app/src/main/assets/index.html
grep -q 'Version 0.18 features' README.md
printf 'LakeNav WI v0.18 terrain-first 3D updates applied.\n'
