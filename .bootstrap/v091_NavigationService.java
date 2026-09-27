package com.lakenav.wi;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class NavigationService extends Service implements LocationListener {
    public static final String ACTION_START = "com.lakenav.wi.NAV_START";
    public static final String ACTION_UPDATE = "com.lakenav.wi.NAV_UPDATE";
    public static final String ACTION_STOP = "com.lakenav.wi.NAV_STOP";
    public static final String EXTRA_STATE = "state";

    private static final String CHANNEL_ID = "lakenav_navigation";
    private static final String ALERT_CHANNEL_ID = "lakenav_navigation_alerts";
    private static final int NOTIFICATION_ID = 9101;
    private static final String PREFS = "lakenav_navigation_state";
    private static final String KEY_STATE = "state_json";
    private static final double ADVANCE_METERS = 45.72;

    private final List<NavPoint> points = new ArrayList<>();
    private LocationManager locationManager;
    private String navId = "";
    private String routeName = "Navigation";
    private String mode = "route";
    private int index = 0;
    private boolean active = false;
    private boolean completed = false;
    private Location lastLocation;
    private long lastNotificationAt = 0L;
    private int lastAlertedIndex = -1;

    private static class NavPoint {
        double lat;
        double lon;
        String name;
        NavPoint(double lat, double lon, String name) {
            this.lat = lat;
            this.lon = lon;
            this.name = name == null || name.trim().isEmpty() ? "Waypoint" : name;
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        ensureChannels();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopNavigation();
            return START_NOT_STICKY;
        }

        if (ACTION_START.equals(action) || ACTION_UPDATE.equals(action)) {
            String raw = intent == null ? null : intent.getStringExtra(EXTRA_STATE);
            if (raw != null && !raw.trim().isEmpty()) applyState(raw);
            if (!active || points.isEmpty()) {
                stopNavigation();
                return START_NOT_STICKY;
            }
            saveState();
            startForeground(NOTIFICATION_ID, buildNavigationNotification());
            startLocationUpdates();
            return START_STICKY;
        }

        String saved = getSharedPreferences(PREFS, MODE_PRIVATE).getString(KEY_STATE, null);
        if (saved != null) {
            applyState(saved);
            if (active && !points.isEmpty()) {
                startForeground(NOTIFICATION_ID, buildNavigationNotification());
                startLocationUpdates();
                return START_STICKY;
            }
        }
        stopSelf();
        return START_NOT_STICKY;
    }

    private void applyState(String raw) {
        try {
            JSONObject state = new JSONObject(raw);
            active = state.optBoolean("active", true);
            navId = state.optString("navId", "");
            routeName = state.optString("routeName", "Navigation");
            mode = state.optString("mode", "route");
            index = Math.max(0, state.optInt("index", 0));
            JSONArray arr = state.optJSONArray("points");
            points.clear();
            if (arr != null) {
                for (int i = 0; i < arr.length(); i++) {
                    JSONObject p = arr.optJSONObject(i);
                    if (p == null) continue;
                    double lat = p.optDouble("lat", Double.NaN);
                    double lon = p.optDouble("lon", Double.NaN);
                    if (!Double.isFinite(lat) || !Double.isFinite(lon)) continue;
                    points.add(new NavPoint(lat, lon, p.optString("name", "Waypoint")));
                }
            }
            if (!points.isEmpty()) index = Math.min(index, points.size() - 1);
            completed = state.optBoolean("completed", false);
        } catch (Exception e) {
            active = false;
            points.clear();
        }
    }

    private void startLocationUpdates() {
        if (!active || locationManager == null) return;
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) return;
        try { locationManager.removeUpdates(this); } catch (Exception ignored) {}
        try {
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0.0f, this);
                Location last = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER);
                if (last != null) onLocationChanged(last);
            }
        } catch (Exception ignored) {}
    }

    private void stopLocationUpdates() {
        if (locationManager == null) return;
        try { locationManager.removeUpdates(this); } catch (Exception ignored) {}
    }

    @Override
    public void onLocationChanged(Location location) {
        if (!active || location == null || points.isEmpty()) return;
        if (location.getProvider() != null && !LocationManager.GPS_PROVIDER.equals(location.getProvider())) return;
        lastLocation = new Location(location);

        NavPoint target = points.get(index);
        double distance = distanceMeters(location.getLatitude(), location.getLongitude(), target.lat, target.lon);
        if (distance <= ADVANCE_METERS) {
            if (index < points.size() - 1) {
                int reached = index;
                index++;
                saveState();
                if (!"return".equals(mode) && lastAlertedIndex != reached) {
                    lastAlertedIndex = reached;
                    NavPoint next = points.get(index);
                    postAlert("Waypoint reached", "Next: " + next.name);
                }
            } else {
                completed = true;
                active = false;
                saveState();
                postAlert("Route complete", routeName);
                stopLocationUpdates();
                stopForeground(true);
                stopSelf();
                return;
            }
        }

        long now = System.currentTimeMillis();
        if (now - lastNotificationAt >= 900L) {
            lastNotificationAt = now;
            NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (manager != null) manager.notify(NOTIFICATION_ID, buildNavigationNotification());
        }
    }

    private Notification buildNavigationNotification() {
        NavPoint target = points.isEmpty() ? null : points.get(Math.min(index, points.size() - 1));
        double distance = -1;
        float bearing = -1f;
        if (target != null && lastLocation != null) {
            distance = distanceMeters(lastLocation.getLatitude(), lastLocation.getLongitude(), target.lat, target.lon);
            bearing = bearingDegrees(lastLocation.getLatitude(), lastLocation.getLongitude(), target.lat, target.lon);
        }
        String targetName = target == null ? "Navigation" : target.name;
        String distanceText = distance >= 0 ? formatDistance(distance) : "GPS acquiring";
        String detail = target == null ? routeName : distanceText + " • " + targetName;
        if (bearing >= 0) detail = Math.round(bearing) + "° • " + detail;

        Intent launch = new Intent(this, MainActivity.class);
        launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pending = PendingIntent.getActivity(this, 9101, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        builder.setSmallIcon(R.drawable.app_icon)
                .setContentTitle("LakeNav WI • " + routeName)
                .setContentText(detail)
                .setContentIntent(pending)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_NAVIGATION)
                .setPriority(Notification.PRIORITY_HIGH)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setShowWhen(false);

        Bitmap preview = renderRoutePreview();
        if (preview != null) {
            builder.setStyle(new Notification.BigPictureStyle()
                    .bigPicture(preview)
                    .setSummaryText(detail));
        }
        return builder.build();
    }

    private Bitmap renderRoutePreview() {
        if (points.isEmpty()) return null;
        final int width = 720;
        final int height = 360;
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.BLACK);

        double originLat;
        double originLon;
        if (lastLocation != null) {
            originLat = lastLocation.getLatitude();
            originLon = lastLocation.getLongitude();
        } else {
            NavPoint p = points.get(Math.min(index, points.size() - 1));
            originLat = p.lat;
            originLon = p.lon;
        }

        float heading = 0f;
        if (lastLocation != null && lastLocation.hasBearing() && lastLocation.getSpeed() >= 0.7f) {
            heading = lastLocation.getBearing();
        } else if (lastLocation != null && index < points.size()) {
            NavPoint target = points.get(index);
            heading = bearingDegrees(originLat, originLon, target.lat, target.lon);
        }
        double h = Math.toRadians(heading);
        double cos = Math.cos(h), sin = Math.sin(h);

        int end = Math.min(points.size(), index + 5);
        List<float[]> projected = new ArrayList<>();
        double maxAbsX = 35.0;
        double maxForward = 80.0;
        for (int i = index; i < end; i++) {
            NavPoint p = points.get(i);
            double[] xy = localMeters(originLat, originLon, p.lat, p.lon);
            double right = xy[0] * cos - xy[1] * sin;
            double forward = xy[0] * sin + xy[1] * cos;
            projected.add(new float[]{(float) right, (float) forward});
            maxAbsX = Math.max(maxAbsX, Math.abs(right));
            maxForward = Math.max(maxForward, forward);
        }

        double scaleX = (width * 0.40) / maxAbsX;
        double scaleY = (height * 0.66) / Math.max(80.0, maxForward);
        double scale = Math.max(0.18, Math.min(scaleX, scaleY));
        float cx = width / 2f;
        float cy = height * 0.82f;

        Paint shadow = new Paint(Paint.ANTI_ALIAS_FLAG);
        shadow.setColor(Color.rgb(55,55,55));
        shadow.setStyle(Paint.Style.STROKE);
        shadow.setStrokeWidth(16f);
        shadow.setStrokeCap(Paint.Cap.ROUND);
        shadow.setStrokeJoin(Paint.Join.ROUND);

        Paint route = new Paint(Paint.ANTI_ALIAS_FLAG);
        route.setColor(Color.WHITE);
        route.setStyle(Paint.Style.STROKE);
        route.setStrokeWidth(8f);
        route.setStrokeCap(Paint.Cap.ROUND);
        route.setStrokeJoin(Paint.Join.ROUND);

        if (!projected.isEmpty()) {
            Path path = new Path();
            path.moveTo(cx, cy);
            for (float[] p : projected) {
                float x = cx + (float) (p[0] * scale);
                float y = cy - (float) (p[1] * scale);
                path.lineTo(x, y);
            }
            canvas.drawPath(path, shadow);
            canvas.drawPath(path, route);
        }

        Paint markerFill = new Paint(Paint.ANTI_ALIAS_FLAG);
        markerFill.setColor(Color.WHITE);
        markerFill.setStyle(Paint.Style.FILL);
        Paint markerStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        markerStroke.setColor(Color.rgb(70,70,70));
        markerStroke.setStyle(Paint.Style.STROKE);
        markerStroke.setStrokeWidth(5f);
        Path boat = new Path();
        boat.moveTo(cx, cy - 30f);
        boat.lineTo(cx - 20f, cy + 22f);
        boat.lineTo(cx, cy + 12f);
        boat.lineTo(cx + 20f, cy + 22f);
        boat.close();
        canvas.drawPath(boat, markerFill);
        canvas.drawPath(boat, markerStroke);

        if (!projected.isEmpty()) {
            float[] p = projected.get(0);
            float tx = cx + (float) (p[0] * scale);
            float ty = cy - (float) (p[1] * scale);
            canvas.drawCircle(tx, ty, 11f, markerFill);
            canvas.drawCircle(tx, ty, 11f, markerStroke);
        }
        return bitmap;
    }

    private static double[] localMeters(double lat0, double lon0, double lat, double lon) {
        double r = 6371000.0;
        double avgLat = Math.toRadians((lat0 + lat) / 2.0);
        double x = Math.toRadians(lon - lon0) * r * Math.cos(avgLat);
        double y = Math.toRadians(lat - lat0) * r;
        return new double[]{x, y};
    }

    private void postAlert(String title, String text) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return;
        NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;
        Intent launch = new Intent(this, MainActivity.class);
        launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pending = PendingIntent.getActivity(this, (int)(System.currentTimeMillis() & 0x7fffffff), launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, ALERT_CHANNEL_ID)
                : new Notification.Builder(this);
        builder.setSmallIcon(R.drawable.app_icon)
                .setContentTitle("LakeNav WI • " + title)
                .setContentText(text)
                .setContentIntent(pending)
                .setAutoCancel(true)
                .setPriority(Notification.PRIORITY_HIGH)
                .setCategory(Notification.CATEGORY_NAVIGATION)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setDefaults(Notification.DEFAULT_SOUND | Notification.DEFAULT_VIBRATE);
        manager.notify((int)(System.currentTimeMillis() & 0x7fffffff), builder.build());
    }

    private void ensureChannels() {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;
        NotificationChannel nav = new NotificationChannel(CHANNEL_ID, "Navigation", NotificationManager.IMPORTANCE_HIGH);
        nav.setDescription("Lock-screen route guidance while LakeNav WI navigation is active.");
        nav.setSound(null, null);
        nav.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        manager.createNotificationChannel(nav);

        NotificationChannel alerts = new NotificationChannel(ALERT_CHANNEL_ID, "Navigation waypoint alerts", NotificationManager.IMPORTANCE_HIGH);
        alerts.setDescription("Waypoint and route completion alerts from LakeNav WI.");
        alerts.enableVibration(true);
        alerts.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        manager.createNotificationChannel(alerts);
    }

    private void stopNavigation() {
        active = false;
        completed = false;
        points.clear();
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().remove(KEY_STATE).apply();
        stopLocationUpdates();
        stopForeground(true);
        stopSelf();
    }

    private void saveState() {
        try {
            JSONObject state = new JSONObject();
            state.put("active", active);
            state.put("completed", completed);
            state.put("navId", navId);
            state.put("routeName", routeName);
            state.put("mode", mode);
            state.put("index", index);
            JSONArray arr = new JSONArray();
            for (NavPoint p : points) {
                JSONObject o = new JSONObject();
                o.put("lat", p.lat);
                o.put("lon", p.lon);
                o.put("name", p.name);
                arr.put(o);
            }
            state.put("points", arr);
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(KEY_STATE, state.toString()).apply();
        } catch (Exception ignored) {}
    }

    public static JSONObject state(Context context) {
        String raw = context.getSharedPreferences(PREFS, MODE_PRIVATE).getString(KEY_STATE, null);
        if (raw == null) return new JSONObject();
        try { return new JSONObject(raw); } catch (Exception e) { return new JSONObject(); }
    }

    private static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
        double r = 6371000.0;
        double p1 = Math.toRadians(lat1), p2 = Math.toRadians(lat2);
        double dp = Math.toRadians(lat2 - lat1), dl = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dp / 2) * Math.sin(dp / 2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2);
        return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    private static float bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
        double p1 = Math.toRadians(lat1), p2 = Math.toRadians(lat2);
        double dl = Math.toRadians(lon2 - lon1);
        double y = Math.sin(dl) * Math.cos(p2);
        double x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
        double deg = Math.toDegrees(Math.atan2(y, x));
        return (float)((deg + 360.0) % 360.0);
    }

    private static String formatDistance(double meters) {
        if (meters < 160.9344) return Math.max(1, Math.round(meters * 3.28084)) + " ft";
        return String.format(Locale.US, "%.1f mi", meters / 1609.344);
    }

    @Override public void onProviderEnabled(String provider) {}
    @Override public void onProviderDisabled(String provider) {}
    @Override public void onStatusChanged(String provider, int status, Bundle extras) {}

    @Override
    public void onDestroy() {
        stopLocationUpdates();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}
