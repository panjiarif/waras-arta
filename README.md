# Waras Arta

> Catat, atur, tetap waras.

Aplikasi keuangan pribadi berbasis Flutter dengan pendekatan local-first. Target pertama adalah Android, dengan antarmuka bahasa Indonesia dan mata uang rupiah.

## Status: alpha pertama

Ini adalah irisan awal menuju versi 0.1 pada [product brief](docs/product-brief.md), **belum MVP lengkap**.

Yang tersedia:

- Membuat rekening tunai, bank, e-wallet, atau lainnya dengan saldo awal yang dicatat sebagai penyesuaian ledger.
- Membuka detail rekening, mengubah nama/jenis, serta mengoreksi saldo melalui entri penyesuaian bertanda yang dapat ditelusuri dan tidak masuk ringkasan arus kas.
- Mengarsipkan rekening bersaldo nol, memulihkannya, atau menghapus permanen rekening yang tidak memiliki referensi ledger tanpa menghapus riwayat secara berantai.
- Mencatat pemasukan dan pengeluaran dengan subkategori, tanggal kejadian, dan catatan.
- Mengelola kategori pemasukan/pengeluaran dalam hierarki dua tingkat: kelompok dan subkategori.
- Mengubah nama serta ikon Material kategori, lalu mengarsipkannya tanpa memutus riwayat lama.
- Transfer satu transaksi antar-rekening sendiri, tidak dihitung sebagai pemasukan/pengeluaran.
- Kalender bulanan Senin–Minggu dengan penanda pemasukan, pengeluaran, serta aktivitas lain per tanggal.
- Memilih tanggal menampilkan total harian dan seluruh pemasukan, pengeluaran, transfer, serta penyesuaian pada hari tersebut.
- Pencatatan tanggal lampau melalui kalender atau pemilih tanggal; tombol tambah pada tab kalender otomatis memakai tanggal yang dipilih.
- Ikhtisar saldo seluruh rekening dan ringkasan bulanan.
- Riwayat bulanan yang dimuat bertahap mulai 50 entri.
- Detail transaksi beserta nama rekening, tanggal kejadian, catatan, dan waktu pencatatan.
- Edit transaksi biasa dengan perhitungan ulang saldo dan ringkasan.
- Hapus permanen transaksi biasa melalui dialog konfirmasi.
- Penyimpanan persisten lokal menggunakan Drift/SQLite.
- Migrasi schema bertahap v1 ke v2 dan v2 ke v3 yang menjaga transaksi serta saldo lama ketika kategori dan siklus rekening berevolusi.

Rekening arsip disembunyikan secara default, tetap dapat ditampilkan dan dipulihkan, serta tidak dapat dipilih untuk transaksi baru. Entri penyesuaian, termasuk saldo awal, bersifat tetap agar jejak perubahan saldo tidak ditulis ulang.

Belum tersedia: gambar kategori unggahan pengguna, backup/restore, anggaran, tujuan keuangan, diagram, dan utang/piutang.

**Gunakan data percobaan atau pertahankan catatan utama di tempat lain.** Alpha belum memiliki backup/restore maupun enkripsi database khusus aplikasi. Penyimpanan privat Android bukan jaminan pemulihan. Uninstall, hapus data, atau kerusakan/kehilangan HP dapat menghilangkan catatan. Jangan menjadikan alpha satu-satunya catatan keuangan.

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
- [Arsitektur dan aturan data](docs/architecture.md)
- [Pengembangan, verifikasi, dan commit](docs/development.md)

Package Dart: `waras_arta`. Application ID Android saat ini: `io.github.panjiarif.waras_arta`; nama tampilan: **Waras Arta**.
