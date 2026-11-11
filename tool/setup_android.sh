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
# Gradle defaults to an 8 GB heap, which gets the build killed on machines
# with less RAM ("Gradle build daemon disappeared unexpectedly").
PROPS=android/gradle.properties
touch "$PROPS"
sed -i '/^org.gradle.jvmargs=/d;/^kotlin.daemon.jvmargs=/d' "$PROPS"
echo 'org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8' >> "$PROPS"
echo 'kotlin.daemon.jvmargs=-Xmx1536m' >> "$PROPS"

echo "Android project ready."
