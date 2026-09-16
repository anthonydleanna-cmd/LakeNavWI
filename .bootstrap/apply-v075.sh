#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
cat .bootstrap/v075.patch.part00 .bootstrap/v075.patch.part01 .bootstrap/v075.patch.part02 > /tmp/lakenav-v075.patch
patch -p1 < /tmp/lakenav-v075.patch
python3 - <<'PY'
from pathlib import Path
p=Path('app/src/main/java/com/lakenav/wi/MainActivity.java')
s=p.read_text()
if 'public void fetchDnrText(String requestId, String url)' not in s:
    marker='    }\n}'
    pos=s.rfind(marker)
    if pos < 0:
        raise SystemExit('Could not find AndroidBridge closing marker for v0.75 DNR fetch bridge')
    method=r'''

        @JavascriptInterface
        public void fetchDnrText(String requestId, String url) {
            if (requestId == null || url == null) return;
            if (!(url.startsWith("https://apps.dnr.wi.gov/") || url.startsWith("https://dnr.wisconsin.gov/"))) return;
            new Thread(() -> {
                java.net.HttpURLConnection connection = null;
                boolean ok = false;
                String body = "";
                String error = "";
                try {
                    java.net.URL target = new java.net.URL(url);
                    connection = (java.net.HttpURLConnection) target.openConnection();
                    connection.setConnectTimeout(10000);
                    connection.setReadTimeout(15000);
                    connection.setInstanceFollowRedirects(true);
                    connection.setRequestProperty("User-Agent", "LakeNavWI/0.75 Android");
                    int code = connection.getResponseCode();
                    InputStream stream = (code >= 200 && code < 300) ? connection.getInputStream() : connection.getErrorStream();
                    if (stream != null) {
                        BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8));
                        StringBuilder text = new StringBuilder();
                        String line;
                        int maxChars = 1500000;
                        while ((line = reader.readLine()) != null && text.length() < maxChars) {
                            text.append(line).append('\n');
                        }
                        body = text.toString();
                    }
                    ok = code >= 200 && code < 300;
                    if (!ok) error = "HTTP " + code;
                } catch (Exception e) {
                    error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
                } finally {
                    if (connection != null) connection.disconnect();
                }
                final boolean resultOk = ok;
                final String resultBody = body;
                final String resultError = error;
                final String js = "window.onNativeDnrText && window.onNativeDnrText(" +
                        JSONObject.quote(requestId) + "," + resultOk + "," +
                        JSONObject.quote(resultBody) + "," + JSONObject.quote(resultError) + ");";
                webView.post(() -> webView.evaluateJavascript(js, null));
            }).start();
        }
'''
    s=s[:pos]+method+s[pos:]
    p.write_text(s)
PY
sed -i "s/versionCode [0-9][0-9]*/versionCode 75/" app/build.gradle
sed -i "s/versionName '[^']*'/versionName '0.75.0'/" app/build.gradle
node -e "const fs=require('fs');const h=fs.readFileSync('app/src/main/assets/index.html','utf8');const s=[...h.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)].map(x=>x[1]).join('\\n');fs.writeFileSync('/tmp/lakenav-v075-inline.js',s)"
node --check /tmp/lakenav-v075-inline.js
grep -q 'v0.75' app/src/main/assets/index.html
grep -q 'refreshSelectedLakeFishingInfo' app/src/main/assets/index.html
grep -q 'lakeLaunchPopup' app/src/main/assets/index.html
grep -q 'fetchDnrText' app/src/main/java/com/lakenav/wi/MainActivity.java
printf 'LakeNav WI v0.75 fishing regulations, lake fish information, and launch-popup navigation applied.\n'
