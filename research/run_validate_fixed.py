#!/usr/bin/env python3
import numpy as np
import pandas as pd
import satellite_bathy_validate as s


def _line_parts(geom):
    if geom is None or geom.is_empty:
        return []
    t = geom.geom_type
    if t == "LineString":
        return [geom]
    if t == "MultiLineString":
        return list(geom.geoms)
    if t == "Polygon":
        return [geom.exterior, *list(geom.interiors)]
    if t == "MultiPolygon":
        out = []
        for poly in geom.geoms:
            out.append(poly.exterior)
            out.extend(list(poly.interiors))
        return out
    if t == "GeometryCollection":
        out = []
        for g in geom.geoms:
            out.extend(_line_parts(g))
        return out
    return []


def densify_any(gdf, spacing=20.0):
    rows = []
    for idx, row in gdf.iterrows():
        for part_idx, line in enumerate(_line_parts(row.geometry)):
            if line.length <= 0:
                continue
            n = max(2, int(line.length // spacing) + 1)
            for dist in np.linspace(0, line.length, n):
                p = line.interpolate(float(dist))
                rows.append({
                    "lake_id": row.LakeID,
                    "depth_ft": float(row.Depth_ft),
                    "contour_id": f"{row.LakeID}-{idx}-{part_idx}",
                    "x": p.x,
                    "y": p.y,
                })
    return pd.DataFrame(rows)


s.densify_lines = densify_any
s.main()
