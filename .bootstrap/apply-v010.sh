#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v010.patch.gz.b64 | gzip -d > /tmp/lakenav-v010.patch
patch -p1 < /tmp/lakenav-v010.patch
printf 'LakeNav WI v0.10 chartplotter route drawing updates applied.\n'
