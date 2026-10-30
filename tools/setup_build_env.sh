#!/usr/bin/env bash
# Checks for, downloads and installs the software needed to build the Age of Android / AoE2HDBeta APKs (see docs/BUILD.md),
# then prints a report: what is installed (with versions), what failed and how to install it by hand.
#
#   tools/setup_build_env.sh            check, then install what is missing (asks once before installing)
#   tools/setup_build_env.sh --check    only check and report, change nothing
#   tools/setup_build_env.sh --yes      do not ask
#
# For Debian/Ubuntu and derivatives (apt) on x86_64. System packages go through apt (sudo); Godot, its export templates and the Android SDK
# are installed under your home folder, no root needed. Override with: GODOT_VERSION, GODOT_DIR, ANDROID_SDK_ROOT.
set -u

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GODOT_TAG="${GODOT_VERSION}-stable"
GODOT_DIR="${GODOT_DIR:-$HOME/godot}"
GODOT_BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_TAG}"
GODOT_BIN_NAME="Godot_v${GODOT_TAG}_linux.x86_64"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
SDK_PACKAGES=("platform-tools" "platforms;android-34" "build-tools;34.0.0")
KEYSTORE="$HOME/.android/debug.keystore"
EDITOR_SETTINGS="$HOME/.config/godot/editor_settings-${GODOT_VERSION%.*}.tres"
APT_PACKAGES=(curl unzip git ca-certificates python3 python3-pil python3-numpy)

MODE=install; ASSUME_YES=0
for a in "$@"; do
  case "$a" in
    --check) MODE=check;;
    --yes|-y) ASSUME_YES=1;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    *) echo "unknown option: $a"; exit 2;;
  esac
done

OK=(); FAILED=(); MANUAL=()
say() { printf '\n== %s\n' "$*"; }
ok() { OK+=("$1"); printf '   ok: %s\n' "$1"; }
fail() { FAILED+=("$1"); MANUAL+=("$1|$2"); printf '   FAILED: %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then have sudo && SUDO="sudo"; fi

# ---------------------------------------------------------------------------------------------- platform
say "Platform"
ARCH="$(uname -m)"
if ! have apt-get; then
  echo "   This script needs apt (Debian, Ubuntu, Mint, Pop!_OS ...). Not found."
  fail "apt package manager" "Install these with your distribution's package manager: ${APT_PACKAGES[*]} openjdk-21-jdk. Then download Godot ${GODOT_VERSION} and its export templates from ${GODOT_BASE}/ and the Android command-line tools from https://developer.android.com/studio#command-line-tools-only, as described in docs/BUILD.md."
  APT=0
else
  APT=1; echo "   apt found, architecture $ARCH"
fi
[ "$ARCH" = "x86_64" ] || echo "   note: Godot's official Linux build used here is x86_64; on $ARCH install Godot ${GODOT_VERSION} yourself (https://godotengine.org/download)."

# ---------------------------------------------------------------------------------------------- what is missing
need_apt=(); need_jdk=0; need_godot=0; need_templates=0; need_sdk=0; need_keystore=0; need_settings=0
JAVA_HOME_FOUND=""

find_jdk() {
  local d
  for d in /usr/lib/jvm/java-21-openjdk-* /usr/lib/jvm/java-17-openjdk-* /usr/lib/jvm/*jdk*21* /usr/lib/jvm/*jdk*17*; do
    [ -x "$d/bin/javac" ] && [ -x "$d/bin/keytool" ] && { echo "$d"; return; }
  done
  if have javac && have keytool; then dirname "$(dirname "$(readlink -f "$(command -v javac)")")"; fi
}

say "Checking"
for p in "${APT_PACKAGES[@]}"; do
  if dpkg -s "$p" >/dev/null 2>&1; then echo "   have $p"; else echo "   missing $p"; need_apt+=("$p"); fi
done
JAVA_HOME_FOUND="$(find_jdk)"
if [ -n "$JAVA_HOME_FOUND" ]; then echo "   have JDK: $JAVA_HOME_FOUND"; else echo "   missing JDK 17+ (21 preferred)"; need_jdk=1; fi
GODOT_BIN=""
for c in "$GODOT_DIR/$GODOT_BIN_NAME" "$(command -v godot 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && "$c" --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable" && { GODOT_BIN="$c"; break; }
done
if [ -n "$GODOT_BIN" ]; then echo "   have Godot ${GODOT_VERSION}: $GODOT_BIN"; else echo "   missing Godot ${GODOT_VERSION}"; need_godot=1; fi
if [ -f "$TEMPLATES_DIR/android_debug.apk" ] || [ -f "$TEMPLATES_DIR/android_source.zip" ]; then echo "   have export templates"; else echo "   missing export templates"; need_templates=1; fi
SDKMANAGER=""
for c in "$SDK/cmdline-tools/latest/bin/sdkmanager" "$SDK"/cmdline-tools/*/bin/sdkmanager; do [ -x "$c" ] && { SDKMANAGER="$c"; break; }; done
sdk_missing=()
if [ -z "$SDKMANAGER" ]; then echo "   missing Android command-line tools"; need_sdk=1; fi
for p in "${SDK_PACKAGES[@]}"; do
  d="$SDK/${p//;//}"
  if [ -d "$d" ]; then echo "   have SDK $p"; else echo "   missing SDK $p"; sdk_missing+=("$p"); need_sdk=1; fi
done
if [ -f "$KEYSTORE" ]; then echo "   have debug keystore"; else echo "   missing debug keystore"; need_keystore=1; fi
if [ -f "$EDITOR_SETTINGS" ] && grep -q "export/android/android_sdk_path" "$EDITOR_SETTINGS" && grep -q "export/android/debug_keystore" "$EDITOR_SETTINGS"; then
  echo "   have Godot Android settings"; else echo "   missing Godot Android settings"; need_settings=1; fi

todo=$(( ${#need_apt[@]} + need_jdk + need_godot + need_templates + need_sdk + need_keystore + need_settings ))
if [ "$MODE" = check ]; then
  echo; echo "   (--check: nothing is installed)"
elif [ "$todo" -gt 0 ]; then
  echo; echo "   $todo item(s) to install. Downloads: Godot ~60 MB, export templates ~1.2 GB, Android SDK ~300 MB."
  if [ "$ASSUME_YES" -ne 1 ]; then read -r -p "   Install now? [y/N] " ans; case "$ans" in y|Y|yes) ;; *) echo "   cancelled"; MODE=check;; esac; fi
fi

# ---------------------------------------------------------------------------------------------- installing
download() { # url file
  curl -fL --retry 3 --connect-timeout 20 -o "$2" "$1"
}
verify_godot_file() { # file name
  local sums="$TMP/SHA512-SUMS.txt" want got
  [ -s "$sums" ] || curl -fsL -o "$sums" "$GODOT_BASE/SHA512-SUMS.txt" || return 0
  want="$(grep " $2\$" "$sums" | awk '{print $1}')"
  [ -n "$want" ] || return 0
  got="$(sha512sum "$1" | awk '{print $1}')"
  [ "$want" = "$got" ]
}

if [ "$MODE" = install ] && [ "$todo" -gt 0 ]; then
  # work under the home folder (not /tmp, which can be a small RAM disk); the templates archive alone is 1.2 GB
  mkdir -p "$HOME/.cache"; TMP="$(mktemp -d "$HOME/.cache/aoe-build-env.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
  free_mb=$(df -Pm "$HOME" | awk 'NR==2{print $4}')
  [ "${free_mb:-0}" -lt 3000 ] && echo "   warning: only ${free_mb} MB free in $HOME; the install needs about 3 GB while it runs"
  if [ "$APT" -eq 1 ]; then
    if [ ${#need_apt[@]} -gt 0 ] || [ "$need_jdk" -eq 1 ]; then
      say "apt packages"
      if [ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ]; then
        fail "system packages (${need_apt[*]:-} openjdk)" "Run as root: apt-get update && apt-get install -y ${need_apt[*]:-} openjdk-21-jdk"
      else
        $SUDO apt-get update -qq || echo "   (apt update reported problems)"
        [ ${#need_apt[@]} -gt 0 ] && { $SUDO apt-get install -y "${need_apt[@]}" || fail "apt packages: ${need_apt[*]}" "Run: sudo apt-get install -y ${need_apt[*]}   (check the error above; a missing universe repository can be enabled with: sudo add-apt-repository universe)"; }
        if [ "$need_jdk" -eq 1 ]; then
          $SUDO apt-get install -y openjdk-21-jdk || $SUDO apt-get install -y openjdk-17-jdk || fail "JDK" "Run: sudo apt-get install -y openjdk-21-jdk   (on older Ubuntu releases without it, install openjdk-17-jdk, or download Temurin 21 from https://adoptium.net)"
        fi
      fi
    fi
  fi
  have curl || fail "curl" "Install curl (sudo apt-get install curl), then run this script again."
  have unzip || fail "unzip" "Install unzip (sudo apt-get install unzip), then run this script again."

  if [ "$need_godot" -eq 1 ] && have curl && have unzip; then
    say "Godot ${GODOT_VERSION}"
    if [ "$ARCH" != "x86_64" ]; then fail "Godot ${GODOT_VERSION}" "This script installs the x86_64 build only. Get Godot ${GODOT_VERSION} for $ARCH from https://godotengine.org/download/archive/${GODOT_TAG}/ and put it on PATH as 'godot'."
    elif download "$GODOT_BASE/${GODOT_BIN_NAME}.zip" "$TMP/godot.zip" && verify_godot_file "$TMP/godot.zip" "${GODOT_BIN_NAME}.zip"; then
      mkdir -p "$GODOT_DIR" "$HOME/.local/bin"
      unzip -oq "$TMP/godot.zip" -d "$GODOT_DIR" && chmod +x "$GODOT_DIR/$GODOT_BIN_NAME" && ln -sf "$GODOT_DIR/$GODOT_BIN_NAME" "$HOME/.local/bin/godot"
      GODOT_BIN="$GODOT_DIR/$GODOT_BIN_NAME"
    else
      fail "Godot ${GODOT_VERSION}" "Download ${GODOT_BASE}/${GODOT_BIN_NAME}.zip in a browser, unzip it into $GODOT_DIR, make it executable and link it as ~/.local/bin/godot. (If the checksum failed, download again.)"
    fi
  fi

  if [ "$need_templates" -eq 1 ] && have curl && have unzip; then
    say "Godot export templates (large download)"
    T="Godot_v${GODOT_TAG}_export_templates.tpz"
    if download "$GODOT_BASE/$T" "$TMP/templates.zip" && verify_godot_file "$TMP/templates.zip" "$T"; then
      mkdir -p "$TMP/tpl" "$TEMPLATES_DIR"
      # only the Android templates (and version.txt) are needed
      unzip -oq "$TMP/templates.zip" 'templates/android*' 'templates/version.txt' -d "$TMP/tpl" && cp -r "$TMP/tpl/templates/." "$TEMPLATES_DIR/" && echo "   installed to $TEMPLATES_DIR"
    else
      rm -rf "$TEMPLATES_DIR"
      fail "Godot export templates" "Download ${GODOT_BASE}/${T}, then in the Godot editor: Editor > Manage Export Templates > Install From File. Or unzip it and copy the 'templates' folder contents to $TEMPLATES_DIR"
    fi
  fi

  if [ "$need_sdk" -eq 1 ] && have curl && have unzip; then
    say "Android SDK"
    JH="$(find_jdk)"
    if [ -z "$JH" ]; then fail "Android SDK" "Needs a JDK first (see the JDK entry), then run this script again."
    else
      if [ -z "$SDKMANAGER" ]; then
        if download "$CMDLINE_URL" "$TMP/cmdline.zip"; then
          mkdir -p "$SDK/cmdline-tools" && unzip -oq "$TMP/cmdline.zip" -d "$TMP/cl" && rm -rf "$SDK/cmdline-tools/latest" && mv "$TMP/cl/cmdline-tools" "$SDK/cmdline-tools/latest"
          SDKMANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
          echo "   command-line tools sha256: $(sha256sum "$TMP/cmdline.zip" | awk '{print $1}')"
        else
          fail "Android command-line tools" "Download 'Command line tools only' for Linux from https://developer.android.com/studio#command-line-tools-only and unzip so that $SDK/cmdline-tools/latest/bin/sdkmanager exists."
        fi
      fi
      if [ -n "$SDKMANAGER" ]; then
        export JAVA_HOME="$JH"
        yes | "$SDKMANAGER" --sdk_root="$SDK" --licenses >/dev/null 2>&1
        "$SDKMANAGER" --sdk_root="$SDK" "${SDK_PACKAGES[@]}" || fail "Android SDK packages" "Run: $SDKMANAGER --sdk_root=$SDK --licenses  and then  $SDKMANAGER --sdk_root=$SDK \"platform-tools\" \"platforms;android-34\" \"build-tools;34.0.0\""
      fi
    fi
  fi

  if [ "$need_keystore" -eq 1 ]; then
    say "Debug keystore"
    JH="$(find_jdk)"
    if [ -n "$JH" ]; then
      mkdir -p "$(dirname "$KEYSTORE")"
      "$JH/bin/keytool" -genkeypair -v -keystore "$KEYSTORE" -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
        -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1 && echo "   created $KEYSTORE" \
        || fail "debug keystore" "Run: keytool -genkeypair -v -keystore $KEYSTORE -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname \"CN=Android Debug,O=Android,C=US\""
    else
      fail "debug keystore" "Needs a JDK (keytool). Install it, then run: keytool -genkeypair -v -keystore $KEYSTORE -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname \"CN=Android Debug,O=Android,C=US\""
    fi
  fi

  if [ "$need_settings" -eq 1 ]; then
    say "Godot editor settings for Android export"
    JH="$(find_jdk)"
    mkdir -p "$(dirname "$EDITOR_SETTINGS")"
    python3 -I - "$EDITOR_SETTINGS" "$SDK" "${JH:-}" "$KEYSTORE" <<'PY' && echo "   wrote $EDITOR_SETTINGS" || fail "Godot Android settings" "In the Godot editor open Editor > Editor Settings > Export > Android and set Android Sdk Path=$SDK, Java Sdk Path=${JH:-<your JDK folder>}, Debug Keystore=$KEYSTORE, user android, password android."
import sys, re
path, sdk, jdk, ks = sys.argv[1:5]
want = {"export/android/android_sdk_path": sdk, "export/android/java_sdk_path": jdk,
        "export/android/debug_keystore": ks, "export/android/debug_keystore_user": "androiddebugkey", "export/android/debug_keystore_pass": "android"}
try:
    text = open(path).read()
except FileNotFoundError:
    text = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
if "[resource]" not in text:
    text += "\n[resource]\n"
for k, v in want.items():
    line = '%s = "%s"' % (k, v)
    pat = re.compile(r'^' + re.escape(k) + r' = .*$', re.M)
    text = pat.sub(line, text) if pat.search(text) else text.replace("[resource]\n", "[resource]\n" + line + "\n", 1)
open(path, "w").write(text)
PY
  fi
fi

# ---------------------------------------------------------------------------------------------- report
say "Report"
ver() { "$@" 2>&1 | head -1; }
row() { printf '   %-34s %s\n' "$1" "$2"; }
echo "Installed:"
have curl && row "curl" "$(ver curl --version)"
have unzip && row "unzip" "$(ver unzip -v)"
have git && row "git" "$(ver git --version)"
have python3 && row "python3" "$(ver python3 --version)"
python3 -c "import PIL; print('Pillow', PIL.__version__)" >/dev/null 2>&1 && row "Pillow (python3-pil)" "$(python3 -c 'import PIL; print(PIL.__version__)')"
python3 -c "import numpy" >/dev/null 2>&1 && row "NumPy (python3-numpy)" "$(python3 -c 'import numpy; print(numpy.__version__)')"
JH="$(find_jdk)"; [ -n "$JH" ] && row "JDK" "$("$JH/bin/javac" -version 2>&1) ($JH)"
GB=""; for c in "$GODOT_DIR/$GODOT_BIN_NAME" "$(command -v godot 2>/dev/null)"; do [ -n "$c" ] && [ -x "$c" ] && { GB="$c"; break; }; done
[ -n "$GB" ] && row "Godot" "$("$GB" --version 2>/dev/null | head -1) ($GB)"
{ [ -f "$TEMPLATES_DIR/android_debug.apk" ] || [ -f "$TEMPLATES_DIR/android_source.zip" ]; } && row "Godot export templates" "${GODOT_VERSION}.stable ($TEMPLATES_DIR)"
SM=""; for c in "$SDK/cmdline-tools/latest/bin/sdkmanager" "$SDK"/cmdline-tools/*/bin/sdkmanager; do [ -x "$c" ] && { SM="$c"; break; }; done
[ -n "$SM" ] && row "Android command-line tools" "$(JAVA_HOME="${JH:-}" "$SM" --sdk_root="$SDK" --version 2>/dev/null | head -1) ($SDK)"
for p in "${SDK_PACKAGES[@]}"; do d="$SDK/${p//;//}"; [ -d "$d" ] && row "SDK $p" "$(grep -h '^Pkg.Revision' "$d/source.properties" 2>/dev/null | cut -d= -f2)"; done
[ -x "$SDK/platform-tools/adb" ] && row "adb" "$("$SDK/platform-tools/adb" version 2>/dev/null | head -1)"
[ -f "$KEYSTORE" ] && row "debug keystore" "$KEYSTORE"
grep -q "export/android/android_sdk_path" "$EDITOR_SETTINGS" 2>/dev/null && row "Godot Android settings" "$EDITOR_SETTINGS"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo; echo "FAILED / needs manual installation:"
  for m in "${MANUAL[@]}"; do printf '   - %s\n     %s\n' "${m%%|*}" "${m#*|}"; done
fi
missing_now=()
[ -z "$GB" ] && missing_now+=("Godot")
[ -z "$JH" ] && missing_now+=("JDK")
[ -z "$SM" ] && missing_now+=("Android SDK")
if [ "$MODE" = check ] && [ ${#missing_now[@]} -gt 0 ]; then echo; echo "Not installed yet (run without --check to install): ${missing_now[*]}"; fi
echo
if [ ${#FAILED[@]} -eq 0 ] && [ ${#missing_now[@]} -eq 0 ]; then
  echo "Everything needed is installed. Add ~/.local/bin to PATH if 'godot' is not found, then see docs/BUILD.md:"
  echo "   mkdir -p godot_game/build && godot --headless --path godot_game --import && godot --headless --path godot_game --export-debug \"Android portable\" build/aoe2hdbeta.apk"
  exit 0
fi
exit 1
