# Build and storage

Pinned toolchain: JDK 21, Gradle 8.14.3, Android Gradle Plugin 8.10.1, Kotlin 2.1.21, Android SDK/build-tools 36, Godot **4.7.2 stable** editor and Maven AAR. Minimum Android 26; target 35. Default ABI arm64-v8a. Emulator tests override with `-PtestAbi=x86_64`.

```sh
export ANDROID_HOME=/path/to/android-sdk
export GODOT_BIN=/path/to/Godot_v4.7.2-stable_linux.x86_64
sdkmanager 'platforms;android-36' 'build-tools;36.0.0'
python3 tools/package_sample.py
python3 tools/validate_godot.py
gradle :Launcher:testDebugUnitTest :Launcher:lintDebug :Launcher:assembleDebug
python3 tools/report_apk.py Launcher/build/outputs/apk/debug/Launcher-debug.apk
```

`preBuild` imports the Godot project and exports a PCK into generated Android assets. This does not require a Godot Android export template: Gradle embeds the official AAR. The PCK excludes proprietary `assets/aoe`, development tests and build files. The APK includes engine runtime, code, schema and small original sample artwork only. Do not add extracted game data to source or build inputs.

The GitHub workflow installs tools, caches Gradle dependencies, runs both test layers and lint, signs a debug APK and uploads it with measured size/hash/ABI/permission reports. A second job installs and boots the native app plus real Godot in an Android 14 x86_64 emulator without game data. This verifies startup plumbing, not ARM64 Mali gameplay. Debug builds from different signing keys may require uninstall; export saves before doing so. Do not use a debug key for production distribution.

`artifacts/build-report.json` is generated from the actual APK. A complete official Godot runtime is around the 30 MB target; the exact report is authoritative. A smaller custom engine would need a separately reproducible build and runtime verification; necessary engine components have not been removed merely to satisfy a size estimate.

App-private layout: `files/AgeOfEmpires2/{Launcher,GameData,Mods,Cheats,Config,Saves,Logs}`. Data uses copy-on-import, so keep enough free space for raw data, converted assets, staging and previous imports. Large first-time conversion is CPU/memory intensive and remains foreground. A cancellation resumes completed stages next time. No network asset downloader or all-files permission exists.

`Saves/vanilla` and `Saves/mods-<content hash>` contain manual/autosave slots; `.previous` retains the preceding slot. `Saves/backups` contains ZIP snapshots before mod changes/new games. The launcher exports saves and logs via SAF. Original standalone Godot/reference-APK private saves are not automatically migrated; do not uninstall the reference app expecting migration.

## Xiaomi acceptance test still required

Import known-compatible HD data, capture importer logs, play 15 minutes on each preset, confirm stable frame pacing/temperature/memory, test all four resource switches with a rival, build/train/research toggles and OFF transitions, save/relaunch, enable/build/damage/delete sample depot, then disable it and confirm vanilla profile restoration. Test dragging the overlay and touch selection at each resolution. Compare AI timing at 30/60 FPS and verify no simulation regressions. Record renderer/GPU/driver and game-data version. No performance claim is validated until these results exist.
