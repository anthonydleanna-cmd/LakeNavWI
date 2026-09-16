#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
base64 -d .bootstrap/v064.patch.gz.b64 | gzip -d > /tmp/v064.patch
patch -p1 < /tmp/v064.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 64/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.64.0'/" app/build.gradle
grep -q 'v0.64' app/src/main/assets/index.html
printf 'LakeNav WI v0.64 dark popup and completed-track interaction fixes applied.\n'
