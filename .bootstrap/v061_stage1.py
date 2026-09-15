from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
s=s.replace('<div id="brand">LakeNav WI <span class="versionPill">v0.60</span></div>','<div id="brand">LakeNav WI <span class="versionPill">v0.61</span></div>',1)
s=s.replace('  let navArrowSyncUntil = 0;\n','  let navArrowSyncUntil = 0;\n  let navAnchorRecenterTimer = null;\n  let lastNavAnchorRecenterAt = 0;\n',1)
s=s.replace('/* v0.60 true GPS-anchored Course Up camera */','/* v0.61 GPS-coordinate screen lock */\n#mapWrap.navGpsPinned #map { will-change:transform; }\n\n/* v0.60 true GPS-anchored Course Up camera */',1)
p.write_text(s)
