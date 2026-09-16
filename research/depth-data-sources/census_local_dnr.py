#!/usr/bin/env python3
"""Reliable census entrypoint using DNR's public statewide File Geodatabase.

This overrides the live dnrmaps ArcGIS query in census.py. GitHub-hosted
runners can intermittently time out against dnrmaps, while the authoritative
ArcGIS Online File Geodatabase is a fast, reproducible public download.
"""
from __future__ import annotations

import importlib.util
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

import requests
import pyogrio
from shapely.ops import unary_union

HERE = Path(__file__).resolve().parent
BASE_PATH = HERE / 'census.py'
spec = importlib.util.spec_from_file_location('depth_census_base', BASE_PATH)
base = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = base
spec.loader.exec_module(base)

DNR_ITEM = 'cb1c7f75d14f42ee819a46894fd2e771'
DNR_DATA_URL = f'https://www.arcgis.com/sharing/rest/content/items/{DNR_ITEM}/data'
CACHE = Path('/tmp/lakenav-depth-census')
ZIP_PATH = CACHE / 'WDNR_HYDRO_24K.zip'
EXTRACT = CACHE / 'hydro'


def ensure_dnr_gdb() -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    existing = list(EXTRACT.glob('*.gdb')) if EXTRACT.exists() else []
    if existing:
        return existing[0]
    print('Downloading authoritative Wisconsin DNR 24K Hydro File Geodatabase...', flush=True)
    with requests.get(DNR_DATA_URL, stream=True, timeout=(20, 180)) as r:
        r.raise_for_status()
        total = int(r.headers.get('content-length') or 0)
        got = 0
        with ZIP_PATH.open('wb') as f:
            for chunk in r.iter_content(1024 * 1024):
                if not chunk:
                    continue
                f.write(chunk)
                got += len(chunk)
                if got and got % (50 * 1024 * 1024) < len(chunk):
                    print(f'  downloaded {got / 1024 / 1024:.0f} MiB' + (f' / {total / 1024 / 1024:.0f} MiB' if total else ''), flush=True)
    print(f'  download complete: {ZIP_PATH.stat().st_size / 1024 / 1024:.1f} MiB', flush=True)
    EXTRACT.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ZIP_PATH) as z:
        z.extractall(EXTRACT)
    gdbs = list(EXTRACT.glob('*.gdb'))
    if not gdbs:
        # Some archives may include a containing directory.
        gdbs = list(EXTRACT.rglob('*.gdb'))
    if not gdbs:
        raise RuntimeError('DNR File Geodatabase not found after extraction')
    return gdbs[0]


def choose_waterbody_layer(gdb: Path) -> str:
    layers = pyogrio.list_layers(gdb)
    print('DNR geodatabase layers:', flush=True)
    for name, geom_type in layers:
        print(f'  {name} [{geom_type}]', flush=True)
    candidates = []
    for name, geom_type in layers:
        n = str(name).lower()
        gt = str(geom_type or '').lower()
        score = 0
        if 'waterbody' in n or 'water_body' in n:
            score += 10
        if 'hydro' in n:
            score += 2
        if 'polygon' in gt:
            score += 4
        if score:
            candidates.append((score, str(name)))
    if not candidates:
        raise RuntimeError('Could not locate a polygon waterbody layer in DNR geodatabase')
    candidates.sort(reverse=True)
    print(f'Selected DNR waterbody layer: {candidates[0][1]}', flush=True)
    return candidates[0][1]


def local_load_dnr_waterbodies():
    gdb = ensure_dnr_gdb()
    layer = choose_waterbody_layer(gdb)
    info = pyogrio.read_info(gdb, layer=layer)
    fields = list(info.get('fields') or [])
    upper = {str(x).upper(): str(x) for x in fields}
    required = ['WATERBODY_WBIC', 'HYDROTYPE']
    missing = [x for x in required if x not in upper]
    if missing:
        raise RuntimeError(f'DNR waterbody layer missing required fields {missing}; fields={fields[:80]}')
    wanted_upper = ['OBJECTID', 'HYDROID', 'WATERBODY_WBIC', 'WATERBODY_NAME', 'WATERBODY_ROW_NAME', 'HYDROTYPE', 'ORIG_HRZ_SRC_YR']
    wanted = [upper[x] for x in wanted_upper if x in upper]
    print('Reading lake/pond and reservoir polygons from local DNR geodatabase...', flush=True)
    df = pyogrio.read_dataframe(gdb, layer=layer, columns=wanted, where=f'{upper["HYDROTYPE"]} IN (706,707)')
    print(f'  DNR hydro polygon features: {len(df):,}', flush=True)
    if df.crs is None:
        raise RuntimeError('DNR geodatabase waterbody layer has no CRS')
    if str(df.crs).upper() not in ('EPSG:4326', 'OGC:CRS84'):
        df = df.to_crs(4326)

    groups = defaultdict(list)
    props = defaultdict(list)
    oid_col = upper.get('OBJECTID') or upper.get('HYDROID')
    for idx, row in df.iterrows():
        wbic_val = row.get(upper['WATERBODY_WBIC'])
        try:
            wbic = int(wbic_val) if wbic_val not in (None, '', 0, '0') else None
        except Exception:
            wbic = None
        oid = row.get(oid_col) if oid_col else idx
        key = f'wbic:{wbic}' if wbic else f'object:{oid}'
        g = row.geometry
        if g is None or g.is_empty:
            continue
        if not g.is_valid:
            g = g.buffer(0)
        groups[key].append(g)
        props[key].append({str(k).upper(): row.get(v) for k, v in upper.items() if v in df.columns})

    waters = []
    for key, geoms in groups.items():
        try:
            g = unary_union(geoms)
            if not g.is_valid:
                g = g.buffer(0)
        except Exception:
            g = geoms[0]
        pp = props[key]
        wbic = int(key.split(':', 1)[1]) if key.startswith('wbic:') else None
        names = [x.get('WATERBODY_NAME') or x.get('WATERBODY_ROW_NAME') for x in pp]
        name = next((str(x).strip() for x in names if x and str(x).strip()), 'Unnamed Lake')
        hydros = []
        for x in pp:
            try:
                if x.get('HYDROTYPE') is not None:
                    hydros.append(int(x.get('HYDROTYPE')))
            except Exception:
                pass
        hydrotype = 706 if 706 in hydros else (hydros[0] if hydros else None)
        pt = g.representative_point()
        waters.append({
            'key': key,
            'wbic': wbic,
            'name': name,
            'hydrotype': hydrotype,
            'geometry': g,
            'centroid_lon': round(float(pt.x), 6),
            'centroid_lat': round(float(pt.y), 6),
            'polygon_parts': len(geoms),
        })
    print(f'  Unique DNR waterbody groups: {len(waters):,}', flush=True)
    print(f'  With WBIC: {sum(1 for x in waters if x["wbic"]):,}', flush=True)
    return waters, len(df)


base.load_dnr_waterbodies = local_load_dnr_waterbodies

if __name__ == '__main__':
    base.main()
