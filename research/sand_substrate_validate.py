#!/usr/bin/env python3
import json, math, os
from pathlib import Path
import numpy as np
import pandas as pd
import requests
import rasterio
from rasterio.windows import from_bounds
from pyproj import Transformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, confusion_matrix, balanced_accuracy_score, accuracy_score
from sklearn.model_selection import GroupKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

OUT=Path('research_sand_validation'); OUT.mkdir(exist_ok=True)
STAC='https://earth-search.aws.element84.com/v1/search'
XLS=Path('research_optical_shallows/sand_lake_2018.xlsx')
UA='LakeNavWI optical-sand-validation/0.1'


def scene_for_bbox(bbox):
    s=requests.Session(); s.headers['User-Agent']=UA
    payload={'collections':['sentinel-2-c1-l2a'],'bbox':bbox,
             'datetime':'2018-06-15T00:00:00Z/2018-09-15T23:59:59Z','limit':100,
             'query':{'eo:cloud_cover':{'lt':25}}}
    r=s.post(STAC,json=payload,timeout=90); r.raise_for_status()
    feats=r.json().get('features',[])
    if not feats: raise RuntimeError('No Sentinel-2 scene found')
    target=pd.Timestamp('2018-08-01',tz='UTC')
    def rank(f):
        p=f.get('properties',{}); dt=pd.Timestamp(p.get('datetime'))
        cloud=float(p.get('eo:cloud_cover',100))
        return (cloud>8, abs((dt-target).days), cloud)
    f=sorted(feats,key=rank)[0]; a=f['assets']
    return {'id':f['id'],'datetime':f['properties'].get('datetime'),'cloud':f['properties'].get('eo:cloud_cover'),
            'blue':a['blue']['href'],'green':a['green']['href'],'red':a['red']['href'],'nir':a['nir']['href']}


def crop_and_sample(url, lon, lat, pad=0.01):
    # Compact remote COG crop around lake, then nearest-pixel sample.
    env=rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif,.TIF',
                     GDAL_HTTP_MULTIPLEX='YES',GDAL_HTTP_MERGE_CONSECUTIVE_RANGES='YES')
    env.__enter__(); ds=rasterio.open(url)
    try:
        tr=Transformer.from_crs('EPSG:4326',ds.crs,always_xy=True)
        xx,yy=tr.transform(lon,lat)
        minx,maxx=min(xx),max(xx); miny,maxy=min(yy),max(yy)
        margin=150
        w=from_bounds(minx-margin,miny-margin,maxx+margin,maxy+margin,transform=ds.transform).round_offsets().round_lengths()
        w=w.intersection(rasterio.windows.Window(0,0,ds.width,ds.height))
        arr=ds.read(1,window=w,masked=True).astype('float32')
        tx=ds.window_transform(w); inv=~tx
        cols,rows=inv*(np.asarray(xx),np.asarray(yy)); rows=np.floor(rows).astype(int); cols=np.floor(cols).astype(int)
        valid=(rows>=0)&(cols>=0)&(rows<arr.shape[0])&(cols<arr.shape[1])
        out=np.full(len(lon),np.nan,float); ii=np.where(valid)[0]
        vals=arr[rows[ii],cols[ii]]; out[ii]=np.asarray(vals.filled(np.nan) if hasattr(vals,'filled') else vals,float)
        return out
    finally:
        ds.close(); env.__exit__(None,None,None)


def spatial_groups(lat,lon,size=0.0025):
    # ~200-300 m blocks in northern Wisconsin.
    a=np.floor((np.asarray(lat)-min(lat))/size).astype(int)
    b=np.floor((np.asarray(lon)-min(lon))/size).astype(int)
    return np.array([f'{x}_{y}' for x,y in zip(a,b)])


def metric(y,p):
    rep=classification_report(y,p,labels=['sand','non_sand'],output_dict=True,zero_division=0)
    return {'n':int(len(y)),'accuracy':float(accuracy_score(y,p)),'balanced_accuracy':float(balanced_accuracy_score(y,p)),
            'confusion_sand_non_sand':confusion_matrix(y,p,labels=['sand','non_sand']).tolist(),'report':rep}


def cv_model(df, features, kind):
    X=df[features].to_numpy(float); y=df.target.to_numpy(); g=df.group.to_numpy()
    splits=min(5,len(np.unique(g))); pred=np.empty(len(df),dtype=object); prob=np.full(len(df),np.nan)
    if splits<2: raise RuntimeError('Too few spatial groups')
    cv=GroupKFold(n_splits=splits)
    for tr,te in cv.split(X,y,g):
        if kind=='logistic':
            m=make_pipeline(StandardScaler(),LogisticRegression(max_iter=2000,class_weight='balanced',C=.5))
        else:
            m=RandomForestClassifier(n_estimators=400,max_depth=7,min_samples_leaf=8,class_weight='balanced_subsample',random_state=42,n_jobs=-1)
        m.fit(X[tr],y[tr]); pred[te]=m.predict(X[te]); cls=list(m.classes_); prob[te]=m.predict_proba(X[te])[:,cls.index('sand')]
    return pred,prob,metric(y,pred)


def main():
    x=pd.read_excel(XLS,sheet_name='2018 Mapping Data')
    d=x[['Latitude','Longitude','Depth','Substrate']].copy().dropna(subset=['Latitude','Longitude','Substrate'])
    d.Substrate=d.Substrate.astype(str).str.strip().str.upper()
    d=d[d.Substrate.isin(['S','R','M'])].copy()
    d['target']=np.where(d.Substrate=='S','sand','non_sand')
    bbox=[float(d.Longitude.min()-0.01),float(d.Latitude.min()-0.01),float(d.Longitude.max()+0.01),float(d.Latitude.max()+0.01)]
    scene=scene_for_bbox(bbox); print('Scene',scene['id'],scene['datetime'],'cloud',scene['cloud'],flush=True)
    for band in ['blue','green','red','nir']:
        d[band]=crop_and_sample(scene[band],d.Longitude.to_numpy(),d.Latitude.to_numpy())/10000.0
    d=d.replace([np.inf,-np.inf],np.nan).dropna().copy()
    # water-ish filter; retain shallow bright bottoms while excluding obvious land/invalid pixels
    d=d[(d.green>0.001)&(d.blue>0.001)&(d.nir>=0)&(d.nir<0.18)].copy()
    eps=1e-4
    d['log_bg']=np.log((d.blue+eps)/(d.green+eps)); d['log_gr']=np.log((d.green+eps)/(d.red+eps))
    d['ndwi']=(d.green-d.nir)/(d.green+d.nir+eps); d['brightness']=(d.blue+d.green+d.red)/3
    d['sand_index']=(d.red+d.green)/(d.blue+eps)
    d['group']=spatial_groups(d.Latitude.to_numpy(),d.Longitude.to_numpy())
    features=['blue','green','red','nir','log_bg','log_gr','ndwi','brightness','sand_index']
    results={'scene':scene,'field_points_total':int(len(x)),'usable_substrate_points':int(len(d)),
             'class_counts':d.target.value_counts().to_dict(),'substrate_counts':d.Substrate.value_counts().to_dict(),'models':{}}
    # all-sand baseline is important because this lake is sand-dominant
    baseline=np.array(['sand']*len(d)); results['baseline_all_sand']=metric(d.target.to_numpy(),baseline)
    for kind in ['logistic','rf']:
        pred,prob,m=cv_model(d,features,kind); d['pred_'+kind]=pred; d['p_sand_'+kind]=prob; results['models'][kind]=m
        # high-confidence precision / recall table
        tbl=[]
        for th in [.6,.7,.8,.9]:
            sel=prob>=th; tp=((d.target.to_numpy()=='sand')&sel).sum(); total=(d.target=='sand').sum()
            tbl.append({'threshold':th,'selected':int(sel.sum()),'precision_pct':float((d.loc[sel,'target']=='sand').mean()*100) if sel.sum() else None,
                        'recall_pct':float(tp/total*100) if total else None,'coverage_pct':float(sel.mean()*100)})
        results['models'][kind]['high_confidence_sand']=tbl
    d.to_csv(OUT/'sand_samples_predictions.csv',index=False)
    (OUT/'results.json').write_text(json.dumps(results,indent=2,default=str))
    best=max(results['models'].items(),key=lambda kv:kv[1]['balanced_accuracy'])
    b=results['baseline_all_sand']; m=best[1]
    lines=['# LakeNav WI probable-sand validation','',
           f"Field ground truth: Wisconsin DNR Sand Lake 2018 point-intercept substrate survey. Usable points: {len(d)}.",
           f"Sentinel-2 scene: `{scene['id']}` ({scene['datetime']}, tile cloud {scene['cloud']}).",'',
           'The field substrate classes are S (sand), R (rock), and M (muck). Sand is tested against rock+muck.','',
           '| Method | Accuracy | Balanced accuracy | Sand precision | Sand recall | Non-sand recall |','|---|---:|---:|---:|---:|---:|',
           f"| All-sand baseline | {b['accuracy']*100:.1f}% | {b['balanced_accuracy']*100:.1f}% | {b['report']['sand']['precision']*100:.1f}% | {b['report']['sand']['recall']*100:.1f}% | {b['report']['non_sand']['recall']*100:.1f}% |"]
    for name,r in results['models'].items():
        lines.append(f"| {name} spatial CV | {r['accuracy']*100:.1f}% | {r['balanced_accuracy']*100:.1f}% | {r['report']['sand']['precision']*100:.1f}% | {r['report']['sand']['recall']*100:.1f}% | {r['report']['non_sand']['recall']*100:.1f}% |")
    lines += ['', 'Spatial group cross-validation holds out geographic blocks to reduce neighboring-pixel leakage. Because Sand Lake is highly sand-dominant, balanced accuracy and non-sand recall are more informative than raw accuracy.', '', '## High-confidence probable-sand calls']
    r=results['models'][best[0]]; lines += [f"Best balanced model: **{best[0]}**",'', '| Threshold | Precision | Recall | Coverage |','|---|---:|---:|---:|']
    for q in r['high_confidence_sand']:
        lines.append(f"| {q['threshold']:.1f} | {q['precision_pct']:.1f}% | {q['recall_pct']:.1f}% | {q['coverage_pct']:.1f}% |")
    (OUT/'README.md').write_text('\n'.join(lines)+'\n'); print((OUT/'README.md').read_text())

if __name__=='__main__': main()
