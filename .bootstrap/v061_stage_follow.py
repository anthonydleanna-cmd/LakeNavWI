from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
a="if (target) map.panTo(target,{animate:true,duration:.58,easeLinearity:.18,noMoveStart:true});"
b="if (target) map.panTo(target,{animate:false,noMoveStart:true});"
if a not in s: raise SystemExit('follow camera anchor missing')
p.write_text(s.replace(a,b,1))
