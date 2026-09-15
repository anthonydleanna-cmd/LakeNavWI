from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
s=s.replace("    const h=activeHeading();\n    if (!h || h.degrees == null) return [loc.lat,loc.lon];\n",'',1)
p.write_text(s)
