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

# Payment-due notifications (flutter_local_notifications):
# permissions + scheduled-notification receivers in the manifest …
for perm in POST_NOTIFICATIONS RECEIVE_BOOT_COMPLETED VIBRATE SCHEDULE_EXACT_ALARM; do
  if ! grep -q "android.permission.$perm" "$MANIFEST"; then
    sed -i "s|<application|<uses-permission android:name=\"android.permission.$perm\"/>\n    <application|" "$MANIFEST"
  fi
done
if ! grep -q 'ScheduledNotificationReceiver' "$MANIFEST"; then
  sed -i 's|</application>|    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>\n                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n            </intent-filter>\n        </receiver>\n    </application>|' "$MANIFEST"
fi
# … and Java 8+ API desugaring, which the plugin requires.
if [ -f android/app/build.gradle.kts ]; then
  G=android/app/build.gradle.kts
  if ! grep -q 'isCoreLibraryDesugaringEnabled' "$G"; then
    sed -i 's|compileOptions {|compileOptions {\n        isCoreLibraryDesugaringEnabled = true|' "$G"
  fi
  if ! grep -q 'desugar_jdk_libs' "$G"; then
    printf '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n' >> "$G"
  fi
  if ! grep -q 'androidx.core:core' "$G"; then
    printf '\ndependencies {\n    implementation("androidx.core:core:1.13.1")\n}\n' >> "$G"
  fi
elif [ -f android/app/build.gradle ]; then
  G=android/app/build.gradle
  if ! grep -q 'coreLibraryDesugaringEnabled' "$G"; then
    sed -i 's|compileOptions {|compileOptions {\n        coreLibraryDesugaringEnabled true|' "$G"
  fi
  if ! grep -q 'desugar_jdk_libs' "$G"; then
    printf "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n" >> "$G"
  fi
  if ! grep -q 'androidx.core:core' "$G"; then
    printf "\ndependencies {\n    implementation 'androidx.core:core:1.13.1'\n}\n" >> "$G"
  fi
fi
# App lock (local_auth): biometric permission and a FragmentActivity.
if ! grep -q 'android.permission.USE_BIOMETRIC' "$MANIFEST"; then
  sed -i 's|<application|<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application|' "$MANIFEST"
fi
# MainActivity: FlutterFragmentActivity (fingerprint) + the file share / pick
# channel used by Backup & Restore.
MA=$(find android/app/src/main -name 'MainActivity.kt' | head -1)
if [ -n "$MA" ]; then
  PKG=$(grep -m1 '^package ' "$MA" | sed 's/^package //')
  sed "s/__PACKAGE__/$PKG/" tool/android/MainActivity.kt > "$MA"
fi
if ! grep -q 'androidx.core.content.FileProvider' "$MANIFEST"; then
  sed -i 's|</application>|    <provider android:name="androidx.core.content.FileProvider" android:authorities="${applicationId}.files" android:exported="false" android:grantUriPermissions="true">\n            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/gamex_file_paths" />\n        </provider>\n    </application>|' "$MANIFEST"
fi

# Gradle defaults to an 8 GB heap, which gets the build killed on machines
# with less RAM ("Gradle build daemon disappeared unexpectedly").
PROPS=android/gradle.properties
touch "$PROPS"
sed -i '/^org.gradle.jvmargs=/d;/^kotlin.daemon.jvmargs=/d' "$PROPS"
echo 'org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8' >> "$PROPS"
echo 'kotlin.daemon.jvmargs=-Xmx1536m' >> "$PROPS"

echo "Android project ready."
