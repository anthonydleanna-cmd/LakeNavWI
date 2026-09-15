from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
s=s.replace('const aheadPx=Math.max(80,Math.min(420,visibleHeight*(anchorY-.50)));','const anchorOffsetPx=Math.max(80,Math.min(420,visibleHeight*(anchorY-.50)));',1)
p.write_text(s)
