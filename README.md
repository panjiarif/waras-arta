# Waras Arta

> Catat, atur, tetap waras.

Aplikasi keuangan pribadi berbasis Flutter dengan pendekatan local-first. Target pertama adalah Android, dengan antarmuka bahasa Indonesia dan mata uang rupiah.

## Status: alpha pertama

Ini adalah irisan awal menuju versi 0.1 pada [product brief](docs/product-brief.md), **belum MVP lengkap**.

Yang tersedia:

- Membuat rekening tunai, bank, e-wallet, atau lainnya pada kelompok aktif **Saldo utama** atau **Simpanan & investasi**, dengan saldo awal yang dicatat sebagai penyesuaian ledger.
- Membuka detail rekening, mengubah nama/jenis/kelompok, serta mengoreksi saldo melalui entri penyesuaian bertanda yang dapat ditelusuri dan tidak masuk ringkasan arus kas.
- Memisahkan rekening aktif dari **Rekening diarsipkan**; rekening bersaldo nol dapat diarsipkan dan dipulihkan ke kelompok aktif sebelumnya, sedangkan rekening tanpa referensi ledger dapat dihapus permanen tanpa menghapus riwayat secara berantai.
- Mencatat pemasukan dan pengeluaran dengan 1–50 rincian nominal–subkategori, tanggal kejadian, dan catatan; total split dihitung otomatis.
- Mengelola kategori pemasukan/pengeluaran dalam hierarki dua tingkat: kelompok dan subkategori.
- Mengubah nama serta ikon Material kategori, lalu mengarsipkannya tanpa memutus riwayat lama.
- Transfer satu transaksi antar-rekening sendiri, termasuk lintas kelompok saldo, tidak dihitung sebagai pemasukan/pengeluaran dan tidak mengubah total seluruh rekening.
- Kalender bulanan Senin–Minggu dengan penanda pemasukan, pengeluaran, serta aktivitas lain per tanggal.
- Memilih tanggal menampilkan total harian dan seluruh pemasukan, pengeluaran, transfer, serta penyesuaian pada hari tersebut.
- Pencatatan tanggal lampau melalui kalender atau pemilih tanggal; tombol tambah pada tab kalender otomatis memakai tanggal yang dipilih.
- Ikhtisar saldo utama yang siap digunakan dan ringkasan bulanan; subtotal Saldo utama serta Simpanan & investasi tersedia terpisah pada tab Rekening.
- Riwayat bulanan yang dimuat bertahap mulai 50 entri.
- Detail transaksi beserta nama rekening, tanggal kejadian, catatan, waktu pencatatan, dan seluruh rincian split.
- Edit transaksi biasa dengan perhitungan ulang saldo dan ringkasan.
- Hapus permanen transaksi biasa melalui dialog konfirmasi.
- Penyimpanan persisten lokal menggunakan Drift/SQLite.
- Migrasi schema bertahap v1 sampai v5 yang menjaga transaksi serta saldo lama ketika kategori, siklus rekening, alokasi transaksi, dan kelompok saldo berevolusi.
- Backup manual terenkripsi ke file `.warasarta` melalui pemilih dokumen Android; hasil simpan dibuka ulang dan diverifikasi sebelum dianggap berhasil.
- Restore replace-all dengan pemeriksaan kata sandi, ringkasan isi, konfirmasi, transaksi database atomik, dan safety backup terenkripsi yang wajib disimpan lebih dahulu.

`Saldo utama` dan `Simpanan & investasi` adalah kelompok rekening aktif, sedangkan arsip merupakan status terpisah. Rekening arsip disembunyikan secara default, tetap dapat ditampilkan, menyimpan kelompok aktif terakhirnya untuk pemulihan, serta tidak dapat dipilih untuk transaksi baru. Entri penyesuaian, termasuk saldo awal, bersifat tetap agar jejak perubahan saldo tidak ditulis ulang.

Backup aktif memakai payload v3/schema v5 dan membawa `balanceGroup` setiap rekening. Restore payload v1/schema 3 atau v2/schema 4 tetap didukung; karena format lama belum mempunyai field tersebut, seluruh rekening lama dipetakan ke `Saldo utama`.

Belum tersedia: gambar kategori unggahan pengguna, backup rutin terjadwal, anggaran, tujuan keuangan, diagram, dan utang/piutang.

Backup rutin adalah snapshot manual saat tombol ditekan; aplikasi belum menjadwalkan, mengunggah, merotasi, atau memverifikasi backup secara otomatis. Verifikasi tepat setelah penulisan hanya memastikan ukuran dan SHA-256 file yang baru disimpan cocok pada saat itu, bukan memantau retensi file berikutnya. Pengecualiannya adalah jalur restore: setelah pengguna mengonfirmasi restore, aplikasi wajib menyimpan safety backup terenkripsi dari data aktif dengan kata sandi yang sama sebelum melakukan replace-all. Jika penyimpanan dibatalkan, gagal, atau tidak lolos verifikasi penulisan, restore tidak dijalankan. Simpan beberapa file di luar HP, misalnya pada penyedia dokumen cloud dan komputer, lalu uji restore menggunakan data percobaan sebelum mengandalkannya. **Kata sandi backup tidak disimpan dan tidak dapat dipulihkan. Jika lupa, file tersebut tidak dapat direstore.**

File backup dienkripsi, tetapi database SQLite yang sedang dipakai aplikasi belum dienkripsi khusus oleh Waras Arta. Penyimpanan privat Android juga bukan jaminan pemulihan: uninstall, hapus data, atau kehilangan HP tetap dapat menghilangkan data yang belum masuk backup terbaru.

Backup otomatis dan transfer data aplikasi milik Android dinonaktifkan serta dikecualikan lewat aturan platform agar database kerja yang belum dienkripsi tidak menjadi salinan portabel di luar alur `.warasarta`. Konsekuensinya, pindah HP harus dilakukan dengan membuat dan merestore file backup terenkripsi secara manual.

## Mulai mengembangkan

Siapkan Flutter, JDK 17, Android SDK, dan HP dengan USB debugging. Dari root repository:

```bash
flutter pub get
dart run build_runner build
flutter analyze
flutter test
flutter devices
flutter run -d DEVICE_ID
```

Ganti `DEVICE_ID` dengan ID HP. Proyek ini belum menargetkan runtime web atau desktop. Lihat [panduan pengembangan](docs/development.md) untuk checklist manual dan alur commit.

## Fondasi teknis

Flutter/Dart, Material 3, MVVM dengan Riverpod, repository, Drift/SQLite dengan background isolate, dan `go_router`. Saldo berasal dari ledger, nominal menggunakan bilangan bulat rupiah, periode transaksi berdasarkan tanggal kejadian, dan identitas kategori memakai ID stabil.

- [Product brief dan ruang lingkup versi](docs/product-brief.md)
- [Spesifikasi Alokasi Kategori Transaksi](docs/transaction-allocations.md)
- [Spesifikasi Anggaran v1](docs/budgets.md)
- [Arsitektur dan aturan data](docs/architecture.md)
- [Format, keamanan, dan pemulihan backup](docs/backup-restore.md)
- [Pengembangan, verifikasi, dan commit](docs/development.md)

Package Dart: `waras_arta`. Application ID Android saat ini: `io.github.panjiarif.waras_arta`; nama tampilan: **Waras Arta**.
