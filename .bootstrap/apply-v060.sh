#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
cat .bootstrap/v060.patch.gz.b64.part00 .bootstrap/v060.patch.gz.b64.part01 .bootstrap/v060.patch.gz.b64.part02 .bootstrap/v060.patch.gz.b64.part03 .bootstrap/v060.patch.gz.b64.part04 > /tmp/v060.b64
base64 -d /tmp/v060.b64 | gzip -d > /tmp/v060.patch
patch -p1 < /tmp/v060.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 60/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.60.0'/" app/build.gradle
grep -q 'v0.60' app/src/main/assets/index.html
printf 'LakeNav WI v0.60 GPS anchor fix applied.\n'
