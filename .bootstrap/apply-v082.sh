#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
python3 - <<'PY'
from pathlib import Path
p=Path('app/src/main/assets/index.html')
s=p.read_text()
old_brand='<div id="brand">LakeNav WI <span class="versionPill">v0.81</span></div>'
new_brand='<div id="brand">LakeNav WI <span class="versionPill">v0.82</span></div>'
if old_brand not in s:
    raise SystemExit('v0.82 brand target not found')
s=s.replace(old_brand,new_brand,1)
start=s.find('  function createMarineBaseLayer() {')
end=s.find('\n  function toggleNoaa(on) {',start)
if start<0 or end<0:
    raise SystemExit('v0.82 marine base layer target not found')
new_func=r'''  function createMarineBaseLayer() {
    const MarineTiles=L.GridLayer.extend({
      createTile:function(coords,done) {
        // Keep the actual OSM image visible as soon as it finishes loading. The water-color
        // pass is painted on a transparent canvas afterward, so panning never waits on pixel
        // processing and cannot flash the dark map background between tiles.
        const tile=document.createElement('div');
        tile.style.width='256px'; tile.style.height='256px';
        tile.style.position='relative'; tile.style.overflow='hidden'; tile.style.background='transparent';

        const img=new Image();
        img.alt=''; img.setAttribute('role','presentation');
        img.crossOrigin='anonymous'; img.decoding='async';
        img.style.position='absolute'; img.style.inset='0';
        img.style.width='256px'; img.style.height='256px'; img.style.display='block';
        img.style.pointerEvents='none'; img.style.filter=marineBaseCanvasFilter();

        const canvas=document.createElement('canvas');
        canvas.width=256; canvas.height=256;
        canvas.style.position='absolute'; canvas.style.inset='0';
        canvas.style.width='256px'; canvas.style.height='256px';
        canvas.style.pointerEvents='none';
        const ctx=canvas.getContext('2d',{willReadFrequently:true});
        tile.appendChild(img); tile.appendChild(canvas);

        img.onload=()=>{
          // Mark the tile ready immediately. This is the key flicker fix: Leaflet can reveal
          // the normal filtered OSM image before the optional water recolor work begins.
          img.style.filter=marineBaseCanvasFilter();
          done(null,tile);
          setTimeout(()=>{
            if(!tile.isConnected) return;
            try {
              const sourceCanvas=document.createElement('canvas');
              sourceCanvas.width=256; sourceCanvas.height=256;
              const sourceCtx=sourceCanvas.getContext('2d',{willReadFrequently:true});
              sourceCtx.drawImage(img,0,0,256,256);
              const source=sourceCtx.getImageData(0,0,256,256).data;
              const overlay=ctx.createImageData(256,256);
              const px=overlay.data;
              const dark=darkModeEnabled;
              const wr=dark?82:112, wg=dark?166:205, wb=dark?202:234;
              for(let i=0;i<source.length;i+=4) {
                if(source[i+3] && osmWaterPixel(source[i],source[i+1],source[i+2])) {
                  px[i]=wr; px[i+1]=wg; px[i+2]=wb; px[i+3]=255;
                }
              }
              ctx.clearRect(0,0,256,256);
              ctx.putImageData(overlay,0,0);
            } catch(e) {
              // The underlying OSM image is already visible, so failure here simply leaves
              // the normal chart tile in place rather than ever exposing a blank/dark tile.
              try { ctx.clearRect(0,0,256,256); } catch(ignore) {}
            }
          },0);
        };
        img.onerror=err=>done(err,tile);
        const n=Math.pow(2,coords.z);
        const x=((coords.x%n)+n)%n;
        img.src='https://tile.openstreetmap.org/'+coords.z+'/'+x+'/'+coords.y+'.png';
        return tile;
      }
    });
    return new MarineTiles({
      tileSize:256,maxZoom:19,keepBuffer:10,updateWhenZooming:true,updateWhenIdle:false,updateInterval:120,
      attribution:'&copy; OpenStreetMap contributors'
    });
  }
'''
s=s[:start]+new_func+s[end:]
p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 82/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.82.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v082-inline.js',s)"
node --check /tmp/lakenav-v082-inline.js
grep -q 'v0.82' app/src/main/assets/index.html
grep -q "const tile=document.createElement('div')" app/src/main/assets/index.html
grep -q "done(null,tile);" app/src/main/assets/index.html
grep -q "setTimeout(()=>" app/src/main/assets/index.html
printf 'LakeNav WI v0.82 non-blocking water recolor applied.\n'
