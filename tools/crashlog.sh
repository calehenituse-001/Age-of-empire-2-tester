#!/usr/bin/env bash
# After a crash or freeze on the tablet: how the app last ended, the native crash report and the game's own log.
# Usage: tools/crashlog.sh [output_dir]     (default /tmp/aoa_crash)
set -uo pipefail
PKG=dev.j3rry.villagebuilder
OUT="${1:-/tmp/aoa_crash}"
mkdir -p "$OUT"
echo "== how the app last ended"
adb shell "dumpsys activity exit-info $PKG" | sed -n 1,16p | cut -c1-200
echo "== native crash (dropbox)"
adb shell "dumpsys dropbox --print data_app_native_crash" | sed -n 1,30p | cut -c1-200
echo "== the game's log (user://logs), last status lines and slow frames"
adb shell "run-as $PKG ls -la files/logs" 2>/dev/null | tail -8
adb shell "run-as $PKG cat files/logs/godot.log" > "$OUT/godot.log" 2>/dev/null
grep -E "^\[status\]|^\[slow\]|ERROR|SCRIPT ERROR" "$OUT/godot.log" | tail -25 | cut -c1-260
echo "== autosave and save copied to $OUT"
adb shell "run-as $PKG cat files/autosave.json" > "$OUT/autosave.json" 2>/dev/null
adb shell "run-as $PKG cat files/save.json" > "$OUT/save.json" 2>/dev/null
adb pull /data/tombstones/tombstone_02 "$OUT/tombstone.txt" >/dev/null 2>&1 || true
ls -la "$OUT"
