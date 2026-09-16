# LakeNav WI Depth Data Research

Status: research only. This branch does not change the production app.

## Goal

Find the broadest possible set of accurate water-depth data for Wisconsin while spending $0 first. Only after the free/open stack is exhausted should LakeNav consider paid chart licenses or purchased datasets.

The core rule for this project is simple: LakeNav should never turn a weak proxy into a precise depth claim. A maximum-depth number, a historic paper map, an optical satellite signal, or a modeled basin must not be presented as if it were a measured modern contour.

## Executive conclusion

There is no single free statewide API that provides modern, high-resolution measured bathymetry for every Wisconsin lake. The strongest zero-cost strategy is a source ladder keyed to Wisconsin DNR WBICs:

1. Use authoritative federal hydrographic data where it exists.
   - NOAA ENC Direct + NOAA/NCEI hydrographic surveys for Lake Michigan, Green Bay, Lake Superior and other NOAA-charted waters.
   - USACE Inland ENC/eHydro for the Mississippi River and other Corps navigation areas.
   - USGS/NCEI survey releases and topobathymetric products for specific rivers, estuaries, harbors and selected lakes.
2. Use Wisconsin DNR as the statewide identity and metadata backbone.
   - DNR hydro polygons + WBIC.
   - Maximum and mean depth where reported.
   - Official historical bathymetric-map references.
   - Do not stretch old paper maps into precise GPS navigation contours unless a separate georeferencing and accuracy test proves them suitable.
3. Ingest smaller public measured datasets opportunistically.
   - UW/North Temperate Lakes LTER.
   - University, local government, tribal, lake-association and project-specific survey releases when provenance and redistribution terms are acceptable.
4. Build LakeNav's own measured-depth layer from user-owned sonar.
   - Live NMEA/Signal K depth + GNSS.
   - Deeper raw bathymetry CSV/NMEA.
   - User-exported sonar data where the user owns the data and the format can be imported lawfully.
   - Quality-control and aggregate these observations into a LakeNav Community Depth surface.
5. Use commercial chart catalogs only for the remaining coverage gap if the business case works.
   - Garmin/Navionics Mobile SDK is the clearest documented third-party chart SDK found so far.
   - i-Boating also advertises Android/Web/embedded SDKs with HD contours; pricing is quote-only.
   - Wisconsin Lake Maps/Wiscartography sells vector GIS depth data for 160 Wisconsin lakes and may be negotiable as a bulk/commercial source.
   - C-MAP and Humminbird/LakeMaster have valuable cartography, but no public third-party bathymetry API suitable for LakeNav was identified in this pass. Any use would require an explicit business/data license.

## Source-quality classes

LakeNav should store source quality independently from visual styling.

### A — authoritative measured hydrography

Examples: NOAA hydrographic soundings/BAGs/ENC depth objects, USACE IENC/eHydro surveys, recent USGS multibeam/singlebeam survey products.

Allowed use: true depth contours/areas/soundings, subject to source date, datum and stated uncertainty.

### B — measured/georeferenced scientific or agency bathymetry

Examples: university GIS bathymetry, agency GPS soundings, lake-association sonar surveys with clear provenance.

Allowed use: true depth layer with source/date badge and QA status.

### C — LakeNav/community sonar after QA

Actual GNSS + sonar observations contributed by users. Quality depends on GPS, transducer offset, speed, water level, device, sample density and cross-track agreement.

Allowed use: measured community depth, clearly identified as community-derived. Promote confidence only after repeated independent passes agree.

### D — historical/reference bathymetry

Examples: old Wisconsin DNR scanned paper contour maps. The contours may have been created from real soundings, but scan registration, shoreline change, survey age and original positional accuracy can make them unsafe for direct GPS alignment.

Allowed use: reference map/source badge, max/mean depth metadata, research/validation. Do not silently render as modern GPS contours.

### E — modeled or remotely inferred depth

Examples: GLOBathy, basin-shape models, Sentinel-2 optical bathymetry without local calibration, sparse ICESat-2 bottom returns.

Allowed use: research, screening or qualitative overlays only. Never label as verified numeric navigation depth.

## Free/open source inventory

### 1. Wisconsin DNR — statewide backbone

**What it gives us**

- Statewide hydrography polygons and WBIC identifiers through ArcGIS REST.
- Lake name, county and area.
- Maximum depth and, for many waters, mean depth and substrate information on lake pages.
- Roughly 1,350 historical lake/river bathymetric maps available for public distribution.

**Access**

- Hydro layer: `https://dnrmaps.wi.gov/arcgis/rest/services/ER_Biotics/ER_Biotics_WGS84_Hydro/MapServer/0`
- Lake pages: `https://apps.dnr.wi.gov/lakes/lakepages/LakeDetail.aspx?wbic={WBIC}`
- Historical map index: `https://apps.dnr.wi.gov/lakes/maps/`

**LakeNav use**

This should remain the master Wisconsin waterbody identity layer. Every other source should be cross-walked to WBIC when possible.

**Limitation**

No statewide public DNR ArcGIS service containing modern vector depth contours or soundings was found. Historical PDFs are often explicitly marked historical/not for navigation.

### 2. NOAA ENC Direct to GIS — highest-value free API for Great Lakes/navigation waters

NOAA exposes Electronic Navigational Chart objects as queryable ArcGIS Feature Layers. These are not just rendered tiles; LakeNav can query vector geometry and attributes.

Useful layers include:

- Harbor soundings: `https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_harbour/MapServer/76`
  - `Z` = sounding depth.
  - `SORDAT` = source date.
  - `SORIND` = source indication.
  - `QUASOU` = quality of sounding.
  - Supports JSON and GeoJSON queries.
- Harbor depth contours: `https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_harbour/MapServer/104`
  - `VALDCO` = depth contour value.
  - Source/date and vertical-datum fields are included.
- Harbor depth areas: `https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_harbour/MapServer/227`
  - `DRVAL1` / `DRVAL2` = depth range.
  - `SOUACC` = sounding accuracy when supplied.

ENC Direct has additional scale bands such as approach/coastal/general. A production adapter should query the most detailed applicable source without creating duplicate contours across overlapping scale bands.

**LakeNav use**

Excellent for Green Bay, Lake Michigan, Lake Superior ports/coasts and any Wisconsin water covered by NOAA ENCs. Preserve vertical datum, survey/source date and quality fields instead of flattening everything to just `depth_ft`.

### 3. NOAA/NCEI hydrographic survey archive

NCEI stores the source hydrographic work behind many nautical products, including:

- BAG gridded bathymetry.
- XYZ soundings.
- Smooth sheets.
- Multibeam data.
- Survey reports and uncertainty information.

Discovery API documentation: `https://www.ngdc.noaa.gov/next-web/docs/guide/catalog.html`

The catalog supports hydrographic sounding, multibeam and trackline searches with spatial criteria. This is particularly useful when LakeNav wants more detail than generalized ENC contours.

**LakeNav use**

Create an offline preprocessing pipeline: discover surveys intersecting Wisconsin, download best available processed surfaces/soundings, normalize datums, clip, tile and host a compact LakeNav depth package.

### 4. NOAA/NCEI Great Lakes bathymetry

NOAA maintains Great Lakes bathymetric grids/contours assembled from decades of U.S. and Canadian sounding data. These products provide broad free coverage where detailed survey products are not necessary.

Source: `https://www.ncei.noaa.gov/products/great-lakes-bathymetry`

**LakeNav use**

Good regional base surface for the Great Lakes, then override with more detailed ENC/hydrographic surveys where available.

### 5. NOAA Wisconsin Lake Superior Digital Atlas

NOAA/NCCOS exposes a Wisconsin Lake Superior ArcGIS service with:

- multibeam depth,
- regional bathymetry depth,
- lakebed slope,
- backscatter,
- rugosity and other seabed layers.

Service: `https://gis.ngdc.noaa.gov/arcgis/rest/services/nccos/WisconsinLakeSuperiorDigitalAtlas/MapServer`

**LakeNav use**

High-value local enhancement for the Wisconsin Lake Superior/Apostle Islands region.

### 6. USACE Inland Electronic Navigational Charts — Mississippi River

The Corps publishes IENC data free and exposes ArcGIS services/downloads.

Example depth-area service: `https://ienccloud.us/arcgis/rest/services/IENC_Feature_Classes/DEPTH_AREA/MapServer`

Depth areas contain `DRVAL1` and `DRVAL2`. The master IENC dataset also contains depth contours, soundings and navigation objects. Data can be downloaded in S-57 and GIS formats and accessed through web services.

**LakeNav use**

Primary free depth/navigation source for Wisconsin's Mississippi River corridor.

### 7. USACE eHydro

USACE eHydro publishes recent hydrographic survey footprints and survey products for Corps-maintained waterways.

**LakeNav use**

Use as survey discovery and as a source for newer channel/harbor depth data than a generalized chart may provide. Coverage is survey/project driven, not statewide inland-lake coverage.

### 8. USGS 3DEP / 3D National Topography Model / ScienceBase

USGS offers several useful discovery systems:

- The National Map / TNM Access API for downloadable elevation/topobathymetry products.
- ScienceBase APIs and data releases.
- Project-specific multibeam, singlebeam and topobathymetric lidar releases.

Important limitation: ordinary topographic lidar usually treats lakes as water surfaces; it does not see the lake bottom. Topobathymetric green lidar can measure through water only under suitable depth/clarity/bottom conditions. USGS explicitly notes that lakes/reservoirs are generally mapped by sonar rather than topobathy lidar.

Wisconsin examples already published by USGS include bathymetric/topobathymetric datasets around the Bad River/Kakagon/Honest John Lake area, Milwaukee River Estuary and Sheboygan River.

**LakeNav use**

Automate ScienceBase/TNM searches for each Wisconsin waterbody/bbox and ingest only products that actually contain bottom bathymetry.

### 9. UW-Madison / North Temperate Lakes LTER

NTL-LTER publishes georeferenced GIS bathymetry for its study lakes, including northern Wisconsin lakes and Yahara lakes.

**LakeNav use**

Small but valuable verified/free collection. Cross-walk the datasets to WBIC and preserve original source/date/provenance. Northern Wisconsin LTER vectors may themselves originate from digitized older DNR maps, so distinguish them from modern sonar surveys.

### 10. Local government, tribal, university and lake-association surveys

Potential sources include county GIS portals, tribal natural-resource programs, university research releases, watershed projects, lake-district engineering work and lake-association sonar surveys.

**LakeNav use**

Build a discovery crawler/catalog rather than assuming a single endpoint. Require explicit redistribution permission/license and survey provenance before promotion to a true depth layer.

### 11. User-owned sonar — most important scalable free path

For thousands of inland lakes with no modern public measured bathymetry, LakeNav can create genuinely new measured coverage without paying a chart provider.

#### Deeper

Deeper supports raw bathymetry export containing latitude, longitude, depth and timestamp, and documents NMEA 0183 depth/GNSS streaming for supported integrations.

LakeNav opportunity:

- Import `Bathymetry.csv`.
- Potentially capture live NMEA over the documented network path.
- Normalize transducer offset and water level.

#### NMEA 0183 / NMEA 2000 / Signal K

A vendor-neutral pipeline is strategically better than supporting every fish-finder file format first.

Signal K is an open marine data model/protocol over WebSocket/HTTP and maps common NMEA depth observations into paths such as:

- `environment.depth.belowTransducer`
- `environment.depth.belowKeel`
- `environment.depth.belowSurface`

LakeNav opportunity:

- Connect to a Signal K server on the boat.
- Capture depth + GNSS + timestamp while Track is active.
- Store raw observations locally and optionally contribute them to Community Depth.

#### Humminbird and other NMEA-capable devices

Humminbird documents NMEA 0183 depth output such as DPT plus GNSS sentences on supported systems. This is a cleaner integration path than reverse-engineering proprietary LakeMaster/sonar-card formats.

#### Proprietary sonar logs

Lowrance, Humminbird, Garmin and others store proprietary sonar recordings. User-owned file import may eventually be useful, but LakeNav should not depend on undocumented reverse-engineering where licensing or encryption terms are unclear. Prefer documented exports, open parsers with compatible licenses, or manufacturer partnerships.

## Free sources that should NOT become verified depth contours

### Historical Wisconsin DNR paper maps

Useful as official historical references, maximum-depth evidence and potential research ground truth. Not automatically safe for GPS contour rendering because of survey age and scan/georeferencing uncertainty.

### GLOBathy

GLOBathy creates global lake bathymetry using lake polygons, maximum-depth inputs and geometric/empirical modeling. It is valuable scientifically at global scale, but it is not a measured Wisconsin contour source. Licensing descriptions also need to be verified at the original dataset level before commercial redistribution.

LakeNav classification: modeled/reference only; never verified depth.

### Satellite-derived bathymetry

LakeNav's own Wisconsin Sentinel-2 experiment showed poor cross-lake transfer for exact numeric depth. It can support qualitative shallow/shelf features in clear water, but not trustworthy numeric contours.

### ICESat-2

Potentially accurate along individual laser tracks under favorable water conditions, but coverage is sparse. In LakeNav's five-small-lake northern Wisconsin test, no useful ICESat-2 tracks crossed the test lake boxes.

### Standard lidar/DEM products

Hydro-flattened DEM water surfaces are not lake-bottom bathymetry. Do not infer bottom depth by subtracting them from a guessed basin.

## Paid/licensed sources — investigate only after free stack

### Garmin/Navionics Mobile SDK

This is currently the most clearly documented commercial path for an Android app.

Garmin states that the Navionics mobile SDK can embed:

- nautical charts,
- SonarChart HD bathymetry,
- depth contours/areas,
- tides/currents,
- chart object information,
- frequent/daily chart updates.

Developer page: `https://developer.garmin.com/marine-charts/mobile/`

SDK request: `https://www.garmin.com/en-US/forms/navionics-mobile-sdk/`

Current form requirement: the app name must be live in the app stores before requesting access. Mobile pricing is not publicly posted; Garmin says it offers different data packages/pricing structures.

Important: this is embedded licensed cartography, not permission to extract the Navionics database and convert it into LakeNav-owned vector tiles.

### i-Boating SDK

i-Boating publicly advertises Android, iOS, web and embedded Linux mapping SDKs, plus WMTS, with vector marine charts, bathymetry, depth contours/areas, obstructions and built-in HD contours. Pricing is quote-only.

Developer page: `https://i-boating.com/main/marine-maps-sdk`

This deserves a direct technical/pricing inquiry because it appears more flexible than a consumer-only chart product.

### Wisconsin Lake Maps / Wiscartography

Wiscartography sells GIS/CAD/SVG/PNG vector data for roughly 160 Wisconsin lakes. The datasets advertise shorelines, depth contours, sounding points, boat launches and source attributes, with some free samples.

Source: `https://wiscartography.com/digital-data`

LakeNav should request:

- bulk price for all Wisconsin lakes,
- commercial mobile-app redistribution rights,
- source/survey date for every lake,
- whether contours are measured/digitized/modelled,
- horizontal/vertical datum,
- update rights.

A provenance audit is mandatory before treating all 160 as equivalent quality.

### C-MAP

C-MAP has high-resolution bathymetry and Genesis/community inputs in its own products, but this research did not locate a public third-party mobile SDK/API comparable to Garmin's. The consumer data EULA restricts copying, redistribution and reverse-engineering.

LakeNav path: only through an explicit commercial/Navico data partnership. Do not scrape Genesis Social Map or consumer chart tiles.

### Humminbird LakeMaster

LakeMaster provides detailed commercial contour maps and HD-lake features on Humminbird products. No public third-party mapping SDK/API was identified in this pass.

LakeNav path: partnership/licensing inquiry only. Do not extract SD-card chart data.

### DepthScout

DepthScout is particularly interesting as a research comparator because it explicitly distinguishes survey-based and approximated contours, and reports thousands of Wisconsin waters. However, its current terms prohibit scraping, resale or redistribution without permission.

LakeNav path: possible partnership/data-source intelligence, not a free ingest API.

### Fishing Hot Spots / Mapping Specialists / similar publishers

These companies have Wisconsin lake-map catalogs, but no public developer API or broad redistribution license was identified. Treat as potential bulk-data/licensing conversations, not web-scraping targets.

## Recommended LakeNav depth architecture

Do not let the map renderer know or care which provider produced a lake. Create a normalized internal depth package with provenance.

Suggested fields per feature/package:

- `wbic`
- `source_provider`
- `source_product`
- `source_url_or_id`
- `source_date`
- `survey_date`
- `ingested_at`
- `depth_value`
- `depth_unit_original`
- `depth_m_normalized`
- `vertical_datum`
- `horizontal_crs`
- `quality_class` (A/B/C/D/E)
- `measured` boolean
- `uncertainty_m` if known
- `community_pass_count` if applicable
- `license_id`
- `display_permission`
- `navigation_status`

Source precedence for overlapping data:

1. Newer authoritative measured survey with known datum/quality.
2. Authoritative chart object based on suitable source survey.
3. High-quality georeferenced measured scientific/agency dataset.
4. LakeNav Community Depth after QA.
5. Older measured/reference data.
6. No numeric depth layer rather than a modeled guess.

## No-cost implementation plan

### Phase 1 — build a Wisconsin depth coverage census

For every DNR WBIC/lake polygon:

1. Check NOAA ENC coverage.
2. Check NOAA/NCEI hydrographic survey coverage.
3. Check USACE IENC/eHydro coverage.
4. Search USGS/TNM/ScienceBase by geometry.
5. Match known university/public GIS collections.
6. Record DNR max/mean depth and historical contour-map availability.
7. Produce a statewide table saying exactly which source is best for each lake.

This is the next research step because it converts the source list into a measurable answer such as: `X lakes have trustworthy vector depth at $0; Y have reference-only contours; Z have no measured public depth`.

### Phase 2 — build free adapters in priority order

1. NOAA ENC Direct GeoJSON adapter.
2. USACE IENC GeoJSON adapter.
3. NCEI/USGS survey discovery and preprocessing pipeline.
4. NTL-LTER/public GIS import adapter.
5. DNR metadata/reference adapter.

### Phase 3 — LakeNav Community Depth

1. Add a raw depth-observation schema.
2. Import Deeper CSV.
3. Add Signal K/NMEA live capture.
4. Store GNSS accuracy, depth reference, transducer offset and water-level correction.
5. Reject spikes and unrealistic jumps.
6. Require spatial density/cross-track agreement before contour generation.
7. Keep the original soundings so derived contours can always be regenerated.
8. Badge community contours separately from official depth.

### Phase 4 — paid gap analysis

Only after the census:

- identify the number and user importance of lakes still missing measured depth,
- request Garmin/Navionics pricing/access,
- request i-Boating SDK pricing/coverage,
- request Wiscartography bulk/mobile licensing,
- contact C-MAP/Humminbird only if their Wisconsin coverage fills material gaps,
- compare annual license cost against building community sonar coverage.

## Decision today

Do not buy depth data yet.

There is enough high-quality zero-cost material to justify building a **free-source coverage census and ingestion prototype first**. The biggest likely free coverage wins are NOAA for the Great Lakes, USACE for the Mississippi, federal/project survey repositories for selected areas, and user-owned sonar for unmapped inland lakes. The statewide DNR WBIC layer should be the index that ties all of these together.

The important paid benchmark is Garmin/Navionics, because it offers the clearest documented Android SDK with HD inland bathymetry. We should request pricing only after LakeNav is eligible and after we know exactly which Wisconsin lakes the free stack still cannot cover.
