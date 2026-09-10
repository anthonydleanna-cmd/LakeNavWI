# LakeNav WI

LakeNav WI is a personal Android lake-navigation prototype focused on Wisconsin and Great Lakes use.

## Version 0.1 features

- Uses Android GPS for current position, speed, accuracy, and course when provided by GPS.
- Saves named waypoints on the phone.
- Lets you navigate directly to a waypoint with distance and bearing.
- Records a breadcrumb GPS track and calculates trip distance.
- Imports and exports GPX waypoints/tracks.
- Uses OpenStreetMap as the base map.
- Optional NOAA electronic chart display overlay with charted depths, hazards, and aids to navigation where NOAA ENC coverage exists.
- National Weather Service hourly weather and active alert lookup at your current GPS position.
- Detects the Wisconsin DNR mapped lake/pond at your GPS position and returns its WBIC when available.
- Finds nearby Wisconsin DNR public boat access sites and plots them on the map.
- Links directly to the detected lake DNR detail page plus the statewide depth-map catalog and Lakes/AIS viewer.

## Important depth-data limitation

There is no single free public source that provides live, current bathymetric depth for every Wisconsin inland lake.

NOAA ENC chart data is useful for the Great Lakes and other federally charted navigable waters. The Wisconsin DNR publishes depth maps for many inland lakes, but not every lake, and those maps are generally survey maps rather than live depth readings.

Charted depth can differ from actual water under your boat because water levels change and surveys age. A depth sounder/sonar remains the proper source for real-time depth directly under the boat.

## Safety

This app is for situational awareness only. Do not use it as your sole means of navigation. Maintain visual lookout, obey local boating rules, and use official navigation information and depth-sounding equipment when needed.

## Build in Android Studio

1. Open the `LakeNavWI` folder in a current Android Studio release.
2. Allow Gradle sync to finish.
3. Connect an Android phone with USB debugging enabled, or use an emulator.
4. Click Run.
5. Grant location permission when prompted.

Minimum Android version: Android 8.0 (API 26).

## Build an installable APK with GitHub Actions

This repository includes `.github/workflows/build-apk.yml`.

1. Put the project in a GitHub repository.
2. Open the repository Actions tab.
3. Run the `Build Android APK` workflow, or push to the main branch.
4. Download the `LakeNavWI-debug-apk` artifact from the completed workflow.
5. On the Android phone, allow installation from the app used to open the APK, then install `app-debug.apk`.

The debug APK is suitable for personal testing. A Play Store release would use a release signing key and additional store packaging.

## Online services used

- OpenStreetMap map tiles
- Leaflet mapping library
- NOAA Coast Survey chart display WMS
- National Weather Service API
- Wisconsin DNR public lake-map pages

Internet access is required for online map tiles, NOAA chart overlays, weather, and DNR links. Saved waypoints and recorded track data are stored locally on the device.

## Suggested next version

- Offline map downloads for a chosen lake/region.
- Direct Wisconsin DNR bathymetry overlays for supported lakes.
- Search lake by name.
- Nearby boat launches and access points.
- USGS lake/river gauge data when available.
- NOAA buoy/station observations where available.
- Magnetic compass heading while nearly stationary.
- Background track recording with a foreground notification.
- Man-overboard one-tap waypoint.
- Shallow-water alert based on charted contours where supported.
- Optional sonar/fish-finder GPX/CSV import.
