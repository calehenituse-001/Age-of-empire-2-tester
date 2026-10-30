#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 && $# -ne 4 ]]; then
  echo 'Usage: bash tools/rebuild_menu_from_v33.sh SUPPLIED_v3.3.apk NEW_v3.3_MenuFix.apk [EXISTING_KEY.pem EXISTING_CERT.der]' >&2
  exit 2
fi
original=$(realpath "$1")
output=$(realpath -m "$2")
if [[ $# == 4 ]]; then
  supplied_key=$(realpath "$3")
  supplied_cert=$(realpath "$4")
fi
cd "$(dirname "$0")/.."
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"
: "${ANDROID_JAR:=${ANDROID_HOME}/platforms/android-35/android.jar}"
: "${BUILD_TOOLS:=${ANDROID_HOME}/build-tools/35.0.0}"
for file in "$ANDROID_JAR" "$BUILD_TOOLS/d8" "$BUILD_TOOLS/zipalign" "$BUILD_TOOLS/apksigner"; do
  [[ -f "$file" ]] || { echo "Missing Android build tool: $file" >&2; exit 3; }
done
mkdir -p build/menu_fix_classes build/menu_fix_dex "$(dirname "$output")"
find android -type f -name '*.java' > build/menu_fix_java_sources.txt
javac -source 8 -target 8 -cp "$ANDROID_JAR" -d build/menu_fix_classes @build/menu_fix_java_sources.txt
mapfile -t classes < <(find build/menu_fix_classes/org -name '*.class')
"$BUILD_TOOLS/d8" --min-api 28 --lib "$ANDROID_JAR" --output build/menu_fix_dex "${classes[@]}"
python3 tools/repack_menu_v33.py "$original" build/menu_fix_dex/classes.dex build/menu_fix_unsigned.apk
"$BUILD_TOOLS/zipalign" -f -P 16 4 build/menu_fix_unsigned.apk build/menu_fix_aligned.apk
if [[ $# == 4 ]]; then
  key="$supplied_key"
  cert="$supplied_cert"
else
  key=build/menu-fix-local-key.pem
  cert=build/menu-fix-local-cert.der
  if [[ ! -f "$key" ]]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj '/CN=Stronghold Menu Fix Test/' -keyout "$key" -out build/menu-fix-cert.pem >/dev/null 2>&1
    openssl x509 -in build/menu-fix-cert.pem -outform DER -out "$cert"
  fi
fi
# The SDK apksigner expects an unencrypted DER PKCS#8 key.
if head -c 32 "$key" | grep -q -- '-----BEGIN'; then
  openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt -in "$key" -out build/menu-fix-private.pk8
  chmod 600 build/menu-fix-private.pk8
  key=build/menu-fix-private.pk8
fi
"$BUILD_TOOLS/apksigner" sign --key "$key" --cert "$cert" --out "$output" build/menu_fix_aligned.apk
"$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$output"
"$BUILD_TOOLS/zipalign" -c -P 16 4 "$output"
python3 tools/verify_menu_apk.py "$output"
echo "New Stronghold APK: $output"
echo 'WARNING: If signing with a new key, Android will reject updating the installed older APK. Back up all saves and data before uninstalling.'
