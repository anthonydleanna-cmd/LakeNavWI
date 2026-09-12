#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v09.patch.gz.b64 | gzip -d > /tmp/lakenav-v09.patch
patch -p1 < /tmp/lakenav-v09.patch
printf 'LakeNav WI v0.9 MOB, zoom, and saved-route updates applied.\n'
