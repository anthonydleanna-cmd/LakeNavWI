#!/usr/bin/env python3
import json
import os
from pathlib import Path
from urllib.parse import urlencode

import geopandas as gpd
import requests

OUT = Path(os.environ.get("SAT_BATHY_OUT", "research_output"))
OUT.mkdir(parents=True, exist_ok=True)

LAKES = {
    "Crystal Lake": (46.00275, -89.612233),
    "Big Muskellunge Lake": (46.021067, -89.611783),
    "Sparkling Lake": (46.007733, -89.701183),
    "Allequash Lake": (46.038317, -89.620617),
    "Trout Lake": (46.029267, -89.665017),
    "Lake Mendota": (43.09885, -89.40545),
    "Lake Monona": (43.06337, -89.36086),
    "Lake Wingra": (43.05258, -89.42499),
}

OA_BASE = "https://openaltimetry.earthdatacloud.nasa.gov/data"
STAC = "https://earth-search.aws.element84.com/v1/search"

session = requests.Session()
session.headers.update({"User-Agent": "LakeNavWI satellite-bathymetry-research/0.1"})


def bbox(lat, lon, pad=0.035):
    return [lon - pad, lat - pad, lon + pad, lat + pad]


def safe_json(resp):
    try:
        return resp.json()
    except Exception:
        return {"raw": resp.text[:4000]}


def get_tracks(bounds):
    params = {
        "minx": bounds[0], "miny": bounds[1],
        "maxx": bounds[2], "maxy": bounds[3],
        "outputFormat": "json",
    }
    url = f"{OA_BASE}/api/icesat2/getTracks"
    r = session.get(url, params=params, timeout=90)
    return {
        "request_url": r.url,
        "status": r.status_code,
        "data": safe_json(r),
    }


def stac_search(bounds):
    payload = {
        "collections": ["sentinel-2-c1-l2a"],
        "bbox": bounds,
        "datetime": "2022-05-01T00:00:00Z/2025-09-15T23:59:59Z",
        "limit": 40,
        "query": {"eo:cloud_cover": {"lt": 20}},
        "sortby": [{"field": "properties.datetime", "direction": "desc"}],
    }
    r = session.post(STAC, json=payload, timeout=90)
    data = safe_json(r)
    scenes = []
    for f in data.get("features", []) if isinstance(data, dict) else []:
        props = f.get("properties", {})
        assets = f.get("assets", {})
        def href(*names):
            for n in names:
                if n in assets:
                    return assets[n].get("href")
            return None
        scenes.append({
            "id": f.get("id"),
            "datetime": props.get("datetime"),
            "cloud_cover": props.get("eo:cloud_cover"),
            "mgrs_tile": props.get("mgrs:tile") or props.get("s2:mgrs_tile"),
            "blue": href("blue", "B02"),
            "green": href("green", "B03"),
            "red": href("red", "B04"),
            "nir": href("nir", "B08"),
            "scl": href("scl", "SCL"),
            "visual": href("visual"),
        })
    return {"status": r.status_code, "scene_count": len(scenes), "scenes": scenes}


def inspect_bathymetry():
    shp = Path("/tmp/NTLlakeloads/data-raw/ntl153_v3_0/nhld_bathymetry.shp")
    out = {"exists": shp.exists()}
    if not shp.exists():
        return out
    gdf = gpd.read_file(shp)
    out["crs"] = str(gdf.crs)
    out["columns"] = list(gdf.columns)
    out["feature_count"] = len(gdf)
    for c in ["LakeID", "LAKEID", "Lake", "lake", "Depth_ft", "DEPTH_FT", "Depth_m"]:
        if c in gdf.columns:
            vals = gdf[c].dropna().tolist()
            out[f"{c}_sample"] = vals[:50]
            if c.lower().startswith("lake"):
                out[f"{c}_unique"] = sorted({str(x) for x in vals})
            if "depth" in c.lower():
                nums = [float(x) for x in vals]
                out[f"{c}_min"] = min(nums) if nums else None
                out[f"{c}_max"] = max(nums) if nums else None
    out["bounds"] = [float(x) for x in gdf.total_bounds]
    sample = gdf.drop(columns="geometry").head(20)
    out["records_sample"] = json.loads(sample.to_json(orient="records"))
    return out


def main():
    result = {
        "purpose": "LakeNav WI satellite-derived bathymetry feasibility discovery",
        "openaltimetry": {},
        "sentinel2": {},
        "ntl_bathymetry": inspect_bathymetry(),
    }
    for name, (lat, lon) in LAKES.items():
        b = bbox(lat, lon)
        print(f"Checking {name} {b}", flush=True)
        try:
            result["openaltimetry"][name] = get_tracks(b)
        except Exception as e:
            result["openaltimetry"][name] = {"error": repr(e)}
        try:
            result["sentinel2"][name] = stac_search(b)
        except Exception as e:
            result["sentinel2"][name] = {"error": repr(e)}

    (OUT / "discovery.json").write_text(json.dumps(result, indent=2))

    lines = ["# LakeNav WI satellite bathymetry discovery", ""]
    b = result["ntl_bathymetry"]
    lines.append(f"NTL digital bathymetry: {b.get('feature_count', 'n/a')} features, CRS `{b.get('crs', 'n/a')}`")
    lines.append("")
    lines.append("| Lake | ICESat-2 discovery | Sentinel-2 scenes (<20% tile cloud) |")
    lines.append("|---|---:|---:|")
    for name in LAKES:
        oa = result["openaltimetry"].get(name, {})
        od = oa.get("data")
        if isinstance(od, list):
            ntracks = len(od)
        elif isinstance(od, dict):
            if isinstance(od.get("tracks"), list): ntracks = len(od["tracks"])
            elif isinstance(od.get("features"), list): ntracks = len(od["features"])
            else: ntracks = "response"
        else:
            ntracks = "error"
        ns = result["sentinel2"].get(name, {}).get("scene_count", "error")
        lines.append(f"| {name} | {ntracks} | {ns} |")
    (OUT / "README.md").write_text("\n".join(lines) + "\n")
    print((OUT / "README.md").read_text())

if __name__ == "__main__":
    main()
