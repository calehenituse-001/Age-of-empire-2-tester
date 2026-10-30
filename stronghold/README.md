# Stronghold Crusader Extreme Android — Mod Menu v3.3

Milestone APK uji dari **Launcher Stronghold 0.3.1-DEV asli milik pengguna**. Ini integrasi Android/JNI dengan perubahan instruksi ARM64 pada game asli; tidak menggunakan HTML, WebView, atau simulasi game.

**Status: implemented but runtime-untested.** APK telah dikompilasi, ditandatangani, dan diperiksa. Instruksi ARM64 hasil patch telah dieksekusi di Unicorn dengan state sintetis. Belum ada pengujian instalasi atau gameplay di Android/Xiaomi 11T. Tidak ada fitur yang berstatus *implemented and runtime-tested* pada Android.

## Yang tersedia dalam build uji

- Tombol MOD yang dapat digeser, panel scroll, kategori, ON/OFF, Apply & Save, Reset individual/semua, dan diagnostics manual.
- Unlimited Gold: tujuh titik debit langsung dan jalur debit inventori Gold. Rekrut biasa/Arab dan jalur pembelian dipatch; kelengkapan seluruh biaya masih perlu dibuktikan dalam game.
- Unlimited Wood, Stone, Iron, Pitch **pada jalur biaya konstruksi yang dipetakan**.
- Unlimited Bow, Crossbow, Spear, Pike, Mace, Sword, Leather Armor, Metal Armor **pada rekrut reguler**.
- Peasant Spawn ×1–100, sampai tiga digit desimal; Instant Peasant independen. Kondisi spawn dan alokasi unit asli tetap berlaku.

Semua mod memakai pemeriksaan owner pada setiap event. Sesi selain kandidat offline Extreme skirmish/trail (mode 99, game mode 3) ditolak. Viewer bukan penentu manusia. AI isolation pada gameplay **belum diverifikasi**. Mulai dengan semua fitur OFF dan gunakan save uji terpisah.

## Batas yang sengaja dinyatakan di menu

Production multiplier untuk semua bahan, makanan, senjata, dan armor belum dipasang. Unlimited makanan, input bahan baku industri, dan penggunaan stok nol belum didukung. Gold dan peralatan tetap memerlukan saldo/stok awal yang memenuhi pemeriksaan asli. Recruitment/Construction Speed atau Instant belum tersedia karena timer yang sesuai belum tervalidasi. Crusader HD dan Stronghold Classic tidak dipatch. Batas pasukan asli tidak berubah.

## Perbaikan bootstrap MOD (branch perbaikan)

Jika tombol **MOD** tidak terlihat setelah masuk Extreme, lihat [diagnosis menu](docs/MENU_NOT_VISIBLE.md).
Provider sekarang menunda pemasangan tombol hingga decor view terpasang, dan menulis log `StrongholdModBoot` untuk membedakan masalah startup, activity, dan rendering.
Jalankan `python3 tools/verify_menu_apk.py path/ke/APK.apk` untuk memeriksa bahwa provider, DEX, dan library telah masuk APK hasil build. Pemeriksaan ini **tidak membuktikan tombol terlihat pada Android**.

GitHub Actions utama di repositori ini membangun launcher **AoE II**, bukan Stronghold. Pemeriksaan source Stronghold yang dapat dijalankan manual ada di workflow `Stronghold menu source check (no APK)`. Build Stronghold tetap menggunakan `tools/build.sh` dan APK original milik pengguna sebagaimana dijelaskan dalam [petunjuk build](docs/BUILD.md).

## Berkas

- [Laporan teknis](docs/TECHNICAL_REPORT.md): hook, hashes, identitas, batas, hasil pengujian.
- [Panduan perangkat](docs/TESTING_ID.md): backup, instalasi, skenario uji, laporan crash.
- [Build](docs/BUILD.md): SDK/NDK, input yang tepat, signing, uji otomatis.
- [Status fitur](docs/FEATURE_STATUS.csv).
- `android/`: UI, konfigurasi, lifecycle, JNI adapter.
- `native/`: payload event, frame register, JNI runtime.
- `tools/`: patch, manifest injector, perakitan/signing APK.
- `tests/`: emulasi ARM64, konfigurasi, integritas APK.

Folder ini berdiri sendiri di dalam repository Age-of-empire-2-tester. Kode AoE tidak diubah. APK asli, EXE, arsip data game, dan private signing key tidak disertakan dalam source publik. Data game tetap diimpor melalui launcher asli.

Integrasi melanjutkan source v3.2 (yang meneruskan v3.1) dan penelitian sampai v2.8. Injector manifest dan assembler berasal dari v3.2, diperbaiki untuk build ini. Gate Gold lama diganti setelah koreksi makna kandidat mode 99 dan argumen resolver. Alamat lama tidak dipakai tanpa hash dan verifikasi instruksi.
