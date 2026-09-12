#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base64 -d .bootstrap/v011.patch.gz.b64 | gzip -d > /tmp/lakenav-v011.patch
patch -p1 < /tmp/lakenav-v011.patch
printf 'LakeNav WI v0.11 route-leg, settings, MOB SMS, storm, and lightning updates applied.\n'
