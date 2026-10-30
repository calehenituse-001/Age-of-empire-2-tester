# Source analysis — 30 October 2026

## Evidence and scope

The repository initially had only a README. The supplied `AoE2HDBeta-source(1).zip` (884,539 bytes; SHA-256 `b1a42902fdfc340e0dd1edc9d8eca9420fb56a36db51e0ea922ab746d669e013`) contains a complete Godot project, GDScript importer, tests, tools, GPL license and notice. It contains no legally distributable original HD assets. The attached modder APK is a reference binary; it is not copied into the launcher. Modder-only binary changes are not assumed to be present in the supplied source.

The source is a **custom Godot RTS implementation consuming AoE2 HD data**, not the original Windows Genie source. No bespoke C/C++ engine source, JNI library or vendor GPU backend is supplied. We retain this engine and add a native Kotlin host using the official matching Godot 4.7.2 AAR (`libgodot_android.so`). The original project already selects GL Compatibility.

| System | Actual source | Integration |
|---|---|---|
| Startup | `project.godot`, `boot.gd`, `Main` | Kotlin GameActivity embeds Godot, bridge passes paths/session options; boot converts user data before Main |
| Rendering | Godot GL Compatibility; TileMapLayer terrain, Sprite2D units/buildings, CanvasLayer HUD | OpenGL ES 3, original 2D isometric view; no Vulkan addition |
| Asset data | `GameData`, `Assets`, JSON manifest/units/terrain and extracted PNG/WAV/MP3 | App-private imported data; separate validated mod sprite map; original files untouched |
| Raw game import | `scripts/importer/`: DAT schema/reader, DRS, SLP, palette, PE strings, audio/terrain extraction | SAF copies required inputs; existing threaded importer runs resumable conversion into staging |
| Initialization | `Rules`, `Assets`, `Sfx` autoloads, then `Main` | AppRuntime runs before registries; fail closed if mod/data preparation fails |
| Input | `RtsCamera`, `Controller`, `Hud`, touch selection/placement and gestures | Preserve original controls; HUD blocks touches handled by overlay |
| Human economy | `GameMap.stock`, `can_afford`, `pay`, `add_resource`, relic/barter paths | Owner-scoped cheat policy, real payment receipts |
| AI economy | `Rival.stock`, `_pay`, `FoeBuilding` | Separate; no human bonus injected. Shared construction code receives team guard |
| Buildings/units | `Defs.BUILDINGS`, `Rules.units`, `TechState`, `Building`, `Mob` and subclasses | New building adapter clones a supported base row under a unique ID, then registers definition and sprite |
| Research | `Rules.techs/effects`, `TechState`, Building progress | Upgrade effect type 3 distinguished from other research; no globally changed duration |
| Simulation | `GameMap._process/_step`, explicit elapsed-time update paths | Original timing retained; FPS cap does not multiply simulation speed |
| Saves | `SaveGame` version 6 JSON | Atomic writes, previous copy, payment receipts, content fingerprint, separate profiles |
| Logging | `GameLog` custom Logger and Android exit history | Existing logging retained; native crash log and engine log are exportable |

## Limits that matter

This source has its own mechanics and coverage. It must not be described as full original-game compatibility. PC save formats are not supported. The source has offline rival/raid modes, no implemented multiplayer transport or allied-player simulation. Cheat guards explicitly reject non-human owners and live non-offline multiplayer peers; an eventual multiplayer implementation needs further validation.

`Rules.units` is data-driven, but `Mob` subclasses, production buttons, technology chains, civilization trees and sprite animation wiring are not a general-purpose runtime plugin API. Therefore v1 accepts only `buildings.add`, with a constrained adapter for non-combat economic buildings. It does not pretend arbitrary content JSON creates usable new military units or civilizations. Broader registry adapters, prerequisite graphs, production rules, directional animation states and AI planning remain future engine work.

The sample uses new ID 900001, its own original sprite, real costs/time/HP/population/dropoff behavior and existing construction rendering. A supplied compatible HD data set is still needed to exercise conversion, full rendering and complete gameplay on the Xiaomi.

## Storage and resource decisions

User data lives below app-private `files/AgeOfEmpires2`: Launcher, GameData/raw, GameData/importing, GameData/imported, Mods, Cheats, Config, Saves and Logs. Raw and converted data stay outside the APK. Staged copies preserve the preceding complete import on failure. Save backups happen before mod-selection changes and new games; mod fingerprints include ordered manifests, content and sprites.

Performance profiles change rendering resolution, frame cap, cosmetic effects and cache ownership budgets only. The texture LRU retains weak references to textures still used by live nodes to avoid duplicate uploads. Animation cache entries no longer pin all textures through the original manifest. CPU terrain masks are released after generation. Budgets do not cap textures owned by live sprites/TileSets; peak importer and GPU memory require real-device profiling. Existing sprite batching/draw calls are not claimed to be measurably faster without a benchmark.

## Primary platform references

- [Godot Android library and embedding lifecycle](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_library.html)
- [Android Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)

Godot is hosted in a separate Android process because one engine instance is supported per process. Both activities handle listed configuration changes; the game stays landscape. No root, accessibility or system overlay permission is used.
