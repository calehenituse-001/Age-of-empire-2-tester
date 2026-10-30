# Building the APKs from source

This archive/repo holds the source only: no game files, no extracted assets, no Godot binaries, no APKs. The game's graphics, sounds and data
come from your own copy of Age of Empires II HD (2013 edition, "AoK HD.exe"); they are never part of the source.

## Software needed

| what | version used | notes |
|---|---|---|
| Godot Engine | 4.7.2 stable (standard build, not .NET) | https://godotengine.org/download/archive/4.7.2-stable/ |
| Godot export templates | 4.7.2 stable (`Godot_v4.7.2-stable_export_templates.tpz`) | Editor > Manage Export Templates > Install from file; or unzip into `~/.local/share/godot/export_templates/4.7.2.stable/` |
| JDK | OpenJDK 21 | e.g. `/usr/lib/jvm/java-21-openjdk-amd64` |
| Android SDK | command-line tools, platform-tools (adb), platform `android-34`, build-tools `34.0.0` (36.1.0 also present) | e.g. `/opt/android-sdk`; accept the licences with `sdkmanager --licenses` |
| debug keystore | any | `keytool -genkeypair -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"` |
| Python 3 + Pillow + NumPy | 3.12, Pillow 12, NumPy 2 | only for the optional `tools/*.py` (the portable version does its import in GDScript on the device) |

No NDK, no Gradle: the export uses the prebuilt templates (`gradle_build/use_gradle_build=false`), arm64-v8a only.

### Godot editor settings (Editor > Editor Settings > Export > Android, or `~/.config/godot/editor_settings-4.7.tres`)

```
export/android/android_sdk_path = "/opt/android-sdk"
export/android/java_sdk_path = "/usr/lib/jvm/java-21-openjdk-amd64"
export/android/debug_keystore = "/home/<you>/.android/debug.keystore"
export/android/debug_keystore_pass = "android"
```

## Portable version ("AoE2HDBeta", package co.domotix.ao2hdbeta, ~29 MB)

Needs nothing from the game at build time.

```
mkdir -p godot_game/build && touch godot_game/build/.gdignore
godot --headless --path godot_game --import
godot --headless --path godot_game --export-debug "Android portable" build/aoe2hdbeta.apk
adb install -r godot_game/build/aoe2hdbeta.apk
```

(`tools/tablet.sh portable` does these, launches the app and takes a screenshot.) On first start the app asks for "all files access", then for the game
folder (the one that contains `Data` and `Bin`) and imports it. Files it needs (~190 MB) are listed in `docs/PORTABLE.md`.

## Development version (package dev.j3rry.villagebuilder, ~137 MB)

Bundles the game data, so it must be extracted first, from your install (`GAME=/path/to/AoE2HD`):

```
python3 -I tools/import_dat.py --game $GAME --openage <openage>/src --out godot_game/assets/aoe/data   # rules (needs openage's source, GPLv3)
python3 -I tools/extract_aoe_godot.py $GAME godot_game/assets/aoe
python3 -I tools/extract_units.py --game $GAME
python3 -I tools/extract_terrain.py --game $GAME
mkdir -p godot_game/build && touch godot_game/build/.gdignore
godot --headless --path godot_game --import
godot --headless --path godot_game --export-debug "Android" build/villagebuilder.apk
```

Simpler: run the portable app's importer on a PC (`tests/importer.tscn`, see below) and copy `~/.local/share/godot/app_userdata/<project>/gamedata/`
into `godot_game/assets/aoe/`.

## Tests (no device needed)

```
godot --headless --path godot_game res://tests/<name>.tscn
```

rules, terrain, civs, garrison, gates, monks, lasso, sim, rival (about 15 min), logs, inflate, dat, rulesbuild, extract, importer, wizard.
Tests that need the game use `GAME=/path/to/AoE2HD` (default /home/j3rry/AOE); `AOE_DATA=imported` makes the game tests use the imported copy.

## Layout

- `godot_game/` the Godot project (scripts, scenes, `export_presets.cfg` with both presets, `data/dat_schema.json`)
- `godot_game/scripts/importer/` the on-device import (ports of the Python tools)
- `tools/` Python tools and `tablet.sh` (build, install, launch); `docs/` notes on formats, rules, monks, gates, lasso, logs, portable
