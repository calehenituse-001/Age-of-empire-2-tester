#!/usr/bin/env bash
# Export the Godot game as a debug APK, install it on the connected device, launch it and save a screenshot.
# Usage: tools/tablet.sh [dev|portable] [screenshot.png]
#   dev      the development version (all game files bundled), package dev.j3rry.villagebuilder          (default)
#   portable the portable version "AoE2HDBeta" (no game files, imports them on first start), package co.domotix.ao2hdbeta
set -euo pipefail
VARIANT=dev
case "${1:-}" in dev|portable) VARIANT="$1"; shift;; esac
ROOT="$(cd "$(dirname "$0")/.." && pwd)/godot_game"
if [ "$VARIANT" = portable ]; then
  PKG=co.domotix.ao2hdbeta; PRESET="Android portable"; APK="$ROOT/build/aoe2hdbeta.apk"
else
  PKG=dev.j3rry.villagebuilder; PRESET="Android"; APK="$ROOT/build/villagebuilder.apk"
fi
SHOT="${1:-$ROOT/build/screen.png}"
mkdir -p "$ROOT/build"
godot --headless --path "$ROOT" --import >/dev/null 2>&1
godot --headless --path "$ROOT" --export-debug "$PRESET" "$APK" 2>&1 | grep -E "ERROR|error:" || true
ls -la "$APK"
adb install -r "$APK" | tail -1
adb shell am force-stop $PKG
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep "${WAIT:-8}"
adb exec-out screencap -p > "$SHOT"
echo "screenshot: $SHOT"
