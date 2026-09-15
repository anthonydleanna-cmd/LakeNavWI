from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
a='const rad=normalizeDegrees(h.degrees)*Math.PI/180;'
b='const visualDeg=Number.isFinite(Number(mapRotationDeg)) ? normalizeDegrees(Number(mapRotationDeg)) : 0;\n      const rad=visualDeg*Math.PI/180;'
if a not in s: raise SystemExit('rotation anchor missing')
p.write_text(s.replace(a,b,1))
