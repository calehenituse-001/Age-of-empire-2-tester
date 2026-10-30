#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 2 ]]; then echo 'Usage: bash tools/build.sh ORIGINAL.apk OUTPUT.apk [KEY.pem CERT.der]' >&2; exit 2; fi
original=$(realpath "$1")
output=$(realpath -m "$2")
if [[ $# -ge 4 ]]; then supplied_key=$(realpath "$3");supplied_cert=$(realpath "$4");fi
cd "$(dirname "$0")/.."
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"
: "${ANDROID_JAR:=${ANDROID_HOME}/platforms/android-35/android.jar}"
: "${BUILD_TOOLS:=${ANDROID_HOME}/build-tools/35.0.0}"
: "${NDK_BIN:=${ANDROID_HOME}/ndk/27.2.12479018/toolchains/llvm/prebuilt/linux-x86_64/bin}"
export NDK_BIN
for f in "$ANDROID_JAR" "$BUILD_TOOLS/d8" "$BUILD_TOOLS/apksigner" "$BUILD_TOOLS/zipalign" "$NDK_BIN/aarch64-linux-android28-clang"; do
 [[ -f "$f" ]] || { echo "Missing build tool: $f" >&2; exit 3; }
done
mkdir -p build/java build/dex "$(dirname "$output")"
python3 - "$original" <<'PY'
import hashlib,pathlib,sys,zipfile
p=pathlib.Path(sys.argv[1]);raw=p.read_bytes()
assert hashlib.sha256(raw).hexdigest()=='92dc03003274dcac024d63a66e61fab75f9f5b26bb3bcd01c89f935bfa22d252','Requires exact original APK, not an earlier mod'
with zipfile.ZipFile(p) as z:pathlib.Path('build/libstronghold-original.so').write_bytes(z.read('lib/arm64-v8a/libstronghold.so'))
PY
python3 tools/patch_extreme.py build/libstronghold-original.so build/libstronghold-menu-v33.so
"$NDK_BIN/aarch64-linux-android28-clang" -std=c11 -shared -fPIC -fvisibility=hidden -Oz -Wall -Wextra -Werror \
 -Wl,-z,max-page-size=16384 -I native native/mod_runtime.c -ldl -o build/libstronghold_mod_runtime.so
python3 tests/test_native.py
rg --files android -g '*.java' > build/java_sources.txt
javac -source 8 -target 8 -cp "$ANDROID_JAR" -d build/java @build/java_sources.txt
javac -cp "build/java:$ANDROID_JAR" -d build/java tests/SettingsTest.java
java -cp "build/java:$ANDROID_JAR" SettingsTest
# Only application classes go into the APK; JVM test class stays outside DEX.
mapfile -t classes < <(rg --files build/java/org -g '*.class')
"$BUILD_TOOLS/d8" --min-api 28 --lib "$ANDROID_JAR" --output build/dex "${classes[@]}"
python3 tools/assemble_unsigned_apk.py "$original" build/unsigned.apk
"$BUILD_TOOLS/zipalign" -f -P 16 4 build/unsigned.apk build/aligned.apk
if [[ $# -ge 4 ]]; then key=$supplied_key;cert=$supplied_cert;
else
 key=build/local-test-key.pem;cert=build/local-test-cert.der
 if [[ ! -f "$key" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj '/CN=Stronghold Mod v3.3 Test/' -keyout "$key" -out build/local-test-cert.pem >/dev/null 2>&1
  openssl x509 -in build/local-test-cert.pem -outform DER -out "$cert"
 fi
fi
# apksigner reads DER PKCS#8. Convert PEM explicitly; never commit this output.
if head -c 32 "$key" | rg -q -- '-----BEGIN'; then
 openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt -in "$key" -out build/signing-key.pk8
 chmod 600 build/signing-key.pk8
 key=build/signing-key.pk8
fi
"$BUILD_TOOLS/apksigner" sign --key "$key" --cert "$cert" --out "$output" build/aligned.apk
"$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$output" | tee build/signature_verification.txt
"$BUILD_TOOLS/zipalign" -c -P 16 4 "$output"
python3 tests/test_apk.py "$original" "$output"
python3 tools/verify_menu_apk.py "$output"
printf 'Signed test APK: %s\n' "$output"
