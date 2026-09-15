#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cat .bootstrap/v056.patch.gz.b64.part00 \
    .bootstrap/v056.patch.gz.b64.part01 \
    .bootstrap/v056.patch.gz.b64.part02 \
  | base64 -d | gzip -d > /tmp/v056.patch
patch -p1 < /tmp/v056.patch
sed -i "s/versionCode [0-9][0-9]*/versionCode 56/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.56.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v056-inline.js',s)"
node --check /tmp/lakenav-v056-inline.js
grep -q 'v0.56' app/src/main/assets/index.html
grep -q "localStorage.getItem(STORAGE_DARK_MODE) !== '0'" app/src/main/assets/index.html
grep -q 'html.darkMode body #weatherQuickPanel' app/src/main/assets/index.html
grep -q 'document.documentElement.classList.toggle' app/src/main/assets/index.html
python3 - <<'PY'
from pathlib import Path
import re, collections
s=Path('app/src/main/assets/index.html').read_text()
ids=re.findall(r'\\bid="([^"]+)"',s)
dups=[k for k,v in collections.Counter(ids).items() if v>1]
if dups: raise SystemExit('Duplicate DOM ids: '+', '.join(dups[:12]))
required=['weatherQuickPanel','layersQuickPanel','settingsSheet','darkModeToggle','toolbar','depthLegend']
missing=[x for x in required if f'id="{x}"' not in s]
if missing: raise SystemExit('Missing critical UI ids: '+', '.join(missing))
print(f'LakeNav dark diagnostics: {len(ids)} unique ids; critical dark UI targets present.')
PY
printf 'LakeNav WI v0.56 dark-mode default, flicker guard, contrast pass, and diagnostics applied.\n'
