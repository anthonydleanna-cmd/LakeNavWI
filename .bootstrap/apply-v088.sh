#!/bin/sh
set -eu
base64 -d .bootstrap/v088.patch.gz.b64 | gzip -d > /tmp/v088.patch
patch -p1 < /tmp/v088.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 88/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.88.0'/" app/build.gradle
grep -q 'v0.88' app/src/main/assets/index.html
grep -q 'id="lakeAlertBackdrop"' app/src/main/assets/index.html
grep -q 'html.darkMode body #lakeAlertCard' app/src/main/assets/index.html
grep -q 'Lightning --' app/src/main/assets/index.html
grep -q '#lightningChip { right:12px; bottom:54px' app/src/main/assets/index.html
grep -q 'LakeNavWI/0.88' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'Version 0.88 features' README.md
printf 'LakeNav WI v0.88 themed alerts and Lightning chip polish applied.\n'
