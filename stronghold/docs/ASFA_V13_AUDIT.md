# Audit APK Asfatre v1.3 — 30 Oktober 2026

**Sumber:** APK yang diunggah pengguna, `LauncherStrongholdAsfatre-V1.3.apk`. Analisis statis saja; tidak ada instalasi atau pengujian gameplay.

## Identitas APK

| Properti | Original 0.3.1-DEV | Asfatre v1.3 |
|---|---|---|
| SHA256 APK | `92dc03003274dcac024d63a66e61fab75f9f5b26bb3bcd01c89f935bfa22d252` | `92f90a525716e6bc9d34bdd345a154780477fa1e0af5c0f16dfbd6f8be3629fd` |
| Package | `org.stronghold.port` | sama |
| versionName | `0.3.1-DEV` | `1.3-stable` |
| versionCode | 28 | 36 |
| minSdk / targetSdk | 28 / 28 | 28 / 28 |
| Signed certificate SHA256 | `2370b514733baef3a7ee8c99773a1921e5d647ce52d3170a49f0680e058ecc00` | **sama** |

Package dan signing certificate sama dengan APK launcher original sehingga secara identitas mendukung update original (dengan syarat Android menerima update). APK mod v3.3.x menggunakan signer berbeda; **jangan uninstall mod untuk menggantinya sebelum backup save benar-benar diverifikasi** (`allowBackup=false`).

## Perubahan APK

- `classes.dex`: original 250,712 byte; v1.3 256,268 byte. Tidak ada `classes2.dex` pada APK v1.3.
- `libstronghold.so` Extreme: original 51,493,592 byte; v1.3 51,495,308 byte.
- `libstronghold_classic.so` Crusader HD: original 55,064,096 byte; v1.3 55,067,020 byte.
- `libstronghold_sh.so` Stronghold HD: original 44,818,528 byte; v1.3 44,826,700 byte.
- `AndroidManifest.xml`, `resources.arsc`, dan sumber ikon/donasi juga diperbarui.
- Ketiga `.so` berbeda tetapi perubahan pada byte di lokasi file awal terbatas: Extreme dan Crusader HD masing-masing 124 byte, Stronghold Classic 108 byte, ditambah data/kode di area akhir ELF. Ini tidak berarti keseluruhan ABI atau perilaku pasti kompatibel.

## Cheat bawaan yang benar-benar teridentifikasi

DEX menambahkan kelas:

- `Lorg/stronghold/port/CheatMenu;`
- `Lorg/stronghold/port/CheatMenu$Listener;`
- `GameActivity.queueCheat(char)`
- `GameActivity.updateCheatMenu()`
- field `GameActivity.cheatMenu`, `GameActivity.cheatInGame`

String UI: `Cheat`, `Cheat Alt+`, `Tampilkan menu cheat`, `Sembunyikan menu cheat`.

`CheatMenu.<clinit>` menginisialisasi array `KEYS` `char[2]` dari payload DEX: `0x0058, 0x0051`, yaitu **X dan Q**. Ini menunjukkan dua shortcut **Alt+X** dan **Alt+Q** di menu, bukan tombol Unlimited Gold/Wood/Weapons/Armor yang berdiri sendiri.

`GameActivity.queueCheat` melakukan validasi input karakter dan mengirim perintah melalui metode native `nativeCommand`. Karena menu terintegrasi langsung ke `GameActivity`, jalur ini lebih tepat dijadikan fondasi untuk Mod Menu kita daripada `ContentProvider` eksternal dari prototipe v3.3.

Sumber resmi Firefly mendokumentasikan Alt+X untuk Gold/Popularity. Untuk Alt+Q, catatan populer tentang time compression berbeda dengan manual Stronghold Crusader HD yang menyebut shortcut screenshot. **Efek sebenarnya pada v1.3 perlu diuji di HP**. Demikian juga apakah mode cheat perlu diaktifkan terlebih dahulu.

## Kandidat hook v3.3 vs v1.3

Pemeriksaan empat byte opcode ARM64 pada sembilan alamat VA native v3.3 menunjukkan **semuanya identik** antara original 0.3.1-DEV dan Asfatre v1.3:

`0x2520AEC` regular recruit; `0x2521510` Arab recruit; `0x2C77090` market; `0x2C2C7C8` trade; `0x29D1D90` siege; `0x297F2A8` transfer; `0x29BCF80` ally gold; `0x2C55970` inventory debit; `0x20888A0` peasant rate.

Artinya alamat ini **masih kandidat untuk diverifikasi**, tetapi tidak membuktikan bahwa patch lama aman untuk v1.3: ELF v1.3 sudah memuat segment tambahan dan branch patch pada `stronghold_display_world_begin`, `stronghold_display_ui_end`, serta `stronghold_touch_*`. Installer/payload lama memverifikasi hash original dan tidak akan menerima v1.3 tanpa adaptasi yang benar. Jangan menumpuk patch ELF atau mengganti versi v1.3 dengan library 0.3.1 lama.

## Arah pengembangan

1. Uji APK Asfatre v1.3 asli: apakah tombol `Cheat` muncul, terbuka, dan Alt+X menaikkan Gold. Catat posisi UI dan langkah.
2. Untuk Mod Menu baru, integrasikan tombol/opsi ke `GameActivity` dan `CheatMenu` yang sudah terbukti dipaketkan di DEX. Hindari bootstrap melalui provider dan jendela sistem yang belum teruji.
3. Implementasi Unlimited Gold/resource/weapon/armor/peasant player-only tetap memerlukan hook terpisah, dengan validasi owner dan AI isolation pada **library v1.3**.
4. Pertahankan batas pasukan bawaan dan multiplier maksimum ×100.
5. Wajib build + tes perangkat Android sebelum mengklaim cheat berhasil.

**Bukan APK mod baru**: laporan ini adalah audit file yang diunggah. Tidak memuat file game proprietari atau key signing.
