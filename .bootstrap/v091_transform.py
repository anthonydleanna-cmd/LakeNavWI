from pathlib import Path

p=Path('app/src/main/AndroidManifest.xml')
s=p.read_text()
old='''        <service
            android:name=".BackgroundTrackService"
            android:exported="false"
            android:foregroundServiceType="location" />'''
new=old+'''
        <service
            android:name=".NavigationService"
            android:exported="false"
            android:foregroundServiceType="location" />'''
if '.NavigationService' not in s:
    if old not in s: raise SystemExit('v0.91 manifest anchor missing')
    s=s.replace(old,new,1)
p.write_text(s)

p=Path('app/src/main/java/com/lakenav/wi/MainActivity.java')
s=p.read_text()
s=s.replace('LakeNavWI/0.90 (+personal Android lake navigation prototype)','LakeNavWI/0.91 (+personal Android lake navigation prototype)',1)
s=s.replace('settings.setUserAgentString(settings.getUserAgentString() + " LakeNavWI/0.90");','settings.setUserAgentString(settings.getUserAgentString() + " LakeNavWI/0.91");',1)
s=s.replace('evaluateJavascript("window.syncBackgroundTrackFromNative && window.syncBackgroundTrackFromNative(true);");','evaluateJavascript("window.syncBackgroundTrackFromNative && window.syncBackgroundTrackFromNative(true); window.syncLockScreenNavigationFromNative && window.syncLockScreenNavigationFromNative();");',1)
s=s.replace('webView.postDelayed(() -> evaluateJavascript("window.syncBackgroundTrackFromNative && window.syncBackgroundTrackFromNative(true);"), 250L);','webView.postDelayed(() -> evaluateJavascript("window.syncBackgroundTrackFromNative && window.syncBackgroundTrackFromNative(true); window.syncLockScreenNavigationFromNative && window.syncLockScreenNavigationFromNative();"), 250L);',1)
s=s.replace('Toast.makeText(this, granted ? "Lightning notifications enabled." : "Notification permission denied. In-app lightning alerts will still work.", Toast.LENGTH_LONG).show();','Toast.makeText(this, granted ? "LakeNav notifications enabled." : "Notification permission denied. Lock-screen and lightning alerts may be limited.", Toast.LENGTH_LONG).show();',1)
anchor='''        @JavascriptInterface
        public void startBackgroundTrack(long sessionStartMs) {'''
bridge='''        @JavascriptInterface
        public void startLockScreenNavigation(String stateJson) {
            runOnUiThread(() -> {
                if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQ_NOTIFICATIONS);
                }
                Intent intent = new Intent(MainActivity.this, NavigationService.class);
                intent.setAction(NavigationService.ACTION_START);
                intent.putExtra(NavigationService.EXTRA_STATE, stateJson == null ? "{}" : stateJson);
                if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent);
                else startService(intent);
            });
        }

        @JavascriptInterface
        public void updateLockScreenNavigation(String stateJson) {
            runOnUiThread(() -> {
                Intent intent = new Intent(MainActivity.this, NavigationService.class);
                intent.setAction(NavigationService.ACTION_UPDATE);
                intent.putExtra(NavigationService.EXTRA_STATE, stateJson == null ? "{}" : stateJson);
                if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent);
                else startService(intent);
            });
        }

        @JavascriptInterface
        public void stopLockScreenNavigation() {
            runOnUiThread(() -> {
                Intent intent = new Intent(MainActivity.this, NavigationService.class);
                intent.setAction(NavigationService.ACTION_STOP);
                startService(intent);
            });
        }

        @JavascriptInterface
        public String getLockScreenNavigationState() {
            return NavigationService.state(MainActivity.this).toString();
        }

'''
if 'startLockScreenNavigation' not in s:
    if anchor not in s: raise SystemExit('v0.91 MainActivity bridge anchor missing')
    s=s.replace(anchor,bridge+anchor,1)
p.write_text(s)

p=Path('app/src/main/assets/index.html')
s=p.read_text()
s=s.replace('<span class="versionPill">v0.90</span>','<span class="versionPill">v0.91</span>',1)
anchor='''  function startNavigation(id, options) {'''
helpers=r'''  function lockScreenNavigationState() {
    if (activeRouteId) {
      const route=routes.find(r=>r.id===activeRouteId);
      if(!route) return null;
      const returnMode=!!route.returnTrack;
      const source=returnMode?routeGeometryPoints(route):routeWaypoints(route);
      if(!source.length) return null;
      return {
        active:true, completed:false, navId:'route:'+route.id,
        routeName:route.name||'Route', mode:returnMode?'return':'route',
        index:returnMode?0:Math.max(0,Math.min(activeRouteIndex,source.length-1)),
        points:source.map((p,i)=>({lat:Number(p.lat),lon:Number(p.lon),name:p.name||(returnMode?'Recorded track':routePointName(i,source.length))}))
      };
    }
    if(targetId) {
      const w=waypoints.find(x=>x.id===targetId);
      if(!w) return null;
      return {active:true,completed:false,navId:'waypoint:'+w.id,routeName:w.name||'Waypoint',mode:'waypoint',index:0,points:[{lat:Number(w.lat),lon:Number(w.lon),name:w.name||'Waypoint'}]};
    }
    return null;
  }
  function startLockScreenNavigation() { const state=lockScreenNavigationState(); if(state&&window.Android&&Android.startLockScreenNavigation){ try{Android.startLockScreenNavigation(JSON.stringify(state));}catch(e){} } }
  function updateLockScreenNavigation() { const state=lockScreenNavigationState(); if(state&&window.Android&&Android.updateLockScreenNavigation){ try{Android.updateLockScreenNavigation(JSON.stringify(state));}catch(e){} } }
  function stopLockScreenNavigation() { if(window.Android&&Android.stopLockScreenNavigation){ try{Android.stopLockScreenNavigation();}catch(e){} } }
  function syncLockScreenNavigationFromNative() {
    if(!(window.Android&&Android.getLockScreenNavigationState)) return false;
    try {
      const state=JSON.parse(Android.getLockScreenNavigationState()||'{}');
      if(!state||!state.navId) return false;
      const expected=activeRouteId?('route:'+activeRouteId):(targetId?('waypoint:'+targetId):'');
      if(!expected||state.navId!==expected) return false;
      if(state.completed||state.active===false){ stopNavigation(); return true; }
      if(activeRouteId&&state.mode==='route'){
        const route=routes.find(r=>r.id===activeRouteId), pts=routeWaypoints(route);
        const next=Math.max(0,Math.min(Number(state.index)||0,Math.max(0,pts.length-1)));
        if(next>activeRouteIndex){ activeRouteIndex=next; updateRouteNavPanel(); updateNavigation(); }
      }
      return true;
    } catch(e){ return false; }
  }
  window.syncLockScreenNavigationFromNative=syncLockScreenNavigationFromNative;

'''
if 'function lockScreenNavigationState()' not in s:
    if anchor not in s: raise SystemExit('v0.91 index helper anchor missing')
    s=s.replace(anchor,helpers+anchor,1)
old='''    syncNavigationTouchLockUi();
    if (window.Android && Android.keepScreenOn) Android.keepScreenOn(true);'''
new='''    syncNavigationTouchLockUi();
    startLockScreenNavigation();
    if (window.Android && Android.keepScreenOn) Android.keepScreenOn(true);'''
if s.count(old)<2: raise SystemExit('v0.91 navigation start anchors missing')
s=s.replace(old,new,2)
old_adv='''      activeRouteIndex += 1;
      updateRouteNavPanel();
      renderOfflineFallbackOverlays();'''
new_adv='''      activeRouteIndex += 1;
      updateRouteNavPanel();
      updateLockScreenNavigation();
      renderOfflineFallbackOverlays();'''
if old_adv not in s: raise SystemExit('v0.91 advance anchor missing')
s=s.replace(old_adv,new_adv,1)
old_stop='''    resyncNavigationPuckAfterStop();
    if (window.Android && Android.keepScreenOn) Android.keepScreenOn(recording);'''
new_stop='''    resyncNavigationPuckAfterStop();
    stopLockScreenNavigation();
    if (window.Android && Android.keepScreenOn) Android.keepScreenOn(recording);'''
if old_stop not in s: raise SystemExit('v0.91 stop anchor missing')
s=s.replace(old_stop,new_stop,1)
p.write_text(s)

p=Path('README.md')
s=p.read_text()
if '## Version 0.91 features' not in s:
    s += '''

## Version 0.91 features
- Native lock-screen navigation foreground service for active waypoint and route guidance.
- High-contrast black route preview with a white boat marker and route line in the ongoing navigation notification.
- Waypoint-reached and route-complete notifications continue while the screen is off or LakeNav is backgrounded.
- Native route progress synchronizes back into LakeNav when the app returns to the foreground.
- Existing v0.90 Course Up, touch lock, background track recording, NOAA, and map behavior remain unchanged.
'''
p.write_text(s)
