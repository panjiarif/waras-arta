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

`app_database.g.dart` dan `app_database.steps.dart` dihasilkan dari deklarasi serta langkah migrasi Drift dan ikut di-commit bersama sumbernya. Jangan mengedit berkas tersebut secara manual; jalankan ulang `build_runner` ketika deklarasi tabel atau migrasi berubah. Pertahankan snapshot schema di `drift_schemas/app_database/` dan `pubspec.lock` di Git agar perubahan database serta versi dependency yang dipakai bersama tetap tercatat.

## Pemeriksaan sebelum commit

```bash
dart run build_runner build
dart format lib test
flutter analyze
flutter test
flutter test test/drift/app_database/migration_test.dart
flutter test test/data/drift_backup_data_store_test.dart
flutter test test/data/encrypted_backup_codec_test.dart
flutter test test/data/backup_file_gateway_test.dart
flutter test test/data/backup_service_test.dart
flutter test test/features/backup/backup_screen_test.dart
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

Gunakan data percobaan. Backup/restore sudah tersedia dalam bentuk manual, tetapi keberadaan fitur tidak membuktikan bahwa suatu file tertentu aman atau dapat dipulihkan. Penghapusan permanen dan replace-all hanya boleh diuji pada data yang dapat dibuat ulang sampai alur Android selesai diverifikasi. Checklist ini adalah langkah verifikasi yang harus dijalankan, bukan laporan bahwa semua pengujian sudah lulus.

### Skenario perhitungan

Pilih satu bulan uji (misalnya September 2026); tanggal entri dalam langkah 1–4 berada pada bulan tersebut.

1. Buat rekening **Bank Uji**, saldo awal Rp1.000.000, dan **Tunai Uji**, saldo awal Rp200.000. Total saldo harus Rp1.200.000; pemasukan/pengeluaran tetap nol.
2. Catat pemasukan Rp3.000.000 ke Bank Uji. Bank menjadi Rp4.000.000, pemasukan bulan itu Rp3.000.000.
3. Catat pengeluaran Rp100.000 dari Bank Uji. Bank menjadi Rp3.900.000; pengeluaran Rp100.000 dan selisih bulanan Rp2.900.000.
4. Transfer Rp150.000 dari Bank Uji ke Tunai Uji. Bank menjadi Rp3.750.000, Tunai Rp350.000, total Rp4.100.000. Ringkasan tetap pemasukan Rp3.000.000 dan pengeluaran Rp100.000. Riwayat hanya menampilkan satu transaksi transfer.
5. Catat pengeluaran Rp50.000 dari Bank Uji pada bulan sebelumnya. Saldo saat ini menjadi Bank Rp3.700.000 dan total Rp4.050.000. Ringkasan bulan uji tetap sama; pengeluaran Rp50.000 hanya masuk ringkasan bulan sebelumnya.
6. Berpindah ke bulan sebelumnya. Saldo total tetap Rp4.050.000 karena kartu saldo bukan laporan saldo historis.
7. Tutup aplikasi sepenuhnya lalu buka lagi. Rekening, transaksi, dan hasil perhitungan harus tetap sama. Jangan uninstall atau hapus data untuk tes buka ulang ini.
8. Buka detail pengeluaran Rp100.000, ubah menjadi Rp125.000, lalu pastikan Bank, pengeluaran bulanan, dan selisih berubah tepat Rp25.000.
9. Ubah tanggal pengeluaran tersebut ke bulan sebelumnya. Pastikan transaksi dan pengeluaran berpindah periode, sedangkan saldo saat ini tidak berubah lagi hanya karena perpindahan tanggal.
10. Hapus transfer Rp150.000 setelah membaca dialog konfirmasi. Bank harus bertambah Rp150.000, Tunai berkurang Rp150.000, total saldo tetap, dan hanya satu baris transfer yang hilang.

### Skenario kelola rekening

1. Buka detail Bank Uji, ubah nama dan jenisnya, lalu pastikan saldo serta seluruh riwayat tetap terhubung ke rekening yang sama.
2. Koreksi saldo Bank Uji ke angka yang lebih rendah. Pastikan riwayat menampilkan satu penyesuaian negatif sebesar selisihnya, saldo mencapai target, dan pemasukan/pengeluaran bulanan tidak berubah.
3. Koreksi kembali ke angka yang lebih tinggi. Pastikan penyesuaian positif baru dibuat; entri penyesuaian lama tidak menyediakan edit atau hapus.
4. Coba arsipkan rekening yang saldonya tidak nol. Aplikasi harus menolak dan mengarahkan pengguna untuk menolkan saldo terlebih dahulu.
5. Buat dua rekening aktif untuk pengujian, nolkan salah satunya, lalu arsipkan. Rekening harus hilang dari daftar default, muncul ketika rekening arsip ditampilkan, dan tidak tersedia pada form transaksi atau penyesuaian baru.
6. Buka transaksi lama yang menyentuh rekening arsip. Detail tetap terbaca, tetapi edit dan hapus tidak tersedia sampai rekening dipulihkan. Setelah dipulihkan, rekening kembali aktif beserta riwayatnya.
7. Coba arsipkan satu-satunya rekening aktif yang tersisa. Aplikasi harus menolak tindakan tersebut.
8. Buat rekening baru bersaldo nol tanpa riwayat lalu hapus permanen setelah konfirmasi. Buat rekening lain yang sudah memiliki ledger dan pastikan hapus permanennya tidak tersedia; tidak boleh ada transaksi yang ikut terhapus.

### Skenario kalender

1. Buka tab Kalender. Pastikan bulan berjalan dan hari ini terpilih, header tersusun Sen–Min, tombol bulan berikutnya nonaktif, serta tanggal setelah hari ini tidak dapat dipilih.
2. Bergerak ke bulan-bulan sebelumnya. Pastikan pilihan tanggal tetap valid pada bulan yang lebih pendek dan navigasi berhenti pada Januari 2000.
3. Pada satu tanggal lampau, buat masing-masing satu pemasukan, pengeluaran, transfer, dan penyesuaian. Pastikan grid memberi penanda pemasukan, pengeluaran, dan aktivitas lain pada tanggal tersebut.
4. Pilih tanggal tadi. Pastikan total harian hanya menghitung pemasukan/pengeluaran, sedangkan hitungan catatan, transfer, dan penyesuaian mencakup keempat entri. Semua entri harus muncul pada daftar tanggal terpilih.
5. Ketuk setiap jenis entri dari daftar kalender dan pastikan detail transaksi yang benar terbuka. Kembali ke kalender tanpa kehilangan bulan/tanggal yang dipilih.
6. Pilih tanggal lampau lain lalu tekan tombol **Catat transaksi**. Pastikan tanggal awal form sama dengan tanggal kalender yang dipilih dan tetap dapat diubah melalui pemilih tanggal.
7. Buat lebih dari 50 entri dalam satu bulan dengan beberapa entri pada satu tanggal. Pastikan penanda, total harian, dan daftar tanggal terpilih mencakup semuanya walaupun riwayat bulanan belum dimuat lanjut.
8. Edit tanggal atau nominal sebuah transaksi, kemudian hapus transaksi percobaan. Pastikan penanda, total, dan daftar pada tanggal lama maupun baru bereaksi tanpa membuka ulang aplikasi.

### Skenario backup dan restore

Ikuti spesifikasi lengkap pada [backup-restore.md](backup-restore.md). Gunakan snapshot percobaan yang mencakup rekening aktif/arsip, kategori kustom/arsip, seluruh jenis ledger, dan tanggal lampau.

1. Buka menu **Backup & pulihkan data**. Pastikan peringatan menjelaskan bahwa kata sandi tidak disimpan dan file tidak dapat dipulihkan jika kata sandi dilupakan.
2. Coba kata sandi kosong, kurang dari 12 karakter, dan konfirmasi berbeda. Dialog penyimpanan tidak boleh terbuka.
3. Buat backup dengan kata sandi valid ke Downloads. Pastikan file `.warasarta` benar-benar tersedia, status berhasil baru muncul setelah hasil tulis diverifikasi, dan aplikasi tidak menganggap pembatalan pemilih lokasi sebagai keberhasilan.
4. Jika Google Drive tersedia pada pemilih dokumen Android, simpan salinan kedua ke Drive. Pastikan file dapat dipilih kembali; tindakan ini tetap manual dan bukan sinkronisasi Waras Arta.
5. Tambah transaksi setelah backup dibuat. Ingat bahwa transaksi ini tidak berada dalam snapshot lama.
6. Pilih file backup lalu masukkan kata sandi salah. File harus ditolak dan seluruh data aktif tetap sama.
7. Rusak atau potong **salinan** file backup percobaan. File harus ditolak tanpa perubahan database; jangan merusak satu-satunya salinan yang valid.
8. Buka backup valid dengan kata sandi benar. Cocokkan waktu pembuatan serta jumlah rekening, kategori, dan transaksi pada ringkasan, lalu tekan **Batal** dan pastikan tidak ada data berubah.
9. Konfirmasikan replace-all dan pastikan aplikasi membuka Save As untuk safety backup terenkripsi dari data aktif sebelum ada data yang diganti.
10. Batalkan Save As tersebut. Restore harus ikut dibatalkan dan data aktif tidak boleh berubah.
11. Ulangi restore, simpan safety backup dengan berhasil, lalu pastikan replace-all baru berjalan setelah penyimpanan dan verifikasi baca ulang selesai.
12. Buka safety backup dengan kata sandi restore yang sama untuk memastikan keadaan sebelum restore dapat dipulihkan.
13. Uji kegagalan penulisan atau baca ulang safety backup bila memungkinkan. Restore harus berhenti dan data aktif tidak boleh berubah.
14. Bandingkan rekening aktif/arsip, kategori, riwayat, saldo, ringkasan bulanan, dan kalender dengan data sumber.
15. Tambahkan rekening, kategori, dan transaksi setelah restore untuk memastikan ID baru tidak bertabrakan.
16. Ulangi dari instalasi atau perangkat terpisah dengan mengambil file dari Downloads/Drive. Tutup aplikasi sepenuhnya setelah restore, buka lagi, dan pastikan data tetap sama.
17. Pastikan dokumen restore lebih dari 16 MiB ditolak selama pembacaan berbatas, plaintext lebih dari 10 MiB ditolak, dan parameter KDF container v1 yang tidak sama persis dengan profil produksi ditolak tanpa mengubah database.
18. Pada HP referensi, periksa waktu derivasi kata sandi, penggunaan memori, layar sempit, ukuran teks besar, keyboard, pembatalan pemilih dokumen, dan ketukan tombol berulang.

### Input, navigasi, dan ketahanan tampilan

- [ ] Instalasi baru menampilkan keadaan kosong yang jelas dan alur tambah rekening dapat dibuka.
- [ ] Nama rekening kosong/duplikat, nominal tidak valid, dan pilihan wajib yang kosong ditolak dengan pesan yang bisa dipahami.
- [ ] Nama rekening tetap dianggap duplikat tanpa membedakan huruf besar/kecil, termasuk jika nama yang sama dimiliki rekening arsip.
- [ ] Transfer ke rekening yang sama tidak dapat disimpan; alur transfer dengan kurang dari dua rekening memberi arahan yang jelas.
- [ ] Form pemasukan hanya menawarkan kategori pemasukan dan form pengeluaran hanya kategori pengeluaran.
- [ ] Form transaksi hanya dapat memilih subkategori; baris kelompok tidak dapat dipilih.
- [ ] Mengganti jenis pengeluaran ke pemasukan atau transfer membersihkan pilihan subkategori lama.
- [ ] Tambah kelompok selalu meminta satu subkategori pertama; nama dan ikon keduanya dapat diedit.
- [ ] Rename/ubah ikon kategori langsung terlihat di riwayat dan detail transaksi lama.
- [ ] Kategori arsip hilang dari pilihan transaksi baru, tetap terbaca pada riwayat, dan dapat dipulihkan.
- [ ] Aplikasi menolak pengarsipan jika tindakan itu menghilangkan subkategori aktif terakhir untuk suatu jenis.
- [ ] Tekan simpan berulang ketika proses sedang berjalan: tidak terjadi transaksi ganda.
- [ ] Batalkan form atau kembali dari pemilih tanggal: data tidak tersimpan tanpa konfirmasi simpan.
- [ ] Tanggal di akhir bulan/tahun masuk ke periode kejadian yang benar.
- [ ] Riwayat dengan lebih dari 50 entri dapat dimuat lanjut tanpa duplikasi atau kehilangan urutan.
- [ ] Coba lebar layar HP kecil, keyboard terbuka, dan ukuran font sistem diperbesar. Form serta tombol tetap dapat dijangkau tanpa overflow.
- [ ] Pindah layar/bulan setelah menyimpan memperbarui rekening dan ringkasan yang terkait.
- [ ] Detail transaksi menampilkan rekening asal/tujuan, kategori, tanggal kejadian, catatan, dan waktu pencatatan yang benar.
- [ ] Form edit terisi dengan nilai lama; simpan berulang tidak menghasilkan operasi ganda dan `createdAt` tidak berubah.
- [ ] Menekan Back setelah mengubah form meminta konfirmasi; memilih tetap tidak membuang input dan memilih buang tidak menyimpan perubahan.
- [ ] Tombol hapus selalu meminta konfirmasi; Batal tidak mengubah data dan kegagalan hapus tidak menutup halaman.
- [ ] Saldo awal dapat dibuka sebagai detail tetapi tidak menawarkan edit atau hapus.
- [ ] Kondisi error repository diuji dengan fake/injeksi kegagalan di pengujian otomatis; jangan sengaja merusak database pribadi untuk mengetes pesan error.

## Riwayat commit yang rapi

Gunakan satu commit untuk satu perubahan logis. Test yang membuktikan sebuah fitur sebaiknya ikut commit fitur tersebut. Tidak perlu membuat commit terpisah untuk setiap berkas.

Contoh pengelompokan pekerjaan fondasi ini:

```text
build: add local finance dependencies and Android metadata
feat(data): persist accounts and ledger with balance tests
feat(ledger): add account and transaction flows with UI tests
feat(accounts): add safe account management
feat(backup): add encrypted manual backup and atomic restore
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

1. Jalankan checklist transaksi, kelola rekening, kalender, serta backup/restore pada HP referensi dan perbaiki setiap ketidaksesuaian.
2. Uji file Downloads dan penyedia dokumen cloud pada perangkat/instalasi terpisah menggunakan data percobaan; ukur juga Argon2id pada HP referensi.
3. Pertahankan ekspor schema dan uji migrasi setiap kali versi database berubah; fitur saat ini tetap memakai schema v3.
4. Setelah jalur pemulihan manual terbukti bekerja, implementasikan fondasi [Alokasi Kategori Transaksi](transaction-allocations.md) bersama schema v4 dan payload backup v2. Migrasikan setiap pemasukan/pengeluaran lama menjadi satu alokasi tanpa mengubah ID transaksi, saldo, atau ringkasan.
5. Setelah persistence, migrasi, backup/restore, dan alur satu alokasi stabil, tambahkan UI split transaction. Form tetap membuka satu alokasi secara default; tombol **+ Tambah kategori lain** menambahkan baris, dan total transaksi dihitung otomatis dari jumlah seluruh nominal alokasi tanpa input total kedua.
6. Setelah split transaction lulus pengujian otomatis dan smoke test perangkat, implementasikan [Anggaran v1](budgets.md) bersama schema v5 dan payload backup v3. Progres anggaran harus menjumlahkan nominal alokasi pengeluaran, bukan total header transaksi.

Jangan menjadikan alpha satu-satunya catatan keuangan sebelum restore lintas instalasi berhasil diuji. Setelah itu pun, buat backup rutin secara berkala dan pertahankan beberapa salinan di luar HP; aplikasi belum membuat backup terjadwal. Safety backup yang wajib saat restore hanya melindungi keadaan tepat sebelum replace-all dan bukan pengganti kebiasaan backup rutin.
