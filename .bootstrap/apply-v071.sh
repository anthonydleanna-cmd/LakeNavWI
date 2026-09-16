#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
sed -i "s/versionCode [0-9][0-9]*/versionCode 71/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.71.0'/" app/build.gradle
sed -i 's/<span class="versionPill">v0\.69<\/span>/<span class="versionPill">v0.71<\/span>/' app/src/main/assets/index.html
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v071-inline.js',s)"
node --check /tmp/lakenav-v071-inline.js
grep -q 'v0.71' app/src/main/assets/index.html
! grep -q 'DNR_SURVEY_VECTOR_PACK' app/src/main/assets/index.html
printf 'LakeNav WI v0.71 rollback build applied; v0.70 DNR survey pilot removed.\n'
