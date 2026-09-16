#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
base64 -d .bootstrap/v065.patch.gz.b64 | gzip -d > /tmp/v065.patch
patch -p1 < /tmp/v065.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 65/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.65.0'/" app/build.gradle
grep -q 'v0.65' app/src/main/assets/index.html
printf 'LakeNav WI v0.65 sequential route-point workflow applied.\n'
