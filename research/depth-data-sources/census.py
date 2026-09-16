#!/usr/bin/env python3
import csv
import json
import math
import re
import sys
import time
from collections import defaultdict
from pathlib import Path
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup
from shapely.geometry import shape, mapping, box
from shapely.ops import unary_union

OUT = Path('research/depth-data-sources/output')
OUT.mkdir(parents=True, exist_ok=True)

WI_BBOX = (-92.90, 42.45, -86.20, 47.40)
DNR_LAKES = 'https://dnrmaps.wi.gov/arcgis/rest/services/ER_Biotics/ER_Biotics_WGS84_Hydro/MapServer/0'
DNR_MAPS = 'https://apps.dnr.wi.gov/lakes/Documents/LakeMaps.aspx'
NOAA_COVERAGE = 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coverage/MapServer'
NOAA_SERVICES = {
    'overview': 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_overview/MapServer',
    'general': 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_general/MapServer',
    'coastal': 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coastal/MapServer',
    'approach': 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_approach/MapServer',
    'harbour': 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_harbour/MapServer',
    'berthing': 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_berthing/MapServer',
}
NOAA_COVERAGE_LAYERS = {'overview': 0, 'general': 1, 'coastal': 2, 'approach': 3, 'harbour': 4, 'berthing': 5}
USACE_DEPTH = 'https://ienccloud.us/arcgis/rest/services/IENC_Feature_Classes/DEPTH_AREA/MapServer/96'

S = requests.Session()
S.headers.update({'User-Agent': 'LakeNavWI-depth-census/0.1 (research)'})


def get(url, params=None, timeout=90, tries=4):
    last = None
    for i in range(tries):
        try:
            r = S.get(url, params=params, timeout=timeout)
            r.raise_for_status()
            return r
        except Exception as e:
            last = e
            if i + 1 < tries:
                time.sleep(1.0 * (i + 1))
    raise last


def post(url, data=None, timeout=90, tries=4):
    last = None
    for i in range(tries):
        try:
            r = S.post(url, data=data, timeout=timeout)
            r.raise_for_status()
            return r
        except Exception as e:
            last = e
            if i + 1 < tries:
                time.sleep(1.0 * (i + 1))
    raise last


def arcgis_ids(layer_url, where='1=1', geometry=None):
    p = {'where': where, 'returnIdsOnly': 'true', 'f': 'json'}
    if geometry:
        p.update({
            'geometry': ','.join(str(x) for x in geometry),
            'geometryType': 'esriGeometryEnvelope',
            'inSR': '4326',
            'spatialRel': 'esriSpatialRelIntersects',
        })
    j = get(layer_url + '/query', p).json()
    if 'error' in j:
        raise RuntimeError(f'ArcGIS ID query failed {layer_url}: {j["error"]}')
    return list(j.get('objectIds') or [])


def arcgis_geojson_by_ids(layer_url, ids, fields='*', batch=250):
    out = []
    for i in range(0, len(ids), batch):
        chunk = ids[i:i+batch]
        p = {
            'objectIds': ','.join(str(x) for x in chunk),
            'outFields': fields,
            'returnGeometry': 'true',
            'outSR': '4326',
            'geometryPrecision': '6',
            'f': 'geojson',
        }
        j = get(layer_url + '/query', p).json()
        if 'error' in j:
            raise RuntimeError(f'ArcGIS feature query failed {layer_url}: {j["error"]}')
        out.extend(j.get('features') or [])
    return out


def safe_shape(feature):
    try:
        g = shape(feature['geometry'])
        if not g.is_valid:
            g = g.buffer(0)
        return g if not g.is_empty else None
    except Exception:
        return None


def load_dnr_waterbodies():
    print('Loading Wisconsin DNR lake/pond and reservoir polygons...', flush=True)
    ids = arcgis_ids(DNR_LAKES, 'HYDROTYPE IN (706,707)')
    print(f'  DNR hydro polygon features: {len(ids):,}', flush=True)
    feats = arcgis_geojson_by_ids(
        DNR_LAKES,
        ids,
        'OBJECTID,WATERBODY_WBIC,WATERBODY_NAME,WATERBODY_ROW_NAME,HYDROTYPE,ORIG_HRZ_SRC_YR'
    )
    groups = defaultdict(list)
    props = defaultdict(list)
    for f in feats:
        p = f.get('properties') or {}
        oid = p.get('OBJECTID')
        wbic = p.get('WATERBODY_WBIC')
        try:
            wbic = int(wbic) if wbic not in (None, '', 0, '0') else None
        except Exception:
            wbic = None
        key = f'wbic:{wbic}' if wbic else f'object:{oid}'
        g = safe_shape(f)
        if g is None:
            continue
        groups[key].append(g)
        props[key].append(p)

    waters = []
    for key, geoms in groups.items():
        try:
            g = unary_union(geoms)
            if not g.is_valid:
                g = g.buffer(0)
        except Exception:
            g = geoms[0]
        pp = props[key]
        wbic = None
        if key.startswith('wbic:'):
            wbic = int(key.split(':', 1)[1])
        names = [x.get('WATERBODY_NAME') or x.get('WATERBODY_ROW_NAME') for x in pp]
        name = next((str(x).strip() for x in names if x and str(x).strip()), 'Unnamed Lake')
        hydros = [int(x.get('HYDROTYPE')) for x in pp if x.get('HYDROTYPE') is not None]
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
    return waters, len(ids)


def parse_num(text):
    t = re.sub(r'[^0-9.\-]+', '', str(text or ''))
    try:
        return float(t) if t else None
    except Exception:
        return None


def find_map_table(soup):
    for table in soup.find_all('table'):
        headers = [x.get_text(' ', strip=True).upper() for x in table.find_all('th')]
        if 'WBIC' in headers and any('MAX DEPTH' in h for h in headers):
            return table
    return None


def parse_map_rows(soup):
    table = find_map_table(soup)
    if not table:
        return []
    rows = []
    for tr in table.find_all('tr'):
        cells = [td.get_text(' ', strip=True) for td in tr.find_all('td')]
        if len(cells) < 6:
            continue
        name, county, area, max_depth, location, wbic = cells[:6]
        m = re.search(r'\d+', wbic.replace(',', ''))
        if not m:
            continue
        rows.append({
            'name': name.strip(),
            'county': county.strip(),
            'area_acres': parse_num(area),
            'max_depth_ft': parse_num(max_depth),
            'location': location.strip(),
            'wbic': int(m.group(0)),
        })
    return rows


def aspnet_next_request(soup, current_url):
    candidate = None
    for a in soup.find_all('a'):
        txt = a.get_text(' ', strip=True).lower()
        if txt in ('next >', 'next', '>') or txt.startswith('next'):
            candidate = a
            break
    if not candidate:
        return None
    href = candidate.get('href') or ''
    if href and not href.lower().startswith('javascript:'):
        return ('GET', urljoin(current_url, href), None)
    m = re.search(r"__doPostBack\('([^']*)','([^']*)'\)", href)
    if not m:
        return None
    data = {}
    form = candidate.find_parent('form') or soup.find('form')
    if form:
        for inp in form.find_all('input'):
            name = inp.get('name')
            if not name:
                continue
            typ = (inp.get('type') or '').lower()
            if typ in ('submit', 'button', 'image'):
                continue
            data[name] = inp.get('value') or ''
    data['__EVENTTARGET'] = m.group(1)
    data['__EVENTARGUMENT'] = m.group(2)
    return ('POST', current_url, data)


def scrape_dnr_historical_maps(max_pages=300):
    print('Scraping Wisconsin DNR historical lake-map index...', flush=True)
    current_url = DNR_MAPS
    response = get(current_url)
    records = []
    pages = 0
    seen_fingerprints = set()
    while pages < max_pages:
        pages += 1
        soup = BeautifulSoup(response.text, 'html.parser')
        batch = parse_map_rows(soup)
        fingerprint = tuple((x['wbic'], x['county']) for x in batch)
        if fingerprint in seen_fingerprints and pages > 1:
            break
        seen_fingerprints.add(fingerprint)
        records.extend(batch)
        if pages % 20 == 0 or pages == 1:
            print(f'  historical map pages: {pages}, rows: {len(records):,}', flush=True)
        nxt = aspnet_next_request(soup, response.url)
        if not nxt:
            break
        method, url, data = nxt
        response = post(url, data=data) if method == 'POST' else get(url)
    by_wbic = {}
    for r in records:
        # Some lakes span counties and appear multiple times; keep one WBIC record and preserve counties.
        w = r['wbic']
        if w not in by_wbic:
            by_wbic[w] = dict(r, counties={r['county']} if r['county'] else set())
        else:
            if r['county']:
                by_wbic[w]['counties'].add(r['county'])
            for fld in ('area_acres', 'max_depth_ft'):
                if by_wbic[w].get(fld) is None and r.get(fld) is not None:
                    by_wbic[w][fld] = r[fld]
    for r in by_wbic.values():
        r['county'] = ', '.join(sorted(r.pop('counties')))
    print(f'  pages read: {pages}; unique mapped WBICs: {len(by_wbic):,}', flush=True)
    return by_wbic, {'pages': pages, 'raw_rows': len(records)}


def load_noaa_coverage():
    print('Loading NOAA ENC coverage polygons intersecting Wisconsin...', flush=True)
    cov = []
    for scale, layer_id in NOAA_COVERAGE_LAYERS.items():
        url = f'{NOAA_COVERAGE}/{layer_id}'
        try:
            ids = arcgis_ids(url, geometry=WI_BBOX)
            feats = arcgis_geojson_by_ids(url, ids, '*', batch=200)
            good = []
            for f in feats:
                g = safe_shape(f)
                if g is not None:
                    good.append(g)
            if good:
                cov.append((scale, unary_union(good)))
            print(f'  {scale}: {len(good):,} coverage polygons', flush=True)
        except Exception as e:
            print(f'  WARNING NOAA {scale} coverage failed: {e}', flush=True)
    return cov


def noaa_depth_layer_ids(service_url):
    j = get(service_url, {'f': 'json'}).json()
    hits = []
    for layer in j.get('layers') or []:
        name = str(layer.get('name') or '')
        lname = name.lower()
        if 'depth_contour_line' in lname or 'depth_area' in lname or 'sounding_point' in lname:
            hits.append((int(layer['id']), name))
    return hits


def shapely_to_esri_polygon(g, max_vertices=1800):
    if g is None or g.is_empty:
        return None
    gg = g.simplify(0.0005, preserve_topology=True)
    polygons = [gg] if gg.geom_type == 'Polygon' else list(gg.geoms) if gg.geom_type == 'MultiPolygon' else []
    rings = []
    total = 0
    for p in polygons:
        coords = [[round(x, 6), round(y, 6)] for x, y in p.exterior.coords]
        if len(coords) > max_vertices:
            stride = max(1, math.ceil(len(coords) / max_vertices))
            coords = coords[::stride]
            if coords[0] != coords[-1]:
                coords.append(coords[0])
        total += len(coords)
        rings.append(coords)
        if total >= max_vertices:
            break
    return {'rings': rings, 'spatialReference': {'wkid': 4326}} if rings else None


def arcgis_count_polygon(layer_url, g):
    geom = shapely_to_esri_polygon(g)
    if not geom:
        return 0
    p = {
        'where': '1=1',
        'geometry': json.dumps(geom, separators=(',', ':')),
        'geometryType': 'esriGeometryPolygon',
        'inSR': '4326',
        'spatialRel': 'esriSpatialRelIntersects',
        'returnCountOnly': 'true',
        'f': 'json',
    }
    j = get(layer_url + '/query', p, timeout=75).json()
    if 'error' in j:
        raise RuntimeError(j['error'])
    return int(j.get('count') or 0)


def classify_noaa(waters, coverage):
    print('Matching DNR waterbodies to NOAA ENC coverage...', flush=True)
    candidates = []
    rank = {'overview': 0, 'general': 1, 'coastal': 2, 'approach': 3, 'harbour': 4, 'berthing': 5}
    for w in waters:
        scales = [s for s, g in coverage if w['geometry'].intersects(g)]
        if scales:
            scales.sort(key=lambda s: rank.get(s, -1), reverse=True)
            w['noaa_enc_coverage'] = True
            w['noaa_enc_scale'] = scales[0]
            candidates.append(w)
        else:
            w['noaa_enc_coverage'] = False
            w['noaa_enc_scale'] = ''
        w['noaa_depth_features'] = False
        w['noaa_depth_feature_count'] = 0
    print(f'  DNR waterbodies intersecting NOAA ENC coverage: {len(candidates):,}', flush=True)

    layer_cache = {}
    for scale in set(w['noaa_enc_scale'] for w in candidates):
        try:
            layer_cache[scale] = noaa_depth_layer_ids(NOAA_SERVICES[scale])
            print(f'  {scale} depth layers: {layer_cache[scale]}', flush=True)
        except Exception as e:
            print(f'  WARNING NOAA {scale} layer discovery failed: {e}', flush=True)
            layer_cache[scale] = []

    for idx, w in enumerate(candidates, 1):
        scale = w['noaa_enc_scale']
        count = 0
        for lid, lname in layer_cache.get(scale, []):
            try:
                count += arcgis_count_polygon(f'{NOAA_SERVICES[scale]}/{lid}', w['geometry'])
            except Exception as e:
                print(f'  WARNING NOAA depth count {w["name"]} {scale}/{lid}: {e}', flush=True)
        w['noaa_depth_feature_count'] = count
        w['noaa_depth_features'] = count > 0
        if idx % 20 == 0 or idx == len(candidates):
            print(f'  NOAA depth verification {idx}/{len(candidates)}', flush=True)
    return candidates


def load_usace_depth_geometries():
    print('Loading USACE IENC depth areas intersecting Wisconsin...', flush=True)
    try:
        ids = arcgis_ids(USACE_DEPTH, geometry=WI_BBOX)
        feats = arcgis_geojson_by_ids(USACE_DEPTH, ids, 'DRVAL1,DRVAL2,Source_Date,Source_Indication,Source_Dataset', batch=250)
        geoms = [safe_shape(f) for f in feats]
        geoms = [g for g in geoms if g is not None]
        print(f'  USACE depth-area features in Wisconsin bbox: {len(geoms):,}', flush=True)
        return geoms
    except Exception as e:
        print(f'  WARNING USACE depth query failed: {e}', flush=True)
        return []


def classify_usace(waters, geoms):
    if not geoms:
        for w in waters:
            w['usace_ienc_depth'] = False
        return 0
    # Spatial index is available in Shapely 2; fall back to union if not.
    try:
        from shapely.strtree import STRtree
        tree = STRtree(geoms)
        matched = 0
        for w in waters:
            hit = False
            try:
                inds = tree.query(w['geometry'], predicate='intersects')
                hit = len(inds) > 0
            except Exception:
                hit = any(w['geometry'].intersects(g) for g in geoms)
            w['usace_ienc_depth'] = bool(hit)
            matched += int(hit)
        print(f'  DNR waterbodies intersecting USACE depth areas: {matched:,}', flush=True)
        return matched
    except Exception:
        union = unary_union(geoms)
        matched = 0
        for w in waters:
            hit = w['geometry'].intersects(union)
            w['usace_ienc_depth'] = bool(hit)
            matched += int(hit)
        return matched


def finish_classification(waters, maps):
    for w in waters:
        hist = maps.get(w['wbic']) if w['wbic'] else None
        w['dnr_historical_map'] = bool(hist)
        w['dnr_county'] = hist.get('county', '') if hist else ''
        w['dnr_map_area_acres'] = hist.get('area_acres') if hist else None
        w['dnr_max_depth_ft'] = hist.get('max_depth_ft') if hist else None
        if w.get('noaa_depth_features'):
            w['best_free_class'] = 'A_OFFICIAL_VECTOR'
            w['best_free_source'] = 'NOAA ENC'
        elif w.get('usace_ienc_depth'):
            w['best_free_class'] = 'A_OFFICIAL_VECTOR'
            w['best_free_source'] = 'USACE IENC'
        elif hist:
            w['best_free_class'] = 'D_HISTORICAL_REFERENCE'
            w['best_free_source'] = 'Wisconsin DNR historical map'
        else:
            w['best_free_class'] = 'NONE_IN_CORE_CENSUS'
            w['best_free_source'] = ''


def write_outputs(waters, hydro_feature_count, maps_meta):
    waters = sorted(waters, key=lambda x: (x['name'].lower(), x['wbic'] or 999999999))
    fields = [
        'key', 'wbic', 'name', 'hydrotype', 'centroid_lat', 'centroid_lon', 'polygon_parts',
        'dnr_historical_map', 'dnr_county', 'dnr_map_area_acres', 'dnr_max_depth_ft',
        'noaa_enc_coverage', 'noaa_enc_scale', 'noaa_depth_features', 'noaa_depth_feature_count',
        'usace_ienc_depth', 'best_free_class', 'best_free_source'
    ]
    with (OUT / 'wisconsin_depth_census_core.csv').open('w', newline='', encoding='utf-8') as f:
        wri = csv.DictWriter(f, fields)
        wri.writeheader()
        for w in waters:
            wri.writerow({k: w.get(k, '') for k in fields})

    total = len(waters)
    with_wbic = sum(bool(w['wbic']) for w in waters)
    hist = sum(bool(w['dnr_historical_map']) for w in waters)
    noaa_cov = sum(bool(w['noaa_enc_coverage']) for w in waters)
    noaa_depth = sum(bool(w['noaa_depth_features']) for w in waters)
    usace = sum(bool(w['usace_ienc_depth']) for w in waters)
    official = sum(w['best_free_class'] == 'A_OFFICIAL_VECTOR' for w in waters)
    historical_only = sum(w['best_free_class'] == 'D_HISTORICAL_REFERENCE' for w in waters)
    none = sum(w['best_free_class'] == 'NONE_IN_CORE_CENSUS' for w in waters)
    counts = {
        'dnr_hydro_polygon_features': hydro_feature_count,
        'unique_dnr_waterbody_groups': total,
        'unique_with_wbic': with_wbic,
        'groups_without_wbic': total - with_wbic,
        'dnr_historical_map_index_pages_read': maps_meta['pages'],
        'dnr_historical_map_raw_rows': maps_meta['raw_rows'],
        'waterbodies_with_dnr_historical_map': hist,
        'waterbodies_intersecting_noaa_enc_coverage': noaa_cov,
        'waterbodies_with_verified_noaa_depth_features': noaa_depth,
        'waterbodies_intersecting_usace_ienc_depth': usace,
        'waterbodies_with_official_vector_depth_core': official,
        'waterbodies_historical_reference_only_core': historical_only,
        'waterbodies_without_depth_source_in_core_census': none,
    }
    (OUT / 'counts.json').write_text(json.dumps(counts, indent=2), encoding='utf-8')

    examples_official = [w for w in waters if w['best_free_class'] == 'A_OFFICIAL_VECTOR'][:20]
    lines = [
        '# Wisconsin Depth Coverage Census — Core Pass', '',
        'This is the first automated statewide pass. It currently includes Wisconsin DNR hydrography, the DNR historical lake-map index, NOAA ENC coverage/depth features, and USACE IENC depth areas. It does **not yet** include USGS/ScienceBase project surveys, NCEI hydrographic archive discovery, university/local datasets, or LakeNav community sonar.', '',
        '## Counts', '',
        '| Metric | Count |', '|---|---:|',
    ]
    labels = {
        'dnr_hydro_polygon_features': 'DNR lake/pond/reservoir polygon features',
        'unique_dnr_waterbody_groups': 'Unique DNR waterbody groups (WBIC-grouped; no-WBIC polygons separate)',
        'unique_with_wbic': 'Unique groups with WBIC',
        'groups_without_wbic': 'Groups without WBIC',
        'waterbodies_with_dnr_historical_map': 'Waterbodies matched to DNR historical map index',
        'waterbodies_intersecting_noaa_enc_coverage': 'Waterbodies intersecting NOAA ENC coverage',
        'waterbodies_with_verified_noaa_depth_features': 'Waterbodies with NOAA depth objects intersecting polygon',
        'waterbodies_intersecting_usace_ienc_depth': 'Waterbodies intersecting USACE IENC depth areas',
        'waterbodies_with_official_vector_depth_core': 'Official vector depth available in this core pass',
        'waterbodies_historical_reference_only_core': 'Historical-reference only in this core pass',
        'waterbodies_without_depth_source_in_core_census': 'No depth source found yet in this core pass',
    }
    for k, label in labels.items():
        lines.append(f'| {label} | {counts[k]:,} |')
    lines += ['', '## Interpretation', '',
        '- `A_OFFICIAL_VECTOR` means this pass found a NOAA ENC depth object or USACE IENC depth area intersecting the DNR waterbody polygon.',
        '- `D_HISTORICAL_REFERENCE` means DNR has a mapped historical bathymetry/reference entry, but the core pass did not find official vector depth.',
        '- `NONE_IN_CORE_CENSUS` does **not** mean no depth data exists anywhere. These are the lakes the next census layers (USGS/NCEI/university/local/sonar) must investigate.',
        '- NOAA ENC service pages themselves state that ENC Direct web services are not intended as the navigation display. LakeNav would need to ingest and preserve source/datum/quality metadata rather than treating the web visualization as a certified navigation product.', '',
        '## Sample official-vector matches', '',
    ]
    for w in examples_official:
        lines.append(f'- {w["name"]} — WBIC {w["wbic"] or "none"} — {w["best_free_source"]}')
    (OUT / 'SUMMARY.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps(counts, indent=2), flush=True)
    print('\n'.join(lines[:50]), flush=True)


def main():
    waters, hydro_feature_count = load_dnr_waterbodies()
    hist, maps_meta = scrape_dnr_historical_maps()
    coverage = load_noaa_coverage()
    classify_noaa(waters, coverage)
    usace_geoms = load_usace_depth_geometries()
    classify_usace(waters, usace_geoms)
    finish_classification(waters, hist)
    write_outputs(waters, hydro_feature_count, maps_meta)


if __name__ == '__main__':
    main()
