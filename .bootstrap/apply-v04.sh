#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p app/src/main/assets app/src/main/java/com/lakenav/wi app/src/main/res/drawable
cat .bootstrap/README.md.gz.b64 | base64 -d | gzip -d > README.md
cat .bootstrap/app_build.gradle.gz.b64 | base64 -d | gzip -d > app/build.gradle
cat .bootstrap/AndroidManifest.xml.gz.b64.part00 | base64 -d | gzip -d > app/src/main/AndroidManifest.xml
cat .bootstrap/MainActivity.java.gz.b64.part00 | base64 -d | gzip -d > app/src/main/java/com/lakenav/wi/MainActivity.java
cat .bootstrap/index.html.gz.b64.part00 .bootstrap/index.html.gz.b64.part01 .bootstrap/index.html.gz.b64.part02 | base64 -d | gzip -d > app/src/main/assets/index.html
cat > app/src/main/res/drawable/app_icon.xml <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#063B66" android:pathData="M0,0h108v108h-108z"/>
    <path android:fillColor="#FFFFFF" android:pathData="M30,15 L63,10 L82,23 L89,42 L80,61 L65,70 L57,92 L39,87 L31,70 L19,59 L22,39 Z"/>
    <path android:fillColor="#16A6C9" android:pathData="M18,74 C36,64 52,82 70,72 C84,64 93,70 108,68 L108,88 C91,92 79,82 63,90 C45,99 30,84 18,94 Z"/>
    <path android:fillColor="#063B66" android:pathData="M54,25 L61,49 L55,46 L49,66 L46,46 L40,49 Z"/>
    <path android:fillColor="#16A6C9" android:pathData="M54,30 L57,47 L53,45 L50,56 L49,45 L45,47 Z"/>
</vector>
EOF
printf 'LakeNav WI v0.4 sources materialized for build.\n'
