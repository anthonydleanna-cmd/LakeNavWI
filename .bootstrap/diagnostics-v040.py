from pathlib import Path
import re, collections, sys
html=Path('app/src/main/assets/index.html').read_text()
errors=[]
ids=re.findall(r'\bid=["\']([^"\']+)["\']',html)
dup=[k for k,v in collections.Counter(ids).items() if v>1]
if dup: errors.append('duplicate HTML ids: '+', '.join(dup[:20]))
refs=set(re.findall(r"\$\('([^']+)'\)",html)) | set(re.findall(r'\$\("([^"]+)"\)',html))
idset=set(ids)
missing=sorted(x for x in refs-idset if x not in {'spd'})
if missing: errors.append('missing DOM ids referenced by $(): '+', '.join(missing[:20]))
required=['v0.40','trackLiveTail','persistTrackNow','renderHeadingVisualsNow','runNavigationArrowSyncBurst','updateDynamicRangeRings','navigateToClosestBoatLaunch']
for token in required:
    if token not in html: errors.append('missing required v0.40 token: '+token)
if "runNavigationArrowSyncBurst(900)" in html: errors.append('legacy 900ms arrow sync burst still present')
if "trackLine.setLatLngs(trackPoints.map" in html: errors.append('legacy full track redraw still present in hot path')
scripts=re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>',html,re.S|re.I)
Path('/tmp/lakenav-inline.js').write_text('\n'.join(scripts))
print(f'LakeNav diagnostics: {len(html):,} chars, {len(ids)} ids, {len(refs)} DOM refs, {len(scripts)} inline script blocks')
if errors:
    for e in errors: print('ERROR:',e,file=sys.stderr)
    sys.exit(1)
print('Static structure checks passed.')
