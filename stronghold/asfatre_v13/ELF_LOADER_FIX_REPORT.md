# Asfatre v1.3 — ELF loader fix for Advanced Mod APK

Reported by user on 31 October 2026: launcher shows

```text
dlopen failed: ... libstronghold.so: dynamic section has invalid offset:
0x30829b0, expected to match PT_DYNAMIC offset: 0x307e9b0
```

## Root cause (confirmed by binary comparison)

The **previous native transplant script** injected 0x4000 bytes at file offset `0x3044090` into the vendor ELF, but it updated only `PT_LOAD` file offsets. It neglected other file-backed program headers whose file contents moved.

| ELF program header | Previous incorrect p_offset | Correct p_offset |
|---|---|---|
| `PT_DYNAMIC` (index 5) | `0x307e9b0` | `0x30829b0` |
| `PT_GNU_RELRO` (index 6) | `0x3044090` | `0x3048090` |

Both corrections are necessary. The screenshot error identifies the PT_DYNAMIC inconsistency specifically. The old base v3.3 patcher `stronghold/tools/patch_extreme.py` shifts every program header's offset; the separate *Asfatre donor transplant* logic had this bug. This should not be 'fixed' by changing the game data, bypassing linker validation, or disabling cheat UI.

## Fixed build

A corrected APK was created from the user's exact uploaded experimental APK:

- **Input**: `Stronghold_Asfatre_v1.3_Advanced_Mod_Test.apk`
- Input APK SHA256: `2f1e5c6b217c5380ce1b03f3725f666d44abf3e3b9935f4203646aefb16aaf6d`
- Input `libstronghold.so` SHA256: `9a117e5b7a9115a38fe36fb339b16851cf82dc49bd119d7ffbf6aa2f2495d8ac`
- Output: `Stronghold_Asfatre_v1.3_Advanced_Mod_ELF_Fix_v1.0.apk`
- Output APK SHA256: `8688f811c033d2d1d2c8e8c300ca4e7b48dbefb486e36c069a361804bd44a188`
- Fixed `libstronghold.so` SHA256: `3cd2def5241b2fc7e6f8aba8e2bfe5af999bfe67a5ee7e53e8ae4ba16720dfed`
- ELF binary differences from input: **exactly three bytes**, all in program-header `p_offset` fields at library file offsets 353, 354 and 409. No executable instructions, native hook payload, game content, DEX, resources, or manifest changed.
- ZIP CRC passed; unchanged APK entry bytes verified; `readelf -lW` and `readelf -dW` both parse corrected library. The dynamic section now reports file offset `0x30829b0`.
- APK Signature Scheme v3 verified by apksigner. Certificate SHA256: `2ff44bcd48ff2c5bd12c40dd47786c2c6528545dfb9e4f837717ec85253aec89`, **identical to prior experimental Asfatre mod APK**.

File was delivered to user directly in chat; **not published to public GitHub**, since it contains proprietary game code/assets.

## Next steps and limitations

The user should be able to install this APK as an **update** over the earlier Asfatre Advanced Mod test APK (same Android package, same versionCode 36, same signing certificate); if Android refuses, preserve saves and do not uninstall without verified backup.

This fixes the specific malformed **linker metadata** that caused `dlopen` to abort. It **does not prove** successful Android gameplay, Mod Menu visibility, Unlimited Gold behavior, AI isolation, or native hook stability.

Use `python3 asfatre_v13/repair_v13_elf_headers.py extracted-broken-libstronghold.so fixed-libstronghold.so` to reproduce the bounded file-level correction. It checks exact input/output hashes and validates every LOAD/DYNAMIC/GNU_RELRO mapped header. Later patchers must validate all file-backed program headers after inserting bytes—not only PT_LOAD.

If additional errors appear after this fix, capture the exact displayed message or Logcat and treat it as a separate issue.
