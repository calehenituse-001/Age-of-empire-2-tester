# Stronghold v3.3.2: MOD button diagnostic APK (30 Oct 2026)

## Why this build exists

The user supplied a new screenshot from Extreme gameplay: the MOD button is not visible after v3.3.1. The previous APK was inspected directly and its secondary DEX, ContentProvider manifest entry, and native patch are all present, so file omission has not been shown to be the problem. The lifecycle path and display placement still need an Android device observation.

## Changes

- Show one-time Android Toast `STRONGHOLD MOD v3.3.2 loader aktif` on the first Activity resume when `ModInitProvider` receives the Extreme activity. This is **diagnostic** and does not prove native gameplay hooks work.
- Make the MOD bubble opaque yellow with dark 17sp text and start nearer the center-left of the screen for better visibility.
- Use app-attached `TYPE_APPLICATION_PANEL` first, and if that attach fails, log the error and fall back to an Activity decor FrameLayout child.
- Keep existing draggable button/menu and game JNI/native engine unmodified. **Do not assume this cures invisible overlay in every device.**

## Exact build and verification

- Source Java/DEX check: [Stronghold CI run #41081376899](https://github.com/calehenituse-001/Age-of-empire-2-tester/actions/runs/41081376899), **success** on source commit `51a8973727795801e268c5f6576233231b4cc2c4`.
- Source input APK: user's `Stronghold_Mod_Menu_v3.3.1_Menu_Fix.apk`, signed by private v3.3.1 test key.
- Replaced **only `classes2.dex`** (27,760 bytes) in ZIP entries; original `classes.dex`, AndroidManifest, native libraries, assets and data remain byte-identical.
- Result filename: `Stronghold_Mod_Menu_v3.3.2_Diagnostic.apk`
- Result SHA256: `d32fae725d320d916eefca06753e5096e1f89f38975302f91ede9a94f3098a8a`.
- Zip CRC: PASS; original non-signature entries preservation: PASS.
- Signing: APK Signature Scheme v3 PASS; signed with the **same** local test key as the prior v3.3.1 build.
- Signer certificate SHA256: `2ff44bcd48ff2c5bd12c40dd47786c2c6528545dfb9e4f837717ec85253aec89`.

## On-device test (without ADB)

1. **Back up saves**, then install v3.3.2 as an update over **v3.3.1**, not over v3.3 or original (different signing key). If Android reports signature conflict, do not uninstall until backups are verified.
2. Launch **Stronghold Crusader Extreme HD**.
3. Watch for Toast **STRONGHOLD MOD v3.3.2 loader aktif** during activity entry, then look for the bright yellow MOD button near the middle-left.
4. Report the four-way observation:
   - Toast and button: initialization + rendering appear to work; test menu opening next.
   - Toast but no button: provider executed but overlay was hidden, off-screen, or failed after resume. Get `adb logcat -d | grep StrongholdModBoot` if possible.
   - No Toast and no button: could be the wrong installed APK or provider/activity initialization failure. On-device logcat would discriminate.
   - Button but no Toast: possible clipped/missed Toast (not sufficient to infer provider failure).

**Android runtime, cheat efficacy and AI isolation remain unverified.** Keep all cheats OFF until button and diagnostic panel are functioning.

Do not commit APK, proprietary game files, or private signing key to this public repository.
