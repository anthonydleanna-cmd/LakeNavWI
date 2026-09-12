#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v06.patch.part00 .bootstrap/v06.patch.part01 .bootstrap/v06.patch.part02 .bootstrap/v06.patch.part03 > /tmp/lakenav-v06.patch
patch -p1 < /tmp/lakenav-v06.patch
printf 'LakeNav WI v0.6 quick layers, heading modes, and animated wind applied.\n'
