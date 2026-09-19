#!/bin/sh
set -eu
base64 -d .bootstrap/v087.patch.gz.b64 | gzip -d > /tmp/v087.patch
patch -p1 < /tmp/v087.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 87/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.87.0'/" app/build.gradle
grep -q 'v0.87' app/src/main/assets/index.html
grep -q 'NOAA MARINE CONDITIONS' app/src/main/assets/index.html
grep -q 'fetchNoaaMarineSnapshot' app/src/main/assets/index.html
grep -q 'forecastGridData' app/src/main/assets/index.html
grep -q 'LakeNavWI/0.87' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'Version 0.87 features' README.md
printf 'LakeNav WI v0.87 NOAA marine conditions applied.\n'
