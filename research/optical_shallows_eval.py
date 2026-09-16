#!/usr/bin/env python3
import io, json, math, os, re
from pathlib import Path
import numpy as np
import pandas as pd
import requests
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

OUT=Path('research_optical_shallows'); OUT.mkdir(exist_ok=True)
SAMPLES=Path('research_validation/samples_and_predictions.csv')
FEATURES=['blue','green','red','nir','log_bg','log_gr','blue_green_stumpf','ndwi']


def weighted_fit(train, target):
    lake_counts=train.lake_id.value_counts(); class_counts=train[target].value_counts()
    w=train.lake_id.map(lambda x:1/lake_counts[x]).to_numpy(float)*train[target].map(lambda x:1/class_counts[x]).to_numpy(float)
    w=w/w.mean()
    m=make_pipeline(StandardScaler(),LogisticRegression(max_iter=2000,C=.5))
    m.fit(train[FEATURES],train[target],logisticregression__sample_weight=w)
    return m


def loo_binary(df, label_func, positive):
    rec=[]
    work=df.copy(); work['target']=work.depth_ft.map(label_func)
    for hold in sorted(work.lake_id.unique()):
        tr=work[work.lake_id!=hold].copy(); te=work[work.lake_id==hold].copy()
        m=weighted_fit(tr,'target')
        cls=list(m.named_steps['logisticregression'].classes_)
        p=m.predict_proba(te[FEATURES])[:,cls.index(positive)]
        z=te[['lake_id','depth_ft','target']].copy(); z['p']=p; rec.append(z)
    return pd.concat(rec,ignore_index=True)


def threshold_table(z, positive):
    rows=[]; total_pos=(z.target==positive).sum()
    for th in [0.5,0.6,0.7,0.8,0.9]:
        sel=z.p>=th
        tp=((z.target==positive)&sel).sum()
        rows.append({'threshold':th,'selected':int(sel.sum()),'coverage_pct':float(sel.mean()*100),
                     'precision_pct':float((z.loc[sel,'target']==positive).mean()*100) if sel.sum() else None,
                     'recall_pct':float(tp/total_pos*100) if total_pos else None})
    return rows


def sand_probe():
    docs={2018:'https://apps.dnr.wi.gov/water/wsSWIMSDocument.ashx?documentSeqNo=196089516',
          2017:'https://apps.dnr.wi.gov/water/wsSWIMSDocument.ashx?documentSeqNo=196089510',
          2016:'https://apps.dnr.wi.gov/water/wsSWIMSDocument.ashx?documentSeqNo=196089529'}
    out={}
    s=requests.Session(); s.headers['User-Agent']='LakeNavWI optical shallows research/0.1'
    for year,url in docs.items():
        item={'url':url}
        try:
            r=s.get(url,timeout=60); item['status']=r.status_code; item['content_type']=r.headers.get('content-type'); item['bytes']=len(r.content)
            if r.ok and len(r.content)>1000:
                p=OUT/f'sand_lake_{year}.xlsx'; p.write_bytes(r.content)
                try:
                    xl=pd.ExcelFile(p)
                    item['sheets']=[]
                    for sh in xl.sheet_names:
                        try:
                            d=pd.read_excel(p,sheet_name=sh)
                            cols=[str(c) for c in d.columns]
                            interesting=[c for c in cols if re.search(r'lat|lon|long|substr|bottom|depth|point|site|coord|x$|y$',c,re.I)]
                            item['sheets'].append({'name':sh,'rows':int(len(d)),'columns':cols,'interesting':interesting,
                                                   'sample':d[interesting].head(8).where(pd.notna(d[interesting]),None).to_dict('records') if interesting else []})
                        except Exception as e: item['sheets'].append({'name':sh,'error':repr(e)})
                except Exception as e: item['excel_error']=repr(e); item['head_hex']=r.content[:32].hex()
        except Exception as e: item['error']=repr(e)
        out[str(year)]=item
    return out


def main():
    df=pd.read_csv(SAMPLES)
    # Broad optical shallow-water envelope: <=25 ft vs deeper water.
    opt=loo_binary(df,lambda z:'optical' if z<=25 else 'deep','optical')
    # Conservative shallow core: <=10 ft vs everything else.
    sh=loo_binary(df,lambda z:'shallow' if z<=10 else 'other','shallow')
    # Direct shelf test: 10-25 ft vs all other depths (diagnostic only).
    shelf=loo_binary(df,lambda z:'shelf' if (z>10 and z<=25) else 'other','shelf')
    result={'n_samples':int(len(df)),'lakes':sorted(df.lake_id.unique().tolist()),
            'optical_zone_le25':threshold_table(opt,'optical'),
            'shallow_core_le10':threshold_table(sh,'shallow'),
            'direct_shelf_10_25':threshold_table(shelf,'shelf'),
            'sand_lake_dnr_spreadsheet_probe':sand_probe()}
    (OUT/'results.json').write_text(json.dumps(result,indent=2,default=str))
    def row_for(rows,th): return next(x for x in rows if x['threshold']==th)
    o8=row_for(result['optical_zone_le25'],.8); s7=row_for(result['shallow_core_le10'],.7); f7=row_for(result['direct_shelf_10_25'],.7)
    lines=['# LakeNav WI Optical Shallows Study','',
           'Validation uses leave-one-lake-out testing: the held-out lake contributes no depth labels to model training.','',
           '## Conservative feature detection','',
           '| Feature test | Confidence threshold | Precision | Recall | Map/sample coverage |','|---|---:|---:|---:|---:|',
           f"| Broad optical zone (known depth <=25 ft) | 0.80 | {o8['precision_pct']:.1f}% | {o8['recall_pct']:.1f}% | {o8['coverage_pct']:.1f}% |",
           f"| Shallow core (known depth <=10 ft) | 0.70 | {s7['precision_pct']:.1f}% | {s7['recall_pct']:.1f}% | {s7['coverage_pct']:.1f}% |",
           f"| Direct shelf class (10-25 ft) | 0.70 | {f7['precision_pct']:.1f}% | {f7['recall_pct']:.1f}% | {f7['coverage_pct']:.1f}% |",'',
           'Interpretation: the broad shallow-water envelope is substantially more transferable than an exact shelf class. The shelf should therefore be rendered from the outer gradient/boundary of the reliable optical envelope, rather than classified independently.','',
           '## Sand ground-truth probe','',
           'Wisconsin DNR Sand Lake point-intercept spreadsheets were downloaded and inspected for coordinate/substrate fields. See results.json for workbook schemas and samples.']
    (OUT/'README.md').write_text('\n'.join(lines)+'\n')
    print((OUT/'README.md').read_text())
    print(json.dumps(result['sand_lake_dnr_spreadsheet_probe'],indent=2,default=str)[:12000])

if __name__=='__main__': main()
