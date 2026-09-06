# Panduan Pengembangan

## Prasyarat

- Flutter stable beserta Dart yang memenuhi batas SDK di `pubspec.yaml`.
- Git, JDK 17, Android SDK command-line tools, platform-tools, serta lisensi SDK yang sudah diterima.
- HP Android dengan USB debugging aktif atau emulator yang disiapkan sendiri. Android Studio tidak wajib untuk alur command line ini.

Jalankan perintah dari root repository. Contoh berikut dapat dipakai di Git Bash. Proyek ini menargetkan Android; belum ada dukungan runtime web atau desktop yang diverifikasi.

## Menjalankan aplikasi

```bash
flutter doctor -v
flutter pub get
dart run build_runner build
flutter devices
flutter run -d DEVICE_ID
```

Ganti `DEVICE_ID` dengan ID HP pada `flutter devices`. Buka kunci HP dan izinkan USB debugging/instalasi bila diminta. Build pertama dapat mengunduh dependensi Android. Peringatan Visual Studio tidak perlu diselesaikan jika hanya membangun Android.

`app_database.g.dart` dihasilkan dari deklarasi Drift dan ikut di-commit bersama sumbernya. Jangan mengedit berkas tersebut secara manual; jalankan ulang `build_runner` ketika deklarasi tabel berubah. Pertahankan `pubspec.lock` di Git karena repository ini adalah aplikasi, agar versi dependency yang dipakai bersama tetap tercatat.

## Pemeriksaan sebelum commit

```bash
dart run build_runner build
dart format lib test
flutter analyze
flutter test
git diff --check
git status --short
git diff
```

Jika formatter menyentuh generated code, pastikan hasil tetap sesuai generator dan jangan membuat perubahan manual pada `.g.dart`. Pemeriksaan otomatis tidak menggantikan pengujian di HP; khususnya persistensi, keyboard, izin instalasi, dan performa perlu diperiksa pada runtime Android.

Untuk menilai kelancaran pada HP referensi, gunakan profile mode setelah alur debug bekerja:

```bash
flutter run --profile -d DEVICE_ID
```

Jangan menyimpulkan performa release berdasarkan debug mode. Build release saat ini belum merupakan rilis Play Store: konfigurasi penandatanganan produksi dan prosedur distribusi perlu disiapkan terpisah.

## Checklist manual alpha

Gunakan data percobaan. Alpha belum memiliki backup/restore, edit, atau hapus transaksi. Checklist ini adalah langkah verifikasi yang harus dijalankan, bukan laporan bahwa semua pengujian sudah lulus.

### Skenario perhitungan

Pilih satu bulan uji (misalnya September 2026); tanggal entri dalam langkah 1–4 berada pada bulan tersebut.

1. Buat rekening **Bank Uji**, saldo awal Rp1.000.000, dan **Tunai Uji**, saldo awal Rp200.000. Total saldo harus Rp1.200.000; pemasukan/pengeluaran tetap nol.
2. Catat pemasukan Rp3.000.000 ke Bank Uji. Bank menjadi Rp4.000.000, pemasukan bulan itu Rp3.000.000.
3. Catat pengeluaran Rp100.000 dari Bank Uji. Bank menjadi Rp3.900.000; pengeluaran Rp100.000 dan selisih bulanan Rp2.900.000.
4. Transfer Rp150.000 dari Bank Uji ke Tunai Uji. Bank menjadi Rp3.750.000, Tunai Rp350.000, total Rp4.100.000. Ringkasan tetap pemasukan Rp3.000.000 dan pengeluaran Rp100.000. Riwayat hanya menampilkan satu transaksi transfer.
5. Catat pengeluaran Rp50.000 dari Bank Uji pada bulan sebelumnya. Saldo saat ini menjadi Bank Rp3.700.000 dan total Rp4.050.000. Ringkasan bulan uji tetap sama; pengeluaran Rp50.000 hanya masuk ringkasan bulan sebelumnya.
6. Berpindah ke bulan sebelumnya. Saldo total tetap Rp4.050.000 karena kartu saldo bukan laporan saldo historis.
7. Tutup aplikasi sepenuhnya lalu buka lagi. Rekening, transaksi, dan hasil perhitungan harus tetap sama. Jangan uninstall atau hapus data untuk tes buka ulang ini.

### Input, navigasi, dan ketahanan tampilan

- [ ] Instalasi baru menampilkan keadaan kosong yang jelas dan alur tambah rekening dapat dibuka.
- [ ] Nama rekening kosong/duplikat, nominal tidak valid, dan pilihan wajib yang kosong ditolak dengan pesan yang bisa dipahami.
- [ ] Transfer ke rekening yang sama tidak dapat disimpan; alur transfer dengan kurang dari dua rekening memberi arahan yang jelas.
- [ ] Form pemasukan hanya menawarkan kategori pemasukan dan form pengeluaran hanya kategori pengeluaran.
- [ ] Tekan simpan berulang ketika proses sedang berjalan: tidak terjadi transaksi ganda.
- [ ] Batalkan form atau kembali dari pemilih tanggal: data tidak tersimpan tanpa konfirmasi simpan.
- [ ] Tanggal di akhir bulan/tahun masuk ke periode kejadian yang benar.
- [ ] Riwayat dengan lebih dari 50 entri dapat dimuat lanjut tanpa duplikasi atau kehilangan urutan.
- [ ] Coba lebar layar HP kecil, keyboard terbuka, dan ukuran font sistem diperbesar. Form serta tombol tetap dapat dijangkau tanpa overflow.
- [ ] Pindah layar/bulan setelah menyimpan memperbarui rekening dan ringkasan yang terkait.
- [ ] Kondisi error repository diuji dengan fake/injeksi kegagalan di pengujian otomatis; jangan sengaja merusak database pribadi untuk mengetes pesan error.

## Riwayat commit yang rapi

Gunakan satu commit untuk satu perubahan logis. Test yang membuktikan sebuah fitur sebaiknya ikut commit fitur tersebut. Tidak perlu membuat commit terpisah untuk setiap berkas.

Contoh pengelompokan pekerjaan fondasi ini:

```text
build: add local finance dependencies and Android metadata
feat(data): persist accounts and ledger with balance tests
feat(ledger): add account and transaction flows with UI tests
docs: document alpha architecture and development workflow
```

Commit merupakan tindakan manual pengembang; dokumentasi ini tidak melakukan staging atau commit. Tinjau path yang dipilih sebelum menambahkannya ke staging:

```bash
git status --short
git add -p
git diff --cached --stat
git diff --cached
git commit -m "feat(ledger): add initial local finance workflow"
git log --oneline -5
```

`git add -p` hanya memproses perubahan tracked; untuk berkas baru, gunakan `git add` dengan path berkas yang memang ingin dimasukkan. Bila pemisahan fondasi menghasilkan commit yang tidak bisa dianalisis/dibangun karena dependensi antarlapisan, gabungkan bagian yang saling bergantung menjadi satu commit fitur yang utuh. Jangan mengorbankan baseline yang berfungsi hanya untuk memperbanyak commit.

Jangan commit data keuangan pribadi, database SQLite beserta berkas journal/WAL/SHM, backup, `.env`, signing key, `key.properties`, atau hasil build. Simpan signing key dan salinan pemulihannya di tempat aman di luar repository. Jangan memakai `git reset --hard` atau menghapus database sebagai langkah troubleshooting rutin.

## Urutan kerja setelah alpha

1. Jalankan checklist manual pada HP referensi dan perbaiki ketidaksesuaian saldo/tampilan.
2. Siapkan ekspor skema dan pengujian migrasi sebelum perubahan skema berikutnya.
3. Implementasikan backup/restore lengkap dan uji pemulihan pada perangkat/instalasi terpisah menggunakan data percobaan.
4. Lanjutkan kalender grid serta kebutuhan v0.1 yang belum tersedia.

Selama backup/restore belum tersedia, jangan menjadikan alpha satu-satunya catatan keuangan.
