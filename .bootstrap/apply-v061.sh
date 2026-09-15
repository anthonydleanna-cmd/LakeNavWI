#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
python3 .bootstrap/v061_stage1.py
python3 .bootstrap/v061_stage_course.py
python3 .bootstrap/v061_stage_math2.py
python3 .bootstrap/v061_stage_follow.py
python3 .bootstrap/v061_stage_center.py
