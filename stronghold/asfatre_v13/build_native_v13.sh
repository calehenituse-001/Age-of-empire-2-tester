#!/usr/bin/env bash
# Build native Stronghold ARM64 hooks for the *user-supplied* Asfatre v1.3.
# Does not create an installable APK or modify the proprietary input.
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo 'Usage: bash asfatre_v13/build_native_v13.sh /private/path/LauncherStrongholdAsfatre-V1.3.apk' >&2
  exit 2
fi
input=$(realpath "$1")
cd "$(dirname "$0")/.."
: "${NDK_BIN:?Set NDK_BIN to Android NDK toolchains/llvm/prebuilt/linux-x86_64/bin}"
test -x "$NDK_BIN/aarch64-linux-android28-clang" || { echo 'Android NDK clang missing' >&2; exit 3; }
mkdir -p build
python3 - "$input" <<'PY'
import hashlib,pathlib,sys,zipfile
p=pathlib.Path(sys.argv[1])
apk_hash='92f90a525716e6bc9d34bdd345a154780477fa1e0af5c0f16dfbd6f8be3629fd'
lib_hash='9f23ca8ef417c93d319e3f04a34d5eb0535b8c3222810f839c17d889a4c593a2'
if hashlib.sha256(p.read_bytes()).hexdigest()!=apk_hash:
    raise SystemExit('ERROR: Exact Asfatre v1.3 APK required')
with zipfile.ZipFile(p) as z:
    lib=z.read('lib/arm64-v8a/libstronghold.so')
if hashlib.sha256(lib).hexdigest()!=lib_hash:
    raise SystemExit('ERROR: Unexpected Asfatre Extreme native binary')
pathlib.Path('build/libstronghold-original-v13.so').write_bytes(lib)
print('Asfatre v1.3 original input verified')
PY
python3 asfatre_v13/patch_extreme_v13.py build/libstronghold-original-v13.so build/libstronghold-menu-v33.so
"$NDK_BIN/aarch64-linux-android28-clang" -std=c11 -shared -fPIC -fvisibility=hidden -Oz -Wall -Wextra -Werror \
 -Wl,-z,max-page-size=16384 -I native native/mod_runtime.c -ldl -o build/libstronghold_mod_runtime.so
python3 tests/test_native.py
echo 'Native v1.3 candidate patch compiled and emulation tests completed.'
echo 'NOT an APK: Java GameActivity cheat-menu integration and Android tests remain required.'
