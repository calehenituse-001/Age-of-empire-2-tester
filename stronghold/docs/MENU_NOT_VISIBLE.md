# Stronghold Extreme — MOD button missing (Android)

This is a **diagnostic and bootstrap hardening** change, not a proven device fix. Code inspection alone cannot explain why the user's button did not appear. The v3.3 source commit was marked `[skip ci]`, and the latest successful GitHub Actions artifact was an **Age of Empires II launcher**, not Stronghold. Installing the AoE artifact cannot produce a Stronghold MOD button.

## Before testing

1. Build Stronghold separately from the **exact original** `Launcher-Stronghold-0.3.1-DEV.apk`; see `stronghold/docs/BUILD.md`. Do not use the `AoE2-Custom-Launcher-debug-arm64` artifact.
2. Run `python3 tools/verify_menu_apk.py path/to/Stronghold_Mod_Menu_v3.3_Test.apk` from the `stronghold` directory. A successful test confirms only packaging: `:extreme` provider, activity, DEX, JNI and patched native library.
3. Make a verified backup of game saves and original APK before replacing an installation with a differently signed APK.
4. Enter **Stronghold Crusader Extreme HD**, not Stronghold Crusader HD or Classic. The v3.3 menu does not run in the other two processes.

## Read Logcat

After starting Extreme on an Android device connected to ADB:

```bash
adb logcat -c
adb shell am force-stop org.stronghold.port
# Open the launcher and start Extreme using the phone's normal UI.
adb logcat -d -v time | grep -E 'StrongholdModBoot|AndroidRuntime|FATAL EXCEPTION|ClassNotFoundException|Unable to get provider'
```

On Windows use `findstr` instead of `grep` in the final command.

Expected order for this branch:

```text
StrongholdModBoot: Provider initialized; pid=...
StrongholdModBoot: Extreme resumed; scheduling overlay installation
StrongholdModBoot: MOD bubble attached to org.stronghold.port.ExtremeGameActivity
StrongholdModBoot: MOD bubble resumed
```

Interpretation:

- **No provider message**: wrong APK, provider declaration not loaded, or wrong Android process. First run `verify_menu_apk.py`. If it passes, inspect Logcat for provider instantiation failures.
- **Provider initialized, but no Extreme resumed**: verify which Activity actually launched and whether it uses the `:extreme` process.
- **Failed to create or display MOD bubble**: inspect the exception stack trace for UI/lifecycle/class errors.
- **All four messages but the button is invisible**: the problem is *rendering/z-order/coordinates*, not provider startup. Obtain a screenshot and Android UI hierarchy; investigate whether the game's SurfaceView sits above the Activity decor child. A separate application-attached window may be needed, but should be tested before changing input interception.
- **Button visible but diagnostics show hook unavailable**: investigate native library initialization/load bias/signature. That is distinct from the visual bubble problem.

The current source change defers creation to the attached decor view, guards against showing after pause/destroy, and logs failures. It does not add `SYSTEM_ALERT_WINDOW` and does not make cheats available for unsupported game versions.

## Runtime test checklist

- Check bubble on first entry, after leaving/re-entering Extreme, after background/resume, and after loading a save.
- Drag bubble to all edges, open/close menu 20 times, and ensure game touchscreen works with menu closed.
- Try all cheats **OFF** first; enable Gold only when the menu and native diagnostics are visible.
- Verify AI isolation and game/save stability independently. APK checks and ARM64 emulation do not establish game behavior.

No original APK or copyrighted game data should be committed to the public repository.
