#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
sed -i '938s/v0.61/v0.62/' app/src/main/assets/index.html
sed -i '2785s/1.3/.45/;2785s/3.5/2.2/' app/src/main/assets/index.html
sed -i '2790s/14/7/;2790s/5/2.5/' app/src/main/assets/index.html
sed -i '2792s/0.30/0.18/;2792s/0.10/0.055/' app/src/main/assets/index.html
sed -i '3460s/0.18/0.10/' app/src/main/assets/index.html
sed -i '3576s/70/40/;3577s/70/40/' app/src/main/assets/index.html
sed -i "s/versionCode [0-9][0-9]*/versionCode 62/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.62.0'/" app/build.gradle
printf 'LakeNav WI v0.62 smoothing applied.\n'
