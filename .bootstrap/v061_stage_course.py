from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
a="const courseUpVisual = orientationMode === 'courseup' && ((navFollowMode && navCourseAcquired) || freePanHeading != null);"
b="const courseUpVisual = orientationMode === 'courseup' && ((navFollowMode && displayHeading != null) || freePanHeading != null);"
if a not in s: raise SystemExit('course visual anchor missing')
p.write_text(s.replace(a,b,1))
