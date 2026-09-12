#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v07.patch.gz.b64.part00 .bootstrap/v07.patch.gz.b64.part01 | base64 -d | gzip -d > /tmp/lakenav-v07.patch
patch -p1 < /tmp/lakenav-v07.patch
printf 'LakeNav WI v0.7 wave, radar, and wind-visibility updates applied.\n'
