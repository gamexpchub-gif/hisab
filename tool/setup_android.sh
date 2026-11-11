#!/usr/bin/env bash
# Prepares the Android project: creates it if missing, sets the app name,
# GameX icons and the camera permission (barcode scanner). Safe to re-run.
set -e
cd "$(dirname "$0")/.."
if [ ! -d android ]; then
  flutter create --platforms=android --org com.gamexpchub --project-name hisab .
fi
MANIFEST=android/app/src/main/AndroidManifest.xml
sed -i 's/android:label="[^"]*"/android:label="GameX Hisab"/' "$MANIFEST"
if ! grep -q 'android.permission.CAMERA' "$MANIFEST"; then
  sed -i 's|<application|<uses-permission android:name="android.permission.CAMERA"/>\n    <application|' "$MANIFEST"
fi
cp -r tool/android_res/* android/app/src/main/res/
echo "Android project ready."
