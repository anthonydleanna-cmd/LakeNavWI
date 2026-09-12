#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v05.patch.part00 .bootstrap/v05.patch.part01 .bootstrap/v05.patch.part02 .bootstrap/v05.patch.part03 > /tmp/lakenav-v05.patch
patch -p1 < /tmp/lakenav-v05.patch
printf 'LakeNav WI v0.5 UI and heading updates applied.\n'
