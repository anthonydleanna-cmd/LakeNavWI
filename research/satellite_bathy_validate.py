#!/usr/bin/env python3
import json
import math
import os
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.windows import from_bounds
import requests
from sklearn.linear_model import LinearRegression, HuberRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import GroupKFold

OUT = Path(os.environ.get("SAT_BATHY_OUT", "research_validation"))
OUT.mkdir(parents=True, exist_ok=True)
NTL_ROOT = Path(os.environ.get("NTL_REFERENCE_ROOT", "ntl-reference"))
STAC = "https://earth-search.aws.element84.com/v1/search"

LAKE_NAMES = {
    "AL": "Allequash Lake",
    "BM": "Big Muskellunge Lake",
    "CR": "Crystal Lake",
    "SP": "Sparkling Lake",
    "TR": "Trout Lake",
}

session = requests.Session()
session.headers.update({"User-Agent": "LakeNavWI satellite-bathymetry-validation/0.1"})


def stac_scene(bounds4326):
    payload = {
        "collections": ["sentinel-2-c1-l2a"],
        "bbox": list(bounds4326),
        "datetime": "2024-05-01T00:00:00Z/2025-09-15T23:59:59Z",
        "limit": 100,
        "query": {"eo:cloud_cover": {"lt": 8}},
        "sortby": [{"field": "properties.datetime", "direction": "desc"}],
    }
    r = session.post(STAC, json=payload, timeout=90)
    r.raise_for_status()
    feats = r.json().get("features", [])
    if not feats:
        raise RuntimeError("No Sentinel-2 scenes")
    # Prefer July-September and lowest cloud cover. Tile cloud is only a coarse filter;
    # water masking below rejects contaminated pixels.
    def rank(f):
        dt = f.get("properties", {}).get("datetime", "")
        month = int(dt[5:7]) if len(dt) >= 7 else 1
        summer_penalty = 0 if 7 <= month <= 9 else 1
        cloud = float(f.get("properties", {}).get("eo:cloud_cover", 100))
        return (summer_penalty, cloud, -int(dt[:10].replace("-", "") or 0))
    f = sorted(feats, key=rank)[0]
    a = f["assets"]
    def href(name): return a[name]["href"]
    return {
        "id": f["id"],
        "datetime": f["properties"].get("datetime"),
        "cloud": f["properties"].get("eo:cloud_cover"),
        "blue": href("blue"), "green": href("green"),
        "red": href("red"), "nir": href("nir"),
    }


def densify_lines(gdf, spacing=20.0):
    rows = []
    for idx, row in gdf.iterrows():
        geom = row.geometry
        if geom is None or geom.is_empty:
            continue
        geoms = list(geom.geoms) if geom.geom_type == "MultiLineString" else [geom]
        for part_idx, line in enumerate(geoms):
            if line.length <= 0:
                continue
            n = max(2, int(line.length // spacing) + 1)
            for j, dist in enumerate(np.linspace(0, line.length, n)):
                p = line.interpolate(float(dist))
                rows.append({
                    "lake_id": row.LakeID,
                    "depth_ft": float(row.Depth_ft),
                    "contour_id": f"{row.LakeID}-{idx}-{part_idx}",
                    "x": p.x, "y": p.y,
                })
    return pd.DataFrame(rows)


def crop_band(url, bounds_target, target_crs):
    env = rasterio.Env(
        GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
        CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif,.TIF",
        GDAL_HTTP_MULTIPLEX="YES",
        GDAL_HTTP_MERGE_CONSECUTIVE_RANGES="YES",
        VSI_CACHE="TRUE",
        VSI_CACHE_SIZE="50000000",
    )
    env.__enter__()
    ds = rasterio.open(url)
    # bounds_target arrive in target_crs; transform to source CRS when needed.
    from rasterio.warp import transform_bounds
    b = transform_bounds(target_crs, ds.crs, *bounds_target, densify_pts=21)
    w = from_bounds(*b, transform=ds.transform).round_offsets().round_lengths()
    w = w.intersection(rasterio.windows.Window(0, 0, ds.width, ds.height))
    arr = ds.read(1, window=w, masked=True).astype("float32")
    transform = ds.window_transform(w)
    return env, ds, arr, transform


def sample_array(arr, transform, xs, ys, src_crs, point_crs):
    from pyproj import Transformer
    tr = Transformer.from_crs(point_crs, src_crs, always_xy=True)
    xx, yy = tr.transform(xs, ys)
    inv = ~transform
    cols, rows = inv * (np.asarray(xx), np.asarray(yy))
    rows = np.floor(rows).astype(int)
    cols = np.floor(cols).astype(int)
    valid = (rows >= 0) & (cols >= 0) & (rows < arr.shape[0]) & (cols < arr.shape[1])
    out = np.full(len(xs), np.nan, dtype=float)
    ii = np.where(valid)[0]
    vals = arr[rows[ii], cols[ii]]
    out[ii] = np.asarray(vals.filled(np.nan) if hasattr(vals, "filled") else vals, dtype=float)
    return out


def metrics(y, p):
    return {
        "n": int(len(y)),
        "mae_ft": float(mean_absolute_error(y, p)),
        "rmse_ft": float(mean_squared_error(y, p) ** 0.5),
        "r2": float(r2_score(y, p)),
        "within_5ft_pct": float(np.mean(np.abs(y-p) <= 5) * 100),
        "within_10ft_pct": float(np.mean(np.abs(y-p) <= 10) * 100),
    }


def fit_eval(df, feature_cols, group_col="contour_id"):
    X = df[feature_cols].to_numpy(float)
    y = df["depth_ft"].to_numpy(float)
    groups = df[group_col].to_numpy()
    unique_groups = np.unique(groups)
    n_splits = min(5, len(unique_groups))
    pred = np.full(len(df), np.nan)
    if n_splits >= 2:
        gkf = GroupKFold(n_splits=n_splits)
        for train, test in gkf.split(X, y, groups):
            model = HuberRegressor(epsilon=1.35, max_iter=500)
            model.fit(X[train], y[train])
            pred[test] = model.predict(X[test])
    else:
        model = LinearRegression().fit(X, y)
        pred = model.predict(X)
    return pred, metrics(y, pred)


def main():
    shp = NTL_ROOT / "data-raw/ntl153_v3_0/nhld_bathymetry.shp"
    gdf = gpd.read_file(shp)
    gdf = gdf[gdf.LakeID.isin(LAKE_NAMES)].copy()
    gdf = gdf[gdf.Depth_ft > 0].copy()
    point_crs = gdf.crs

    results = {"scene": {}, "per_lake": {}, "pooled": {}}
    samples_all = []

    for lake_id, lake_name in LAKE_NAMES.items():
        lg = gdf[gdf.LakeID == lake_id].copy()
        if lg.empty:
            continue
        lg4326 = lg.to_crs(4326)
        bounds = lg4326.total_bounds
        scene = stac_scene(bounds)
        results["scene"][lake_id] = scene
        print(f"{lake_name}: {scene['id']} cloud={scene['cloud']}", flush=True)

        pts = densify_lines(lg, spacing=20.0)
        # Read a compact crop from each 10 m band.
        pad = 150.0
        b = lg.total_bounds
        target_bounds = [b[0]-pad, b[1]-pad, b[2]+pad, b[3]+pad]
        crops = {}
        handles = []
        try:
            for band in ["blue", "green", "red", "nir"]:
                env, ds, arr, tx = crop_band(scene[band], target_bounds, point_crs)
                handles.append((env, ds))
                crops[band] = (arr, tx, ds.crs)
            for band, (arr, tx, crs) in crops.items():
                pts[band] = sample_array(arr, tx, pts.x.values, pts.y.values, crs, point_crs)
        finally:
            for env, ds in handles:
                try: ds.close()
                except Exception: pass
                try: env.__exit__(None, None, None)
                except Exception: pass

        # Sentinel L2A reflectance scale is normally 0..10000. Remove invalid/land/cloudy pixels.
        for band in ["blue", "green", "red", "nir"]:
            pts[band] = pts[band] / 10000.0
        pts = pts.replace([np.inf, -np.inf], np.nan).dropna()
        pts = pts[(pts.blue > 0.001) & (pts.green > 0.001) & (pts.red > 0.001)]
        # Water mask: NIR is low for open water. Allow some headroom for glint / shallow bottoms.
        pts = pts[(pts.nir >= 0) & (pts.nir < 0.12)]
        if len(pts) < 25:
            results["per_lake"][lake_id] = {"lake": lake_name, "error": "Too few valid water samples", "n": int(len(pts))}
            continue

        eps = 1e-4
        pts["log_bg"] = np.log((pts.blue + eps) / (pts.green + eps))
        pts["log_gr"] = np.log((pts.green + eps) / (pts.red + eps))
        pts["blue_green_stumpf"] = np.log(1000*(pts.blue+eps)) / np.log(1000*(pts.green+eps))
        pts["ndwi"] = (pts.green - pts.nir) / (pts.green + pts.nir + eps)
        pts["lake_id"] = lake_id

        models = {}
        for name, cols in {
            "blue_green_log_ratio": ["log_bg"],
            "stumpf_blue_green": ["blue_green_stumpf"],
            "multiband_optical": ["log_bg", "log_gr", "red", "nir", "ndwi"],
        }.items():
            pred, m = fit_eval(pts, cols)
            pts[f"pred_{name}"] = pred
            models[name] = m
        results["per_lake"][lake_id] = {
            "lake": lake_name,
            "valid_samples": int(len(pts)),
            "depth_min_ft": float(pts.depth_ft.min()),
            "depth_max_ft": float(pts.depth_ft.max()),
            "models": models,
        }
        samples_all.append(pts)

    if samples_all:
        all_df = pd.concat(samples_all, ignore_index=True)
        # Cross-lake test: train on four lakes, predict the held-out lake. This is the crucial
        # transferability test for unmapped lakes, because per-lake calibration isn't available there.
        feature_sets = {
            "blue_green_log_ratio": ["log_bg"],
            "stumpf_blue_green": ["blue_green_stumpf"],
            "multiband_optical": ["log_bg", "log_gr", "red", "nir", "ndwi"],
        }
        for model_name, cols in feature_sets.items():
            preds = np.full(len(all_df), np.nan)
            per_holdout = {}
            for lake_id in sorted(all_df.lake_id.unique()):
                train = all_df.lake_id != lake_id
                test = ~train
                model = HuberRegressor(epsilon=1.35, max_iter=500)
                model.fit(all_df.loc[train, cols].to_numpy(), all_df.loc[train, "depth_ft"].to_numpy())
                pp = model.predict(all_df.loc[test, cols].to_numpy())
                preds[np.where(test)[0]] = pp
                per_holdout[lake_id] = metrics(all_df.loc[test, "depth_ft"].to_numpy(), pp)
            results["pooled"][model_name] = {
                "leave_one_lake_out": metrics(all_df.depth_ft.to_numpy(), preds),
                "per_holdout_lake": per_holdout,
            }
        all_df.to_csv(OUT / "samples_and_predictions.csv", index=False)

    (OUT / "validation.json").write_text(json.dumps(results, indent=2))

    lines = ["# LakeNav WI Sentinel-2 bathymetry validation", "",
             "Ground truth: UW-Madison NTL digital bathymetric contour vectors. Satellite: Sentinel-2 L2A 10 m reflectance.", ""]
    lines.append("## Per-lake cross-validation")
    lines.append("| Lake | Samples | Depth range | Simple B/G RMSE | Multiband RMSE | Multiband within 5 ft |")
    lines.append("|---|---:|---:|---:|---:|---:|")
    for lid, r in results["per_lake"].items():
        if "models" not in r:
            lines.append(f"| {r['lake']} | {r.get('n',0)} | — | — | — | — |")
            continue
        a=r['models']['blue_green_log_ratio']; m=r['models']['multiband_optical']
        lines.append(f"| {r['lake']} | {r['valid_samples']} | {r['depth_min_ft']:.0f}-{r['depth_max_ft']:.0f} ft | {a['rmse_ft']:.1f} ft | {m['rmse_ft']:.1f} ft | {m['within_5ft_pct']:.0f}% |")
    lines += ["", "## Leave-one-lake-out transfer test", "",
              "This is the more important test for LakeNav: the held-out lake contributes no calibration depths.", "",
              "| Model | RMSE | MAE | R² | Within 5 ft | Within 10 ft |",
              "|---|---:|---:|---:|---:|---:|"]
    for name, r in results["pooled"].items():
        m=r['leave_one_lake_out']
        lines.append(f"| {name} | {m['rmse_ft']:.1f} ft | {m['mae_ft']:.1f} ft | {m['r2']:.2f} | {m['within_5ft_pct']:.0f}% | {m['within_10ft_pct']:.0f}% |")
    (OUT / "README.md").write_text("\n".join(lines)+"\n")
    print((OUT / "README.md").read_text())

if __name__ == "__main__":
    main()
