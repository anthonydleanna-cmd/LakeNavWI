# LakeNav WI v0.85 Navigation Audit

Date: 2026-09-17
Protected baseline: `checkpoint-v0.85-good-water-baseline`
Baseline commit: `31115bfb0f395bd8e6a94b388e4cb9262f859d6b`

## Field evidence

First real water test:
- Outbound track recording followed the traveled line well.
- Reverse-track navigation could lose follow/position and require recentering.
- Reverse-track navigation originally behaved like waypoint-to-waypoint guidance instead of joining the recorded line at the user's actual location.
- v0.85 changed follow release to require a real chart drag and changed Navigate Back to follow the recorded track geometry with nearest-line join and monotonic progress.

The successful outbound track is treated as a protected behavior. Navigation hardening should avoid wholesale changes to track recording unless a test proves a defect.

## Reference behavior

### Garmin marine chartplotters
Garmin GPSMAP documents recorded-track navigation as Follow Track -> Forward/Backward, then follow the colored track line. Garmin chart settings also implement Look Ahead and an Auto vessel-orientation mode that uses GPS COG at higher speed and magnetic heading at lower speed.

References:
- https://www8.garmin.com/manuals/webhelp/GUID-3E67C80C-0812-4EEC-BC60-699751B9CF6F/EN-US/GUID-7AA52DD2-ADC7-45B2-ACC7-4EB29CB17B93.html
- https://www8.garmin.com/manuals/webhelp/GUID-413FE004-9D7D-474E-8423-3B787BC4A5BF/EN-US/GUID-79808A48-8C14-4044-BCAA-3E428040B2F5.html

### Navionics Boating
Navionics instructs users to display a saved track and follow the saved track line in reverse using GPS.

Reference:
- https://support.garmin.com/en-GB/navionics/faq/RGpmob0Hvz0PKyde1WhdS9/

### Raymarine
Raymarine documents Course Up, Relative Motion, forward boat offsets, and cross-track error as core chart-navigation concepts. Relative Motion fixes the vessel onscreen while the chart moves under it; boat-position offset creates more view ahead.

References:
- https://docs.raymarine.com/81426/en-US/latest/GlossaryOfNavigationTerms-A1002356.html
- https://docs.raymarine.com/81406/en-US/latest/ViewMotionSettingsMenu-5E1C9B16.html
- https://docs.raymarine.com/81406/en-US/latest/RestartingCrossTrackError-F2AE9E37.html

### Android location
Android identifies `GPS_PROVIDER` as GNSS and `NETWORK_PROVIDER` as cell/Wi-Fi location. Android also explicitly recommends elapsed realtime for ordering/comparing fixes because `Location.getTime()` is not monotonic.

References:
- https://developer.android.com/reference/android/location/LocationManager
- https://developer.android.com/reference/android/location/Location

## Architecture audit

### 1. Recorded-track geometry: GOOD
v0.85 follows the actual recorded geometry rather than temporary guide waypoints. It can join the line away from an endpoint, computes remaining route distance, and prevents normal progress from moving backward.

This is directionally consistent with Garmin Follow Track Backward and Navionics reverse-track behavior.

### 2. Follow/recenter state: GOOD after v0.85
Before v0.85, incidental map contact could release follow. v0.85 releases follow only after Leaflet confirms `dragstart`.

The protected Course-Up model is Relative Motion style:
- vessel pinned near lower center,
- chart moves/rotates beneath the vessel,
- look-ahead space is ahead of the vessel.

### 3. Native fix ingestion: HIGH PRIORITY
The exact materialized v0.85 Android source requests both:
- GPS provider: 1000 ms / 1 m
- Network provider: 3000 ms / 3 m

Both providers call the same JavaScript callback and provider identity is not passed. Therefore a network fix can compete with a GNSS fix without the JS navigation engine knowing which source produced it.

v0.85 also passes `Location.getTime()` as the timing basis. Android states this clock is not monotonic and should not be used to order/compare locations from different providers. `getElapsedRealtimeNanos()` should be used for ordering and delta timing.

Recommended:
- send provider identity,
- send elapsed-realtime timestamp in addition to wall-clock time,
- reject out-of-order fixes,
- prefer fresh GNSS during navigation,
- use network only as a clearly identified fallback when GNSS is stale.

### 4. Heading pipeline: HIGH PRIORITY
v0.85 smooths movement heading, then smooths the displayed heading, then smooths map rotation again.

Current movement display smoothing:
- deadband ~0.45 degrees,
- max step 7 degrees,
- alpha 0.18.

Current map rotation then applies another alpha 0.18.

A deterministic 90-degree step simulation at the normal visual update cadence shows approximately:
- <=45 degree chart error: 7.36 s
- <=20 degree chart error: 11.00 s
- <=10 degree chart error: 12.45 s
- <=5 degree chart error: 13.36 s

This is a strong explanation for the field report that the arrow/chart felt laggy.

Recommended:
- keep a single bounded heading filter,
- remove the second logical map-rotation filter,
- let the existing short CSS transform transition provide visual smoothness,
- target <=10 degree visual error within about 2 seconds during an ordinary powered-boat turn.

### 5. Course-Up position filter: KEEP / TUNE ONLY IF TESTS FAIL
The current along-track gain is roughly 0.82 at useful speed. Simulation estimates steady display lag of:
- ~1.6 ft at 5 mph
- ~3.2 ft at 10 mph
- ~6.4 ft at 20 mph
- ~9.7 ft at 30 mph

This is not large enough to explain the primary field complaint and this filtering likely contributed to the clean outbound track. Do not remove it casually.

### 6. Camera follow: HIGH PRIORITY
v0.85 camera updates are throttled to ~620 ms and each pan animates for ~0.78 s. Animations can overlap the next navigation update and visually trail a correct fix.

Recommended:
- shorten follow interval to about 300-400 ms,
- shorten camera transition to about 250-350 ms,
- keep the vessel screen anchor fixed,
- never let a camera animation own route progress or heading state.

### 7. GPS dropout continuity: MEDIUM/HIGH PRIORITY
v0.85 can project an estimated position using recent speed/course for up to 22 seconds after fix degradation/loss.

At 20 mph, 22 seconds is nearly 200 m / 650 ft of possible dead-reckoned travel. A phone has no water-speed sensor or inertial navigation solution robust enough to treat that as a trusted position.

Recommended:
- reduce projected continuity window,
- explicitly mark estimated position,
- freeze rather than continue projecting after the short confidence window,
- reacquire a high-quality GNSS fix quickly without a long smoothing tail.

### 8. Reverse-track self-intersections / loops: MEDIUM PRIORITY
v0.85 has heading and prior-progress penalties to disambiguate track segments. This is good, but the search still considers the full track each update.

Recommended after join:
- constrain candidate progress to a physically plausible forward window around prior progress,
- retain unrestricted nearest-line selection before initial join,
- add deterministic figure-eight/hairpin tests.

### 9. Course source selection: GOOD CONCEPT
LakeNav blends GPS COG/movement at useful speed and falls back toward true compass at low speed. This matches the concept documented by Garmin's Auto vessel orientation.

The problem is latency after selecting the source, not the source-selection concept itself.

### 10. XTE guidance: GOOD CONCEPT
LakeNav computes cross-track distance, side, correction direction, warning hysteresis, and a guide line. This is consistent with normal marine XTE concepts. Do not automatically recalculate a route merely because XTE exists; user intent matters.

## Proposed v0.86 scope

Production changes should be isolated to navigation responsiveness and fix quality:
1. Provider-aware native location callback.
2. Elapsed-realtime ordering and delta timing.
3. Fresh GNSS priority; network fallback only when GNSS is stale.
4. Remove double heading smoothing.
5. Faster, shorter camera-follow transitions.
6. Shorter and more conservative estimated-position continuity.
7. Stronger joined-track progress-window protection at loops/intersections.
8. Navigation diagnostics for provider, fix age, raw/accepted fix, and estimate state.

Do not redesign:
- saved track format,
- track-history persistence,
- outbound track filtering,
- lake discovery,
- overlays,
- map/depth behavior.

## Proposed acceptance tests

### GPS acquisition
- no older fix can replace a newer accepted fix,
- a materially worse network fix cannot replace a fresh GNSS fix,
- provider and age are observable in diagnostics.

### Course-Up responsiveness
- ordinary 90-degree powered-boat turn reaches <=10 degrees display error in <=2 s,
- no single bad fix can flip the course by 180 degrees,
- vessel remains pinned onscreen during active follow.

### Camera
- taps do not release follow,
- only real chart drag releases follow,
- Recenter restores follow in one action,
- no long camera animation overlaps successive GPS updates.

### Reverse track
- start at original end and follow backward,
- join at 25%, 50%, and 75% of track,
- leave/rejoin line,
- hairpin,
- figure-eight/self-intersection,
- no spontaneous backward progress,
- no jump to a distant future branch.

### GPS degradation
- 2 s dropout: smooth continuity,
- 5 s dropout: clear estimate state,
- prolonged dropout: stop projecting and show loss/degraded state,
- recovery: return to GNSS promptly without a long lag tail.

### Track recording regression
- recorded outbound path remains as clean as v0.85 baseline,
- track history still saves and survives normal app restart/upgrade.
