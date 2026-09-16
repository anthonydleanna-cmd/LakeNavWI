#!/usr/bin/env python3
import json
import math
import urllib.parse
from pathlib import Path

import requests

OUT=Path('research_pc_shallows'); OUT.mkdir(exist_ok=True)
STAC='https://planetarycomputer.microsoft.com/api/stac/v1/search'
TILEJSON='https://planetarycomputer.microsoft.com/api/data/v1/item/tilejson.json'

# Crystal Lake, Vilas County — one of the Wisconsin validation lakes.
BBOX=[-89.65,45.97,-89.57,46.04]

# Pooled 5-lake logistic model for <=25 ft optical zone, trained only for the
# experimental LakeNav shallow-envelope study. Sentinel reflectance is DN/10000.
# logit = -84.1146873669 -85.0163404186*b +395.935572607*g
#         +169.498777478*r +327.554079983*n
# p>=0.80 => logit>=1.386294; p>=0.70 => logit>=0.847298.
# Tiler expression uses Sentinel DN directly, hence coefficients /10000.
LP='(-84.1146873669)+(-0.00850163404186*B02)+(0.0395935572607*B03)+(0.0169498777478*B04)+(0.0327554079983*B08)'
# Conservative water mask: low NIR plus green not dramatically below NIR.
WATER='(B08<1600)&(B03>(B08*0.88))'
EXPR=f'where({WATER},where(({LP})>=1.3862943611,2,where(({LP})>=0.8472978604,1,0)),0)'
COLORMAP={
    '0':[0,0,0,0],
    '1':[45,157,205,105],   # transition
    '2':[159,238,229,155],  # likely shallow
}

def main():
    s=requests.Session(); s.headers['User-Agent']='LakeNavWI optical-shallows-endpoint-test/0.1'
    payload={
      'collections':['sentinel-2-l2a'],
      'bbox':BBOX,
      'datetime':'2024-05-01T00:00:00Z/2025-09-15T23:59:59Z',
      'limit':100,
      'query':{'eo:cloud_cover':{'lt':10}},
      'sortby':[{'field':'properties.datetime','direction':'desc'}],
    }
    r=s.post(STAC,json=payload,timeout=90); r.raise_for_status()
    feats=r.json().get('features',[])
    if not feats: raise RuntimeError('No Sentinel-2 items returned')
    # Favor Jul-Sep, then lowest tile cloud, then most recent.
    def rank(f):
        dt=f.get('properties',{}).get('datetime','')
        month=int(dt[5:7]) if len(dt)>=7 else 1
        return (0 if 7<=month<=9 else 1,float(f.get('properties',{}).get('eo:cloud_cover',100)),-int(dt[:10].replace('-','') or 0))
    item=sorted(feats,key=rank)[0]
    item_id=item['id']
    params={
      'collection':'sentinel-2-l2a','item':item_id,
      'expression':EXPR,'asset_as_band':'true','nodata':'0','format':'png',
      'rescale':'0,2','colormap':json.dumps(COLORMAP,separators=(',',':')),
    }
    tr=s.get(TILEJSON,params=params,timeout=90)
    result={'item':item_id,'datetime':item.get('properties',{}).get('datetime'),'cloud':item.get('properties',{}).get('eo:cloud_cover'),
            'expression':EXPR,'tilejson_status':tr.status_code,'tilejson_url':tr.url,'tilejson_text':tr.text[:4000]}
    if tr.ok:
        tj=tr.json(); result['tilejson']=tj
        tile=tj.get('tiles',[None])[0]
        if tile:
            # Fetch one tile at the returned center zoom to ensure rendering succeeds.
            z=int(max(tj.get('minzoom',9),12))
            lon,lat=(BBOX[0]+BBOX[2])/2,(BBOX[1]+BBOX[3])/2
            n=2**z; x=int((lon+180)/360*n); latr=math.radians(lat); y=int((1-math.asinh(math.tan(latr))/math.pi)/2*n)
            tile_url=tile.replace('{z}',str(z)).replace('{x}',str(x)).replace('{y}',str(y))
            ir=s.get(tile_url,timeout=90)
            result.update({'tile_status':ir.status_code,'tile_content_type':ir.headers.get('content-type'),'tile_bytes':len(ir.content),'tile_url':tile_url})
            if ir.ok: (OUT/'sample_tile.png').write_bytes(ir.content)
    (OUT/'result.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2)[:12000])
    if tr.status_code!=200 or result.get('tile_status')!=200:
        raise SystemExit(2)

if __name__=='__main__': main()
