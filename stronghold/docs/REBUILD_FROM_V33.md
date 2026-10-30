# Rebuild the visible MOD button directly from the supplied v3.3 APK

The user's uploaded `Stronghold_Mod_Menu_v3.3_Test.apk` was inspected (SHA256 `f29c2c918f9880f958f720df6844682d4824c3de16b334111abd693b3728902`, 61,220,518 bytes).

It **already contains** the `:extreme` provider, `classes2.dex` with `StrongholdModOverlay`, JNI bridge, `SHMOD033` native signature, and patched ARM64 instructions. The previous invisible button is not caused by simply omitting the menu DEX from the APK. Visibility still requires on-device validation.

## Fast rebuild without the original launcher

From the `stronghold` directory on Linux with JDK 17, Android SDK platform 35 and build-tools 35.0.0:

```bash
bash tools/rebuild_menu_from_v33.sh /private/input/Stronghold_Mod_Menu_v3.3_Test.apk /private/output/Stronghold_Menu_Fix_v3.3.1.apk
```

The script demands the **exact** hash of the tested v3.3 APK, recompiles only Android menu Java, replaces only `classes2.dex`, and resigns. Existing native patch, original `classes.dex`, `:extreme` manifest provider, original launcher and game data logic all remain untouched.

Optional signing using the **same private test key** from the previous v3.3 build:

```bash
bash tools/rebuild_menu_from_v33.sh /private/input/Stronghold_Mod_Menu_v3.3_Test.apk /private/output/Stronghold_Menu_Fix_v3.3.1.apk /private/old-test-key.pem /private/old-test-cert.der
```

**Important:** The private key is not stored in GitHub. If it is unavailable, the new build generates a different key. Android will reject an update to the installed APK with a different signer; preserve saves and data carefully before uninstalling. `allowBackup=false` means backups must be verified manually.

## What is different

- `ModInitProvider` waits for an attached Activity window and logs messages as `StrongholdModBoot`.
- The draggable MOD button uses an Android `TYPE_APPLICATION_PANEL` linked to the Extreme Activity token rather than a child of the game's decor FrameLayout. This aims to keep the button above native `SurfaceView` rendering.
- Game touch remains available outside the narrow MOD bubble because `FLAG_NOT_TOUCH_MODAL` is used.
- No system-wide overlay permission is requested.
- The underlying v3.3 cheats and associated native binaries are not changed.

## Validate

```bash
python3 tools/verify_menu_apk.py /private/output/Stronghold_Menu_Fix_v3.3.1.apk
adb logcat -c
# Launch Extreme HD in the user interface
adb logcat -d -v time | grep -E 'StrongholdModBoot|AndroidRuntime'
```

Expected Logcat sequence: Provider initialized, Extreme resumed, MOD bubble attached, MOD bubble resumed.

**The source workflow is compile-only**. It cannot sign or upload a Stronghold APK without the user's local APK and signing credentials, and it cannot confirm gameplay or menu visibility without device testing.

Do not commit the proprietary APK, native libraries extracted from it, original game data, or any private signing keys to the public repository.
