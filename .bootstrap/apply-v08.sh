#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v08.patch.gz.b64.part00 .bootstrap/v08.patch.gz.b64.part01 | base64 -d | gzip -d > /tmp/lakenav-v08.patch
patch -p1 < /tmp/lakenav-v08.patch
printf 'LakeNav WI v0.8 animated marine arrows and waypoint journal applied.\n'
