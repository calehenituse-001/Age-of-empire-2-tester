# Age of Empires II — Android Custom Launcher

A native Kotlin launcher embedding the **supplied GPL Godot RTS source**, with real human-only cheat hooks and a separate declarative gameplay mod framework. It does not replace the source engine or bundle copyrighted game data. It is not the complete original Windows Genie engine or an official Microsoft release.

Target: Xiaomi 11T, Android 14, arm64-v8a, Mali-G77. Other ARM64 devices require OpenGL ES 3.0 and Android 8+. Physical-device gameplay and Mali performance still require testing with legally obtained HD data.

## Install and play

1. Download the **AoE2-Custom-Launcher-debug-arm64** artifact from [GitHub Actions](https://github.com/calehenituse-001/Age-of-empire-2-tester/actions/workflows/android.yml). Extract and install `Launcher-debug.apk`.
2. Copy your own compatible **Age of Empires II HD (2013)** game folder to a selectable location such as `Documents/AoE2HD`. The selected folder must contain `Data` and `Bin`. Definitive Edition data and Windows saves are not supported.
3. Open **GAME FILE MANAGER → IMPORT GAME FOLDER** and select it. The app copies only known required/optional files, using Android's Storage Access Framework, without unrestricted storage permission.
4. Press **PLAY GAME**. The supplied importer converts the game files on the device, with visible progress and resumable stages. Keep the conversion screen open. Missing or incompatible data is reported rather than replaced by a dummy game.
5. Select a performance preset and open the movable **CHEATS** button during play. Cheats start OFF and affect the human player only. Save/return through this menu.
6. To try the expansion: **GAMEPLAY MOD MANAGER → INSTALL MODERN ERA SAMPLE → ENABLE**. Start a new modded game, select a villager and open the **Mods** building tab. Modern Supply Depot is an additional constructible resource-dropoff/population building, not a replacement image.

Use **SAFE MODE** to launch the vanilla save profile without optional mods or cheats. Changes in mod content/order create separate save profiles; the previous profiles remain intact. Export saves/logs before uninstalling or changing debug signing keys. The reference APK's private saves are not automatically accessible.

## Implemented foundation

- Native seven-menu launcher, folder import, required-file checks, atomic config, crash log, save/log export.
- Embedded Godot startup and existing touch controls, original data converter and simulation.
- LOW 70%/30 FPS, BALANCED 85%/60 FPS, HIGH 100%/60 FPS; advanced 50–100% resolution, bounded texture caches, reduced cosmetic effects, FPS/memory diagnostics.
- Four resource cheats, income factors, independent construction/training/research/upgrade rules and population override. Real payment receipts prevent free purchases from producing refund money after disabling a cheat.
- ZIP mod install, selection/order/dependency/ID validation, deletion of disabled mods, reversible registry additions, per-mod-set saves and save backups.
- A genuine **buildings.add** v1 sample. Custom units, civilizations, technologies, executable mod scripts and combat multipliers are **not implemented**.
- CI compilation, JVM tests, Godot simulation tests, APK inspection and an Android emulator startup test. Check the workflow result for the validation status of each commit.

## Documentation

- [Source analysis and integration decisions](docs/SOURCE_ANALYSIS.md)
- [Mod format and supported fields](docs/MOD_FORMAT.md)
- [Build instructions and storage](docs/LAUNCHER_BUILD.md)
- [Progress, test scope and remaining work](docs/PROGRESS.md)
- [Measured APK build report](docs/BUILD_REPORT_2026-10-30.json)
- [Import rollback and recovery](docs/IMPORT_STABILITY.md)

GPL-3.0-or-later; retain [LICENSE](LICENSE) and [NOTICE](NOTICE.md). Godot is MIT. Game data belongs to its respective owners and must not be committed, downloaded by the launcher or redistributed with the APK.
