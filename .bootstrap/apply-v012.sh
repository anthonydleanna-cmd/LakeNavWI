#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v012.patch.gz.b64 | gzip -d > /tmp/lakenav-v012.patch
patch -p1 < /tmp/lakenav-v012.patch
printf 'LakeNav WI v0.12 optional silent MOB SMS updates applied.\n'
