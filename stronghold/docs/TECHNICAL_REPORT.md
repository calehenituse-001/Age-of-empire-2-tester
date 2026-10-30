# Laporan teknis — Stronghold Mod Menu v3.3

Tanggal build: 30 Oktober 2026. Target: Stronghold Crusader Extreme dalam launcher asli 0.3.1-DEV, ARM64 Android 9+. Target pengguna Xiaomi 11T Android 14 belum tersedia untuk pengujian.

## Status hasil

APK bertanda tangan telah dibangun. Menu Java, konfigurasi lokal, provider lifecycle, JNI, dan sembilan detour native telah diintegrasikan. Status fitur yang terpasang adalah **Implemented but runtime-untested**. Kode hasil patch diuji melalui emulasi instruksi ARM64; tidak ada sesi Android nyata, pengukuran FPS, atau bukti AI isolation gameplay. Jangan menafsirkan label ON atau counter applied sebagai sertifikasi bahwa seluruh perilaku game sudah benar.

## Audit input dan pemetaan launcher

Manifest asli: package `org.stronghold.port`, versionName `0.3.1-DEV`, versionCode `28`, minSdk/targetSdk `28`, ARM64, OpenGL ES 3. Original application memakai `allowBackup=false`, `extractNativeLibs=true`, dan `debuggable=true`. Permissions, activities, data-import logic, dan touch-control bytecode dipertahankan.

Pemetaan dari DEX `GameFiles.library` dan activity asli:

| Library | Game | Proses |
|---|---|---|
| `libstronghold.so` | Stronghold Crusader Extreme HD | `:extreme` |
| `libstronghold_classic.so` | Stronghold Crusader HD | `:classic` |
| `libstronghold_sh.so` | Stronghold Classic HD | `:stronghold` |

`GameActivity` membuat SurfaceView dalam FrameLayout. Tidak ditemukan penggunaan `setZOrderOnTop` dalam jalur yang diperiksa. Menu ditambahkan sebagai child kecil pada decor activity, di atas hierarchy game, dan dinaikkan kembali saat resume/layout. Tidak ada loop frame atau permission overlay sistem. Drag dijepit ke visible frame; koordinat relatif disimpan. Dialog menyediakan scroll, kategori, switch 18sp, input desimal, Apply & Save, reset, dan diagnostics. Keterlihatan aktual terhadap driver Mali, input multitouch, keyboard, rotasi, serta perubahan scene masih memerlukan perangkat.

Hashes lengkap input ada di [original_audit.json](original_audit.json); hasil mod dan APK di [patch_manifest.json](patch_manifest.json) dan [apk_audit.json](apk_audit.json). Sertifikat hasil signing ada di [signature_verification.txt](signature_verification.txt).

| Input | SHA256 |
|---|---|
| Original APK | `92dc03003274dcac024d63a66e61fab75f9f5b26bb3bcd01c89f935bfa22d252` |
| Original Extreme library | `c93f34086c06bf7b49530b3297f4aba51ef7b59d95a9aff3661bfb090c1a1539` |
| Extreme EXE untuk audit | `0c90204f7bf622b768cc1fd9ebc0ec5c6cf8e60ea84911c0fdc7ffcbb2119ba8` |

APK tidak memuat tambahan data game dari EXE/ZIP pengguna. Library asli lain, original classes.dex, resources, dan aset asli dipertahankan byte-for-byte; perbandingan otomatis memeriksa seluruh entry yang tidak dikecualikan secara eksplisit.

## Koreksi penelitian mode dan identitas

v2.8 menyebut mode `0x63` belum diketahui dan sumber EDI belum teramati. Audit lanjutan menemukan:

- EXE `0x49002D` mengisi EDI = 1. Saat mode 99, `0x49012B` mendorong EDI ke resolver `0x47F850`; hasilnya disimpan ke local slot `0x25F8748` pada `0x490141`. Angka 1 adalah **participant ID**, bukan asumsi kingdom slot 1.
- Setup `0x42BBA0` dan `0x4C73C0` mengisi session mode 99 dan game mode 3.
- Sender `0x488740` menguji mode dari session+`0x618`; mode 0 dan 99 menuju jalur keluar sebelum pengiriman DirectPlay. Ini mendukung inferensi bahwa mode 99 pada setup tersebut adalah jalur offline. Belum ada konfirmasi runtime Android terhadap transisi semua mode.
- Tabel participant slot 1–8 dimulai `0x248CA94`; AI archetype diperiksa pada `0x248CAFC + slot*4`. Viewer `0x25F874C` hanya dilaporkan, bukan kunci identitas.

Simbol recompiled di ELF asli mengikat fungsi guest dan native: `sub_00490020` → `0x28BFEB8`, `sub_00488740` → `0x29ED040`, `sub_0047F850` → `0x2BE89E4`, `sub_0042BBA0` → `0x22C98E8`, `sub_004C73C0` → `0xCBAE38`. Angka native adalah VA relatif terhadap ELF load bias, bukan alamat absolut proses Android.

Gate sekarang mensyaratkan semuanya: mode 99; game mode 3; local slot 1–8; participant ID local = 1; tepat satu slot memiliki ID 1; AI archetype local = 0; owner transaksi = local. Jika gagal, instruksi/efek asli berlaku. Gate dibaca ulang pada setiap event, sehingga tidak ada identitas yang dicache melewati load, pergantian peserta, mode, atau sesi. Gate tidak mengaktifkan mod pada mode yang belum didukung. Pemeriksaan ini adalah implementasi konservatif berdasarkan audit statis; **identitas manusia dan AI isolation tetap perlu diuji secara independen dalam game**.

## Hook dan ABI

ELF: AArch64, ELF64 little-endian, ET_DYN, alignment load segment `0x4000`. Native tidak menjalankan instruksi x86. Guest memory memakai base `0x2000000000`; stride pemain `0x39F4`. Gold berasal dari stock base `0x122C330 + owner*stride + 15*4`.

| Hook | VA native asli | Bytes asli | Efek |
|---|---|---|---|
| Regular recruit | `0x2520AEC` | `f10100b9` | Cegah store Gold yang menurun |
| Arab recruit | `0x2521510` | `110200b9` | Cegah store Gold yang menurun |
| Market purchase | `0x2C77090` | `cf0100b9` | Cegah store Gold yang menurun |
| Trade purchase | `0x2C2C7C8` | `110200b9` | Cegah store Gold yang menurun |
| Siege action | `0x29D1D90` | `cd0100b9` | Cegah store Gold yang menurun |
| Gold transfer | `0x297F2A8` | `490100b9` | Cegah store Gold yang menurun |
| Ally gold | `0x29BCF80` | `110200b9` | Cegah store Gold yang menurun |
| Inventory debit | `0x2C55970` | `883d0034` | Pilih early-return asli untuk sumber yang diizinkan |
| Peasant rate | `0x20888A0` | `2f0200b9` | Ubah rate timer positif; kondisi spawn asli tetap berjalan |

Setiap bytes asli diverifikasi sebelum patch, selain hash keseluruhan. Wrapper mempertahankan x0–x30, NZCV dan alignment stack 16-byte; hanya register hasil yang disengaja berubah. Payload dikompilasi `-mgeneral-regs-only` tanpa SIMD, stack protector, runtime allocation, atau undefined relocation. ASLR diuji pada load bias nol dan `0x7000000000`. JNI menemukan load bias dengan `dl_iterate_phdr`, memeriksa batas segmen dan signature `SHMOD033`, lalu menulis konfigurasi atomik 32-bit.

Gap file `0x4000` disisipkan setelah akhir RX file `0x3044090`, RX diperluas `0x3000`, payload berada pada VA `0x3048090`. Offset file segmen/section berikutnya digeser; alamat virtual kode/data lama tetap sama. BSS terakhir diperluas untuk control block pada `0x3C82050`. Tidak ada RWX segment baru atau mprotect selama gameplay. Library asli dibackup sebelum patch. Pengujian membalik perubahan yang disengaja dan menuntut sisa byte sama persis dengan library asli.

## Semantik fitur dan batas

Gold hanya menahan store ketika owner cocok, saldo lama nonnegatif, dan nilai baru lebih kecil. Nilai baru yang sama/lebih tinggi tidak diubah; ini mempertahankan income termasuk transfer Starting Goods yang menambah saldo aktual. Tidak ada bypass affordability; saldo awal harus mencukupi. Cakupan semua biaya, misalnya jenis biaya/pajak lain yang belum dipetakan, tidak diklaim lengkap.

Inventory hook berada dalam recompiled `sub_0041BD70`, native entry `0x2C558B4`. w16 pada titik hook adalah ESP guest sebelum prolog virtual; args owner/id/quantity/flag ada di ESP+4/+8/+12/+16. Hook meminta flag 0, jumlah positif, dan stok mencukupi. Gold ID 15 diizinkan pada jalur ini; bahan ID 2/4/6/7 hanya dari daftar caller konstruksi, peralatan ID 17–24 hanya caller rekrut reguler. LR dinormalisasi terhadap ASLR. Semua allowlisted caller diverifikasi sebagai BL ke entry yang sama. w8 = 0 mengarah ke early-return asli yang membersihkan virtual ESP +20. Hook melewati kedua pengurangan aggregate/physical stock, bukan mengembalikan stok sesudahnya. Efek terhadap warehouse nyata dan save masih belum diuji.

Tidak ada perkalian inventory atau pembelian pasar. Unlimited bahan belum meliputi konsumsi produksi. Stok nol tidak dibypass. Pengaturan equipment dan Gold independen; harga/persyaratan lain tetap bekerja.

Peasant: guest `0x45B8F0` memakai accumulator `0xFA0` dan rate pada jalur native `sub_0045B994`. Hook mengubah rate positif saja; ×1–100 memakai fixed-point /1000 dengan sisa pecahan per owner. Rate bonus dibatasi 4000; Instant mengisinya 4000. Rate nol/negatif tidak dipaksa menjadi spawn. Pemeriksaan housing, populasi, idle peasants, serta allocator asli tetap berjalan. Tidak ditambahkan spawn loop dan tidak disentuh troop pool. Ini mengurangi interval menuju ambang, bukan menjamin satu peasant langsung bila syarat asli gagal.

Production multipliers, Unlimited makanan/input industri, dan stok nol tidak dipasang. Recruitment/Construction Speed dan Instant tidak dipasang karena timer independen belum tervalidasi; jangan menyebut keberadaan UI kategori sebagai implementasi fitur tersebut.

## Bukti pengujian dan risiko tersisa

Lima kelompok uji mengeksekusi payload dan wrapper nyata di Unicorn: seluruh Gold site dengan owner berbeda/ON/OFF, income dan penolakan identitas, sumber/flag/stok inventori, epilog asli beserta virtual stack, serta peasant ×1/3/25/100/desimal/Instant. Register general, NZCV, SIMD, SP, dan ASLR diperiksa. Seluruh kelompok lulus. Pengujian memakai state sintetis; **bukan uji manusia versus AI nyata**.

Javac dan D8 lulus. Uji input JVM menolak NaN, infinity, eksponen, nilai di luar 1–100, lebih dari tiga desimal, serta key fitur tidak tersedia. Persistence, layout, drag, input dan lifecycle Android belum diuji runtime.

APK ZIP integrity, alignment, signing melalui apksigner, struktur manifest, JNI exports, semua BL sumber, sembilan branch, dan preservasi entry asli lulus. Tidak ada crash teramati dalam uji otomatis yang dijalankan. Crash Android, ANR, rendering Mali, keselamatan save, AI economy, sesi panjang, dan performa belum diketahui.

Biaya berjalan dibatasi pada event hook dan UI yang sedang dibuka; tidak ada scan memori kontinu, polling JNI per-frame, WebView, logging permanen, atau alokasi heap pada payload. Belum ada angka FPS/memori terukur di perangkat.

APK memakai package dan versionCode launcher asli tetapi sertifikat test baru. Backup save sebelum penggantian instalasi wajib secara praktis karena Android dapat menolak update dengan signature berbeda dan uninstall menghapus private data. Lihat panduan perangkat; tidak ada klaim bahwa allowBackup=false dapat diatasi oleh backup Android biasa.

## Hash hasil yang diserahkan

- Patched Extreme library: `9baf2492b96b14b83414fb166694cb94ffd634d16a4c570ff0d242a295290bfb`
- Signed APK: `f29c2c918f9880f958f720df6844682d4824c3cde16b334111abd693b3728902`
- Ukuran signed APK: 61220518 bytes; perubahan 16530 bytes dari APK asli.
- Signature v3 diverifikasi dengan apksigner.
