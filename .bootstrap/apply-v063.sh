#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
base64 -d .bootstrap/v063.patch.gz.b64 | gzip -d > /tmp/v063.patch
patch -p1 < /tmp/v063.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 63/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.63.0'/" app/build.gradle
grep -q 'v0.63' app/src/main/assets/index.html
printf 'LakeNav WI v0.63 navigation camera smoothing applied.\n'
