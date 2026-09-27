#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

base64 -d .bootstrap/v092.patch.gz.b64 | gzip -d > /tmp/v092.patch
patch -p1 < /tmp/v092.patch

sed -i "s/versionCode [0-9][0-9]*/versionCode 92/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.92.0'/" app/build.gradle

if ! grep -q '## Version 0.92 features' README.md; then
cat >> README.md <<'EOF'

## Version 0.92 features
- Full-screen black-and-white navigation presentation over the Android keyguard while active LakeNav navigation is running.
- Wake the phone during navigation to see the route line, boat marker, current target, next target, remaining distance, and ETA without exposing normal map controls.
- The existing v0.91 navigation notification remains as a fallback and waypoint/route-complete alerts remain active.
- This Phase 1 implementation does not keep the display awake; normal screen timeout and power-button behavior are preserved.
EOF
fi

node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v092-inline.js',s)"
node --check /tmp/lakenav-v092-inline.js

grep -q 'v0.92' app/src/main/assets/index.html
grep -q 'LockScreenNavigationView' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'setShowWhenLocked' app/src/main/java/com/lakenav/wi/MainActivity.java
grep -q 'class LockScreenNavigationView' app/src/main/java/com/lakenav/wi/LockScreenNavigationView.java
grep -q 'lastLat' app/src/main/java/com/lakenav/wi/NavigationService.java
grep -q 'Version 0.92 features' README.md
printf 'LakeNav WI v0.92 full-screen lock-screen navigation phase 1 applied.\n'
