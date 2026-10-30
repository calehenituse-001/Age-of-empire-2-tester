# Asfatre v1.3 — menu cheat yang lebih sederhana

## Status saat ini

Pengguna meminta **menu Asfatre bawaan diperjelas dan cheat native v3.3 diintegrasikan**. Komponen UI Android `AdvancedCheatPanel.java` sudah ditambahkan dan dibangun pada GitHub Actions [run #41140947802](https://github.com/calehenituse-001/Age-of-empire-2-tester/actions/runs/41140947802) (source & DEX compile PASS). **Belum menjadi APK game terintegrasi**. Jangan menyebut fitur sebagai selesai atau mengirim DEX saja sebagai APK.

### Komponen yang telah disiapkan

- Kategori **Cheat bawaan** dengan tombol `Tambah Gold + Popularity (Alt+X)` dan `Perintah Alt+Q`. Kedua callback harus memanggil jalur `GameActivity.queueCheat(char)` yang asli.
- Kategori **Gold & bahan bangunan** untuk Gold/Wood/Stone/Iron/Pitch, disambungkan ke konfigurasi `StrongholdNativeBridge`.
- Kategori **Senjata & Armor** Bow/Crossbow/Spear/Pike/Mace/Sword/Leather/Metal.
- **Peasant**: input multiplier ×1–100 dan Instant Peasant.
- **Diagnostik**; opsi native dikunci jika bridge/library tidak terpasang.
- Teks yang lebih besar dan panel scroll untuk layar lanskap Android.
- Kode tidak menambah hak overlay sistem (`SYSTEM_ALERT_WINDOW` tidak diperlukan).

### Langkah integrasi yang masih dibutuhkan

1. Bekerja dari APK **Asfatre v1.3** yang benar: SHA256 `92f90a525716e6bc9d34bdd345a154780477fa1e0af5c0f16dfbd6f8be3629fd`, versionName 1.3-stable, versionCode 36, package `org.stronghold.port`.
2. **Jangan gunakan `ModInitProvider` lama** untuk menampilkan menu: pada APK mod v3.3–v3.3.2 tombolnya tetap tidak terlihat di HP pengguna.
3. Reverse/decompile DEX `GameActivity` dan `CheatMenu` bawaan Asfatre. Entry yang telah teridentifikasi:
   - `GameActivity.updateCheatMenu()V` (private) — memilih keadaan tampil/sembunyi.
   - `GameActivity.queueCheat(C)V` (private) — mengantre perintah asli.
   - `CheatMenu.<init>(Context,CheatMenu.Listener)` — menu bawaan.
   Saat tombol Cheat bawaan ditekan, buka `AdvancedCheatPanel.show(activity, key -> queueCheat(key))` dari dalam `GameActivity` melalui kode/smali yang tervalidasi. Ini adalah **contoh panggilan integrasi**, belum patch DEX yang telah diterapkan.
4. Tambah `AdvancedCheatPanel`, `ModSettings`, dan `StrongholdNativeBridge` pada APK dengan DEX yang dihasilkan compiler. Hindari duplikasi class yang sudah ada dalam primary DEX.
5. Adaptasi native v3.3 terhadap `libstronghold.so` milik Asfatre v1.3 **tanpa menimpa perubahan vendor**. Native v1.3 sudah punya segmen ELF tambahan; patcher v3.3 saat ini menolak hash baru dan memilih segmen BSS secara keliru bila dipakai apa adanya. Semua sembilan instruksi hook perlu dipastikan byte-for-byte dan owner-gate/AI isolation masih perlu pengujian riil.
6. Pastikan JNI bridge menemukan signature serta struktur kontrol yang benar pada *native v1.3 yang telah dipatch*; jangan mengaktifkan toggle bila belum ada.
7. Build APK baru dari Asfatre, pertahankan aset/data luar, pasang signing key khusus mod. Signature original vendor tidak dapat direproduksi. **Cadangkan save sebelum uninstall APK lama**, karena package sama, signer berbeda, dan `allowBackup=false`.
8. Tes perangkat: menu terlihat, tombol Alt+X asli bekerja, ON/OFF Gold memengaruhi **pemain saja**, AI normal, perlengkapan tidak habis saat rekrut, Peasant, save/load, GameActivity resume, dan landscape.

### Status pengembangan per fitur

| Fitur | Status |
|---|---|
| UI kategoris & tombol bantu | Java source + DEX compile PASS; belum dipasang dalam APK |
| Alt+X dan Alt+Q | Jalur cheat asli tersedia di APK; callback panel belum dihubungkan |
| Unlimited Gold dan inventory | Native v3.3 source tersedia; **belum kompatibel/terpasang v1.3** |
| Peasant multiplier / Instant | Native v3.3 source tersedia; **belum kompatibel/terpasang v1.3** |
| Food / production ×100 / Instant construction/recruit | Belum diimplementasikan |
| APK Asfatre modded siap main | Belum |
| Uji runtime Android, isolasi AI | Belum |

## Keputusan teknis

Jadikan tombol Cheat Asfatre bawaan sebagai pintu masuk panel (bukan floating overlay baru). Jika native hook tidak tersedia atau identitas pemain tidak dapat diverifikasi, mod harus menolak pengaktifan dan membiarkan game bekerja normal.

Source tidak memuat APK vendor, EXE, asset game, atau private signing key.
