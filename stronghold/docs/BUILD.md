# Build APK uji v3.3

Lingkungan yang digunakan: Linux x86-64, JDK 17.0.20, Android platform 35, build-tools 35.0.0, NDK r27c / 27.2.12479018, Python 3. Dependensi Python dipatok dalam `requirements.txt`. Target native API 28 (Android 9); ABI arm64-v8a.

APK input wajib launcher asli dengan SHA256:

```
92dc03003274dcac024d63a66e61fab75f9f5b26bb3bcd01c89f935bfa22d252
```

Build menolak APK/library lain, termasuk APK Gold lama. Tidak memerlukan EXE atau data game untuk membangun. EXE asli hanya digunakan dalam audit tambahan.

```bash
python3 -m pip install -r requirements.txt
export ANDROID_HOME=/path/to/android-sdk
export JAVA_HOME=/path/to/jdk-17
export PATH="$JAVA_HOME/bin:$PATH"
bash tools/build.sh /path/Launcher-Stronghold-0.3.1-DEV.apk /path/Stronghold_Mod_Menu_v3.3_Test.apk
```

SDK harus menyediakan `platforms/android-35/android.jar`, `build-tools/35.0.0`, dan `ndk/27.2.12479018`. Jika layout berbeda, gunakan `ANDROID_JAR`, `BUILD_TOOLS`, dan `NDK_BIN` untuk menunjuk masing-masing komponen. `NDK_BIN` adalah direktori `toolchains/llvm/prebuilt/linux-x86_64/bin`. Diperlukan juga `rg`, OpenSSL, dan Bash.

Build melakukan:

1. Verifikasi SHA APK dan library; salin library asli ke `build/libstronghold-original.so`.
2. Verifikasi sembilan instruksi; kompilasi wrapper/payload ARM64; buat patch ELF dan manifest perubahan.
3. Kompilasi library JNI dan uji eksekusi ARM64 di Unicorn.
4. Kompilasi Java, uji validasi input, lalu D8 menjadi DEX tambahan.
5. Tambah provider non-exported pada proses Extreme; pertahankan DEX/resources/library lain.
6. Zipalign, tanda tangani, verifikasi tanda tangan, dan uji integritas terhadap APK asli.

`build/patch_manifest.json`, `apk_audit.json`, dan `signature_verification.txt` merupakan hasil aktual dari build. `docs/` menyimpan salinan hasil APK yang diserahkan, bukan hasil otomatis setiap build berikutnya. `native/generated.h` dibuat kembali dari payload yang dikompilasi.

## Signing dan update

Tanpa argumen tambahan, script membuat test key lokal dalam `build/`. Gunakan key yang sama untuk update berikutnya. APK yang diserahkan memiliki sertifikat berbeda dari APK launcher asli; tidak dapat menggantikannya sebagai update biasa. Lihat panduan backup sebelum mengganti instalasi.

Untuk menggunakan key uji yang telah disimpan:

```bash
bash tools/build.sh original.apk result.apk private-key.pem public-cert.der
```

Key dapat berupa PEM atau DER PKCS#8; PEM dikonversi secara eksplisit ke DER untuk apksigner. Private key tidak boleh dikomit atau dimasukkan ke source ZIP. Signing kit untuk APK yang diserahkan disimpan terpisah, privat, dengan nama `Stronghold_v3.3_Private_Test_Signing.zip`.

## Pengujian individual

```bash
python3 tests/test_native.py
python3 tests/test_apk.py original.apk signed.apk
```

Perintah pertama memerlukan hasil patch pada `build/`; keduanya membutuhkan dependensi Python. Hasil emulasi bukan pengganti pengujian perangkat.

## Reversibilitas

Seluruh patch dilakukan pada salinan. Input APK/library tidak ditulis ulang. Untuk build tanpa mod, gunakan APK asli yang telah dibackup. Menonaktifkan setting membuat hook menjalankan efek instruksi asli; hook tetap terpasang sampai proses berakhir. Tidak ada modifikasi file save atau aset game oleh build script.
