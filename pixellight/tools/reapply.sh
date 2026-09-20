#!/bin/sh
# Re-installs the APK and re-applies the live wallpaper on the emulator.
# Coordinates are for the 320x640 AVD created without a device profile.
set -e
ADB="${ANDROID_HOME:-$LOCALAPPDATA/Android/Sdk}/platform-tools/adb.exe"
APK="$(dirname "$0")/../app/build/outputs/apk/debug/app-debug.apk"

"$ADB" install -r "$APK"
"$ADB" logcat -c
"$ADB" shell am start -a android.service.wallpaper.LIVE_WALLPAPER_CHOOSER >/dev/null
sleep 3
"$ADB" shell input tap 160 84
sleep 3
"$ADB" shell input tap 160 582
sleep 2
"$ADB" shell input tap 160 391
sleep 2
"$ADB" shell input keyevent 3
sleep 2
echo "---- pixlife ----"
"$ADB" logcat -d -s pixlife 2>/dev/null | tr -d '\r'
echo "---- wallpaper component ----"
"$ADB" shell dumpsys wallpaper 2>/dev/null | tr -d '\r' | grep mWallpaperComponent | head -1
