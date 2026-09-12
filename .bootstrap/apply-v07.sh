#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v07c00 .bootstrap/v07c01 .bootstrap/v07c02 .bootstrap/v07c03 .bootstrap/v07c04 .bootstrap/v07c05 .bootstrap/v07c06 .bootstrap/v07.patch.gz.b64.part01 | base64 -d | gzip -d > /tmp/lakenav-v07.patch
patch -p1 < /tmp/lakenav-v07.patch
printf 'LakeNav WI v0.7 wave, radar, and wind-visibility updates applied.\n'
