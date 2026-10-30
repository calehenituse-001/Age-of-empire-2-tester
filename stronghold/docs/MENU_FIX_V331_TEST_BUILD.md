# Stronghold Mod Menu v3.3.1 — APK test build audit

Date: 30 October 2026. Source: `StrongholdModOverlay.java` and `ModInitProvider.java` from the merged MOD bootstrap fixes. Java / DEX build: GitHub Actions `Stronghold menu source check (no APK)`, run 41079113005 (successful). APK repack and signing were completed in a separate local workspace from **the user's uploaded** `Stronghold_Mod_Menu_v3.3_Test.apk`. The modded APK itself was not committed to GitHub.

## Input APK

- File SHA256: `f29c2c918f9880f958f720df6844682d4824c3cde16b334111abd693b3728902`
- Size: 61,220,518 bytes
- Package: `org.stronghold.port`; version `0.3.1-DEV`; process `:extreme`.
- The original uploaded APK already contained the provider, Java secondary DEX and native Stronghold v3.3 hook. Missing menu therefore cannot be attributed simply to absent menu DEX.

## Resulting test APK

- Suggested filename: `Stronghold_Mod_Menu_v3.3.1_Menu_Fix.apk`
- SHA256: `e5c863394c00731f63793e892ee31a427dff833eb2cfb6e45bb8022c266edd0a`
- Signed with a new local **test** key; certificate SHA256 `2ff44bcd48ff2c5bd12c40dd47786c2c6528545dfb9e4f837717ec85253aec89`.
- `apksigner` verifies signature scheme v3; package targets minSdk 28 and targetSdk 28.
- APK ZIP CRC/integrity passed.
- `classes2.dex` grew from 24,828 to 26,920 bytes.
- All non-signature ZIP entry contents except `classes2.dex` remain identical to the user's v3.3 APK; specifically unchanged: original `classes.dex`, `AndroidManifest.xml`, `libstronghold.so`, other native libraries, resources and game assets.
- Existing `SHMOD033` patch remains. All gameplay cheats are **unchanged**.

## What changed in menu

1. Activity lifecycle bootstrap defers until window decor is attached and writes diagnostic Logcat tag `StrongholdModBoot`.
2. The draggable menu trigger now uses an app-attached `TYPE_APPLICATION_PANEL` to render above the native SurfaceView, without system overlay permission.
3. Retains ON/OFF settings and JNI; no additional game cheats have been added.

## Test status

- Compile: PASS.
- Secondary DEX repack: PASS.
- ZIP data preservation: PASS.
- APK signature verification: PASS.
- **Android installation: NOT TESTED.**
- **Button visibility: NOT TESTED.**
- **Player-only cheats and AI isolation: NOT TESTED.**

### Important installation warning

The new APK is signed with a **different key** from v3.3. Android will normally refuse to install it as an update. Back up your save and data files before uninstalling anything. The original app has `allowBackup=false`. Never assume an uninstall is safe until a complete backup has been verified. Source code allows signing with an existing key if the user still has the previous v3.3 private signing kit.

If the button is still absent, use Logcat tag `StrongholdModBoot` to distinguish provider/startup errors from UI visibility issues.

This test APK was given to the user in the conversation file attachment, not uploaded to the public repository.
