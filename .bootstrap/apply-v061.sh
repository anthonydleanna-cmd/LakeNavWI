#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
python3 .bootstrap/v061_stage1.py
python3 .bootstrap/v061_stage_course.py
python3 .bootstrap/v061_stage_math2.py
python3 .bootstrap/v061_stage_follow.py
python3 .bootstrap/v061_stage_center.py
sed -i "s/versionCode 60/versionCode 61/" app/build.gradle
sed -i "s/versionName '0.60.0'/versionName '0.61.0'/" app/build.gradle
grep -q 'v0.61' app/src/main/assets/index.html
