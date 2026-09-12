#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v09.patch.gz.b64 | gzip -d > /tmp/lakenav-v09.patch
patch -p1 < /tmp/lakenav-v09.patch
sed -i "s/versionCode 8/versionCode 9/; s/versionName '0.8.0'/versionName '0.9.0'/" app/build.gradle
printf 'LakeNav WI v0.9 MOB, zoom, and saved-route updates applied.\n'
