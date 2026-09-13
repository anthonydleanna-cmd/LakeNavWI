#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v017.patch.gz.b64 | gzip -d > /tmp/lakenav-v017.patch
patch -p1 < /tmp/lakenav-v017.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 17/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.17.0'/" app/build.gradle
grep -q 'maplibre-gl.js' app/src/main/assets/index.html
grep -q 'Version 0.17 features' README.md
printf 'LakeNav WI v0.17 bundled 3D engine updates applied.\n'
