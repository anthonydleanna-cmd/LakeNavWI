package com.lakenav.wi;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

public class MainActivity extends Activity implements LocationListener {
    private static final int REQ_LOCATION = 1001;
    private static final int REQ_EXPORT_GPX = 2001;
    private static final int REQ_IMPORT_GPX = 2002;

    private WebView webView;
    private LocationManager locationManager;
    private String pendingExportName;
    private String pendingExportContent;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        webView = new WebView(this);
        setContentView(webView);
        configureWebView();

        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        webView.loadUrl("file:///android_asset/index.html");

        requestLocationPermissionIfNeeded();
    }

    private void configureWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setGeolocationEnabled(false);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);
        settings.setUserAgentString(settings.getUserAgentString() + " LakeNavWI/0.1");

        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new WebViewClient());
        webView.addJavascriptInterface(new AndroidBridge(), "Android");
    }

    private void requestLocationPermissionIfNeeded() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
            }, REQ_LOCATION);
        } else {
            startLocationUpdates();
        }
    }

    private void startLocationUpdates() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            return;
        }

        try {
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 1.0f, this);
                Location last = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER);
                if (last != null) onLocationChanged(last);
            }
        } catch (Exception ignored) {
        }

        try {
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 3000L, 3.0f, this);
            }
        } catch (Exception ignored) {
        }
    }

    private void stopLocationUpdates() {
        if (locationManager != null) {
            try {
                locationManager.removeUpdates(this);
            } catch (Exception ignored) {
            }
        }
    }

    @Override
    public void onLocationChanged(Location location) {
        final double lat = location.getLatitude();
        final double lon = location.getLongitude();
        final float accuracy = location.hasAccuracy() ? location.getAccuracy() : -1f;
        final float speed = location.hasSpeed() ? location.getSpeed() : -1f;
        final float bearing = location.hasBearing() ? location.getBearing() : -1f;
        final long time = location.getTime();

        String js = String.format(Locale.US,
                "window.onNativeLocation && window.onNativeLocation(%.8f,%.8f,%.2f,%.3f,%.2f,%d);",
                lat, lon, accuracy, speed, bearing, time);
        webView.post(() -> webView.evaluateJavascript(js, null));
    }

    @Override
    public void onProviderEnabled(String provider) {
    }

    @Override
    public void onProviderDisabled(String provider) {
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (locationManager != null) startLocationUpdates();
    }

    @Override
    protected void onPause() {
        stopLocationUpdates();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        stopLocationUpdates();
        if (webView != null) webView.destroy();
        super.onDestroy();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQ_LOCATION) {
            boolean granted = false;
            for (int result : grantResults) {
                if (result == PackageManager.PERMISSION_GRANTED) {
                    granted = true;
                    break;
                }
            }
            if (granted) {
                startLocationUpdates();
            } else {
                Toast.makeText(this, "Location permission is required for GPS navigation.", Toast.LENGTH_LONG).show();
            }
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || data.getData() == null) return;

        Uri uri = data.getData();
        if (requestCode == REQ_EXPORT_GPX) {
            try (OutputStream out = getContentResolver().openOutputStream(uri)) {
                if (out != null && pendingExportContent != null) {
                    out.write(pendingExportContent.getBytes(StandardCharsets.UTF_8));
                    out.flush();
                    Toast.makeText(this, "GPX saved.", Toast.LENGTH_SHORT).show();
                }
            } catch (Exception e) {
                Toast.makeText(this, "Could not save GPX: " + e.getMessage(), Toast.LENGTH_LONG).show();
            } finally {
                pendingExportContent = null;
                pendingExportName = null;
            }
        } else if (requestCode == REQ_IMPORT_GPX) {
            try (InputStream in = getContentResolver().openInputStream(uri)) {
                if (in == null) return;
                BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8));
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) sb.append(line).append('\n');
                String js = "window.importGpxText && window.importGpxText(" + JSONObject.quote(sb.toString()) + ");";
                webView.evaluateJavascript(js, null);
            } catch (Exception e) {
                Toast.makeText(this, "Could not import GPX: " + e.getMessage(), Toast.LENGTH_LONG).show();
            }
        }
    }

    public class AndroidBridge {
        @JavascriptInterface
        public void toast(String text) {
            runOnUiThread(() -> Toast.makeText(MainActivity.this, text, Toast.LENGTH_SHORT).show());
        }

        @JavascriptInterface
        public void keepScreenOn(boolean enabled) {
            runOnUiThread(() -> {
                if (enabled) {
                    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                } else {
                    getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                }
            });
        }

        @JavascriptInterface
        public void openLocationSettings() {
            runOnUiThread(() -> {
                try {
                    startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS));
                } catch (ActivityNotFoundException ignored) {
                }
            });
        }

        @JavascriptInterface
        public void openExternal(String url) {
            if (url == null || !(url.startsWith("https://") || url.startsWith("http://"))) return;
            runOnUiThread(() -> {
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                } catch (Exception e) {
                    Toast.makeText(MainActivity.this, "Could not open link.", Toast.LENGTH_SHORT).show();
                }
            });
        }

        @JavascriptInterface
        public void exportGpx(String filename, String content) {
            pendingExportName = (filename == null || filename.trim().isEmpty()) ? "LakeNav-track.gpx" : filename;
            pendingExportContent = content == null ? "" : content;
            runOnUiThread(() -> {
                Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("application/gpx+xml");
                intent.putExtra(Intent.EXTRA_TITLE, pendingExportName);
                startActivityForResult(intent, REQ_EXPORT_GPX);
            });
        }

        @JavascriptInterface
        public void importGpx() {
            runOnUiThread(() -> {
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("*/*");
                startActivityForResult(intent, REQ_IMPORT_GPX);
            });
        }
    }
}
