# Asfatre v1.3 — integrated Advanced Cheat & Mod APK (experimental)

## Build performed

The user's uploaded `LauncherStrongholdAsfatre-V1.3.apk` was modified in a local model workspace. The proprietary APK, extracted game libraries, and private signing key are **not committed to GitHub**.

- Input SHA256: `92f90a525716e6bc9d34bdd345a154780477fa1e0af5c0f16dfbd6f8be3629fd`
- Output APK: `Stronghold_Asfatre_v1.3_Advanced_Mod_Test.apk`
- Output SHA256: `2f1e5c6b217c5380ce1b03f3725f666d44abf3e3b9935f4203646aefb16aaf6d`
- APK Signing Scheme v3: verified.
- Signer certificate SHA256: `2ff44bcd48ff2c5bd12c40dd47786c2c6528545dfb9e4f837717ec85253aec89`
- APK ZIP CRC and ELF `readelf` structural checks: passed.
- VersionName remains `1.3-stable`, versionCode `36`, package `org.stronghold.port`.

## Actual integration steps

1. Disassembled the owner's original `classes.dex` with baksmali.
2. Found that `CheatMenu.lambda$new$2$org-stronghold-port-CheatMenu(View)` is **the expand-button handler**, whereas `lambda$new$0...` is the collapse handler. The latter was deliberately left unchanged.
3. Replaced the expand-button handler with a call to `AdvancedCheatPanel.openForView(View)`, reassembled with smali, and validated DEX magic/integrity.
4. Added compiled secondary DEX from the GitHub Java source build, including `AdvancedCheatPanel`, `ModSettings`, and `StrongholdNativeBridge`.
5. Preserved the vendor's original v1.3 native customizations, including an extra RX ELF segment at VA `0x3c84000`, while reusing the compiled native v3.3 hook payload at the **nine byte-for-byte verified ARM64 hook sites**. The new `libstronghold.so` SHA256 is `9a117e5b7a9115a38fe36fb339b16851cf82dc49bd119d7ffbf6aa2f2495d8ac`.
6. Added the JNI runtime library from the original v3.3 test APK (`libstronghold_mod_runtime.so`). No new permission and no ContentProvider overlay bootstrap are required.
7. Preserved 16 unaffected entries, original manifest, game data import, other game libraries and resources byte-for-byte. Signed and verified the resulting APK.

## Testing status

| Test | Result |
|---|---|
| Java panel compilation in GitHub Actions | PASS |
| Smali assembly of v1.3 primary DEX | PASS |
| Native nine-site version and ELF layout checks | PASS |
| Vendor native ELF segment retained | PASS |
| APK signing and ZIP CRC | PASS |
| Installation on Android device | **NOT TESTED** |
| Owner's Cheat button opens the new dialog | **NOT TESTED** |
| Gold / inventory / Peasant gameplay modifications | **NOT TESTED** |
| AI economy isolation | **NOT TESTED** |
| Save/load safety, crash/ANR, frame rate | **NOT TESTED** |

**Important:** passing static checks does not establish that the patched game loads, runs, or modifies its economy correctly. The native payload was compiled for v3.3 and transplanted based on verified machine-code bytes; its assumptions about runtime pointer layout and owner identification must be tested with the vendor's v1.3 game. Do not use on important saves.

## Test steps

Back up saves and data before changing APK signatures. The mod signer matches the previous ChatGPT mod v3.3.1/v3.3.2 test key, **not** the Asfatre vendor certificate. If Android refuses an update, do not uninstall until backup is verified.

Run **Stronghold Crusader Extreme HD**, tap the owner's original **Cheat** control, and look for a dialog titled `STRONGHOLD • CHEAT & MOD`. There is **no new floating MOD icon**.

Try the native Alt+X command, then Unlimited Gold ON → Apply, recruit one Arabian soldier with sufficient initial Gold and Peasant, and compare Gold on the right-hand book. Use the Diagnostics category to identify `seen`, `applied`, and `denied`. Test OFF as control before other features. Check AI independently.

## Source

- [AdvancedCheatPanel.java](AdvancedCheatPanel.java)
- [patch_cheat_lambda.py](patch_cheat_lambda.py)
- [patch_extreme_v13.py](patch_extreme_v13.py)
- [build_native_v13.sh](build_native_v13.sh)
- [Integration checklist](README.md)

The exact donor-based local packaging script and native manifest have been made available to the user separately in the conversation development ZIP, not copied into the public repository.
