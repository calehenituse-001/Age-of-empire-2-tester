# Instalasi dan pengujian perangkat — v3.3

**APK ini build uji, belum dijalankan pada Android nyata.** Gunakan save salinan dan mulai dari skirmish offline Extreme. Tidak ada cheat yang boleh diaktifkan pada multiplayer; gate menolak mode di luar kandidat offline yang didukung. Menu hanya ditambahkan ke Extreme.

## 1. Simpan APK dan save lama lebih dahulu

Package tetap `org.stronghold.port`, tetapi signing key build ini berbeda dari launcher asli. Android biasanya menolak pemasangan sebagai update dengan pesan signature conflict. **Jangan langsung uninstall aplikasi lama.** Uninstall menghapus private data. APK asli memiliki `allowBackup=false`, sehingga backup Android biasa tidak dapat dianggap cukup.

1. Simpan APK launcher asli, folder data yang benar-benar dipilih di launcher, semua folder save dan file konfigurasi ke PC/lokasi terpisah.
2. Jika data ada di `/sdcard/Stronghold`, salin seluruh folder itu. Jika memilih lokasi lain, backup lokasi tersebut juga. Jangan menganggap semua save berada dalam folder eksternal.
3. Jika memakai ADB, lakukan backup private data saat aplikasi telah ditutup. Original APK teridentifikasi `debuggable=true`, tetapi `run-as` tetap perlu diperiksa pada perangkat:

```bash
adb shell run-as org.stronghold.port pwd
adb exec-out run-as org.stronghold.port tar -cf - . > stronghold-private-before-v33.tar
adb pull /sdcard/Stronghold stronghold-external-before-v33
```

Periksa arsip bisa dibuka dan file save penting benar-benar ada. Jika command ditolak atau lokasi save belum diketahui, **hentikan proses penggantian instalasi** sampai backup ditemukan. Jangan menganggap file arsip berukuran kecil otomatis berarti backup berhasil. Pulihkan file save yang diidentifikasi; jangan menyalin cache/library lama secara membabi buta ke instalasi baru.

Setelah backup terverifikasi, perangkat dapat memakai build bertanda tangan baru dengan menghapus instalasi lama lalu memasang APK uji. Penggantian ini dilakukan pengguna; proses build tidak pernah mengubah instalasi atau save di HP. Untuk update v3.3 berikutnya yang memakai test key sama, gunakan pemasangan update biasa/`adb install -r`.

## 2. Instalasi dan data

- Salin `Stronghold_Mod_Menu_v3.3_Test.apk` ke HP; buka installer Android dan berikan izin install dari sumber tersebut bila diminta.
- Alternatif ADB: `adb install Stronghold_Mod_Menu_v3.3_Test.apk`. Catat pesan error lengkap jika gagal.
- Gunakan launcher/importer asli untuk memilih data Extreme yang dimiliki pengguna. APK mod tidak menyertakan data game eksternal. Jangan mengimpor EXE/data baru hanya untuk mengganti launcher bila data lama sudah valid.
- Buka **Stronghold Crusader Extreme**. Cari tombol **MOD**. Buka panel; status harus menyebut hook terpasang. Jika hook tidak tersedia, jangan menganggap toggle atau file konfigurasi mengaktifkan cheat.
- Semua setting default OFF/×1. Toggle di panel adalah draft sampai **Apply & Save** ditekan. **Reset All** langsung mengembalikan OFF/×1 dan menyimpannya.

## 3. Pemeriksaan aplikasi dan menu

Uji terpisah: startup launcher, deteksi data, launch Extreme, render, suara, touchscreen, membuka/menutup panel 30 kali, drag MOD ke setiap sudut, keyboard input, minimize/resume, keluar game, mulai game baru, restart proses, dan landscape change bila launcher mendukungnya. Tombol harus tetap dapat dijangkau. Uji dua jari pada kontrol game dengan panel tertutup. Pastikan posisi tombol dan setting tersimpan setelah restart.

## 4. Gold terlebih dahulu

Gunakan skirmish offline dengan satu pemain manusia dan AI, saldo awal cukup, idle peasants, dan equipment yang sesuai. Tunggu animasi **Starting Goods** selesai: counter Starting Goods yang berkurang sambil saldo Gold meningkat adalah normal.

| Langkah | Pengamatan yang diharapkan |
|---|---|
| Semua OFF, rekrut normal | Gold turun sesuai biaya |
| Gold ON → Apply, rekrut normal | Gold tidak turun pada biaya yang dipatch |
| Rekrut Arabian mercenary | Gold tidak turun bila syarat lain terpenuhi |
| Beli satu jenis barang di market | Gold tidak turun, barang masuk sekali |
| Bangunan/aksi yang memiliki biaya Gold | Uji setiap jenis; laporkan biaya yang masih turun |
| Income/pajak/penjualan | Gold tetap bertambah normal |
| Gold OFF → Apply | Pengeluaran kembali normal |
| Keluar, mulai/load skirmish | Gate dievaluasi kembali; setting tetap tersimpan |

Periksa Debug / Diagnostics dengan **Refresh** setelah tindakan. `seen` berarti titik hook dilewati; `applied` berarti hook memilih modifikasi; `denied` berarti permintaan ditolak oleh guard. Semua counter kumulatif sampai proses berhenti. `owner` dan `reason` adalah **event terakhir**, bukan pemilik semua event applied sebelumnya. Nilai awal nol belum menunjukkan sesi teridentifikasi.

Jika `reason=2`, sesi belum didukung. `3–7` menunjukkan penolakan identitas/owner. Jangan mengubah participant ID manual untuk memaksa aktivasi. Sertakan diagnostics dan mode game dalam laporan.

## 5. Wood dan peralatan

Unlimited Wood berlaku pada jalur biaya bangunan yang dipetakan, dengan Wood awal mencukupi. Catat stok, aktifkan Wood saja, Apply, letakkan bangunan berbiaya Wood. Stok diharapkan tidak turun. Matikan lalu ulangi sebagai pembanding. Ulangi Stone, Iron, Pitch hanya pada aktivitas konstruksi yang benar-benar membutuhkan bahan itu. Konsumsi wood oleh industri belum didukung.

Untuk Bow: sediakan Bow dan peasants, matikan Unlimited Gold, aktifkan Bow, lalu rekrut Archer. Bow diharapkan tetap, Gold turun. Uji ulang Gold ON dan Bow OFF untuk memastikan pengaturan independen. Uji equipment lainnya dengan unit yang benar. Persyaratan peralatan lain tetap berlaku. Rekrut normal/Arab tetap tunduk pada limit unit asli.

Stok awal nol harus **tetap gagal memenuhi persyaratan** sebagaimana game asli; fitur bypass nol tidak tersedia. Jangan mengharapkan pembangunan/rekrut tanpa persediaan awal. Uji juga stok pas sebesar biaya, stok kurang, stok penuh, penjualan barang, serta save/load. Penjualan dan pembelian tidak boleh digandakan oleh Unlimited material/equipment.

## 6. Multiplier, Instant, dan fitur yang belum tersedia

- Production multiplier untuk Wood/Stone/Iron/Food/Weapons/Armor **belum terpasang**. Tidak ada switch aktif palsu untuk mengujinya. Produksi ×3/25/100 dicatat `NOT IMPLEMENTED`, bukan PASS.
- Peasant Spawn tersedia: dengan kondisi spawn asli yang terpenuhi, ukur waktu muncul peasant pada ×1, ×3, ×25, ×100 dan ×1.25. Gunakan game speed sama, housing/popularity/stock yang sama. Hasil rate tinggi dapat mencapai batas update asli; tidak harus 100 peasant per tick.
- Instant Peasant ON memprioritaskan ambang minimum saat kondisi asli terpenuhi. Matikan untuk memakai multiplier tersimpan. Housing penuh, popularitas yang tidak menghasilkan rate positif, batas idle peasants, dan unit pool tetap membatasi spawn.
- Recruitment Speed/Instant Recruitment dan Construction Speed/Instant Construction belum didukung. Jangan menilai kecepatan klik, bangunan yang memang muncul langsung, atau ketersediaan peasants sebagai bukti fitur baru.

## 7. AI isolation dan stabilitas

Bandingkan save/skenario terkontrol dengan setting OFF dan ON. Identifikasi slot manusia dari skenario/game secara independen, lalu cocokkan diagnostics. Amati transaksi dan produksi AI dengan probe/analisis save yang sesuai bila tersedia. Counter local/viewer sintetis atau kenyataan bahwa AI masih berjalan **bukan bukti** economy AI tidak berubah. Jika pengeluaran/stock AI tidak dapat diukur, catat `NOT VERIFIED`.

Uji save/load, pergantian peserta, trail/skirmish yang berbeda, kembali ke menu, multi-AI, kehabisan resource, storage penuh, pasukan besar dalam limit asli, dan sesi 30–60 menit. Simpan ke slot uji baru; buka kembali dengan semua mod OFF. Periksa inventory, unit, dan save; hentikan penggunaan save tersebut jika muncul ketidaksesuaian.

Seluruh pemeriksaan perangkat berikut masih **PENDING**: instalasi, import, launch, render/input, menu/drag, Gold, warehouse, AI isolation, peasant timing, save compatibility, crash/ANR, FPS/memori dan sesi panjang. Build/emulasi lulus tidak mengubah status ini.

## 8. Melaporkan masalah

Sertakan tipe HP, Android, mode game, data/version yang dipakai, fitur ON, urutan tindakan, saldo/stok sebelum-sesudah, apakah bisa diulang dengan semua OFF, dan **Copy diagnostics**. Bedakan crash installer, launcher, proses Extreme, serta render/input yang macet.

Dengan ADB, setelah mereproduksi crash:

```bash
adb logcat -b crash -d > stronghold-crash.txt
adb logcat -d -v threadtime > stronghold-logcat.txt
```

Logcat lengkap bisa berisi informasi aplikasi lain; tinjau sebelum membagikan. Jika blank screen/ANR tanpa crash, sertakan waktu kejadian dan kondisi game. Jangan mengirim seluruh data game berhak cipta; cukup log, diagnostics, langkah reproduksi, dan save uji jika diperlukan.
