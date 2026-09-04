# Waras Arta — Product Brief

> Catat, atur, tetap waras.

## Informasi Dokumen

- **Status:** Draft
- **Versi produk awal:** `0.1.0`
- **Terakhir diperbarui:** 27 Agustus 2026
- **Platform pertama:** Android
- **Repository:** `waras-arta`
- **Package Dart:** `waras_arta`
- **Application ID yang direncanakan:** `io.github.panjiarif.warasarta`

## Ringkasan

Waras Arta adalah aplikasi pengelolaan keuangan pribadi yang membantu pengguna mencatat transaksi, memantau saldo berbagai rekening, memahami arus kas, dan merencanakan penggunaan uang. Aplikasi dirancang dengan pendekatan **local-first**: seluruh fungsi utama dapat digunakan tanpa akun dan tanpa koneksi internet, sementara data tetap dapat dicadangkan dan dipulihkan saat pengguna berganti atau kehilangan perangkat.

Proyek ini dibuat untuk memenuhi kebutuhan pribadi sekaligus menjadi portofolio pengembangan aplikasi Flutter yang mengutamakan ketepatan data, performa pada perangkat terbatas, arsitektur yang terawat, dan riwayat pengembangan yang terdokumentasi.

## Masalah yang Ingin Diselesaikan

Aplikasi anggaran yang tersedia sering mengunci fitur penting di balik langganan. Pengguna membutuhkan aplikasi yang:

- dapat digunakan sepenuhnya untuk kebutuhan pencatatan pribadi;
- bekerja cepat pada perangkat dengan spesifikasi terbatas;
- tidak bergantung pada layanan cloud agar dapat berfungsi;
- memperlakukan transfer antar-rekening secara benar;
- dapat mencatat transaksi pada tanggal yang sudah lewat;
- memiliki mekanisme backup dan restore yang dapat dibawa ke perangkat baru;
- transparan mengenai cara saldo dan ringkasan dihitung.

## Target Pengguna

Target awal adalah pemilik aplikasi sendiri: pengguna Android yang mengelola beberapa rekening, dompet tunai, dan e-wallet serta ingin mencatat keuangan secara rutin.

Karakteristik pengguna:

- melakukan pencatatan manual;
- menggunakan rupiah sebagai mata uang utama;
- memiliki lebih dari satu tempat penyimpanan uang;
- memerlukan pencatatan mundur berdasarkan tanggal kejadian;
- ingin data tetap privat dan dapat dipindahkan ke perangkat lain.

## Tujuan Produk

1. Membuat pencatatan pemasukan, pengeluaran, dan transfer menjadi cepat dan jelas.
2. Menampilkan posisi saldo serta arus kas secara akurat.
3. Membantu pengguna mengendalikan pengeluaran melalui anggaran.
4. Membantu pengguna memisahkan tujuan keuangan dari lokasi uang sebenarnya.
5. Menjaga data tetap tersedia melalui backup dan restore yang aman.
6. Tetap nyaman digunakan pada perangkat referensi Android 11 dengan RAM 4 GB dan Snapdragon 460.

## Prinsip Produk

- **Local-first:** fungsi utama tidak memerlukan internet.
- **Privat:** data keuangan tidak dikirim ke server secara otomatis.
- **Akurat:** setiap perubahan saldo harus dapat ditelusuri.
- **Cepat:** interaksi utama harus nyaman pada perangkat kelas bawah.
- **Sederhana:** alur pencatatan tidak dikorbankan demi terlalu banyak opsi.
- **Tahan lama:** perubahan skema data harus menggunakan migrasi yang teruji.
- **Dapat dipulihkan:** backup bukan sekadar ekspor laporan, tetapi salinan data yang dapat direstore.

## Fitur Produk

### 1. Ikhtisar

Dashboard yang menampilkan informasi penting secara cepat, seperti:

- saldo total;
- ringkasan pemasukan dan pengeluaran bulan berjalan;
- rekening;
- transaksi terbaru;
- progres anggaran;
- progres tujuan keuangan;
- grafik saldo atau arus kas.

Versi awal menggunakan susunan tetap. Pengaturan kartu dan urutan dashboard direncanakan setelah fondasi utama stabil.

### 2. Ringkasan

- Total pemasukan dan pengeluaran per bulan.
- Selisih bersih pemasukan dan pengeluaran.
- Perbandingan dengan periode sebelumnya.
- Rincian berdasarkan kategori.
- Transfer antar-rekening tidak dihitung sebagai pemasukan atau pengeluaran.

### 3. Transaksi

- Mencatat pemasukan dan pengeluaran.
- Memilih rekening, kategori, nominal, tanggal, dan catatan.
- Melihat riwayat berdasarkan bulan atau tahun.
- Mencari dan memfilter transaksi.
- Mengubah atau menghapus transaksi dengan pembaruan saldo yang konsisten.
- Menyimpan tanggal kejadian terpisah dari waktu pencatatan.

### 4. Transfer Antar-Rekening

Transfer adalah satu jenis transaksi tersendiri dengan:

- rekening asal;
- rekening tujuan;
- nominal;
- tanggal;
- catatan opsional.

Transfer mengurangi saldo rekening asal dan menambah saldo rekening tujuan, tetapi tidak dianggap sebagai pemasukan, pengeluaran, atau pemakaian anggaran.

### 5. Rekening

- Mendukung rekening bank, dompet tunai, e-wallet, dan tempat penyimpanan uang lainnya.
- Menampilkan saldo setiap rekening dan saldo total.
- Mendukung pengarsipan rekening yang tidak lagi digunakan.
- Perubahan saldo manual dicatat sebagai transaksi penyesuaian agar dapat ditelusuri, bukan mengubah saldo secara diam-diam.

### 6. Anggaran

- Anggaran dibuat untuk satu bulan.
- Satu anggaran dapat memakai satu atau beberapa kategori pengeluaran.
- Pemakaian anggaran bertambah otomatis ketika ada pengeluaran pada kategori terkait.
- Pemasukan, transfer, dan penyesuaian saldo tidak menggunakan anggaran.
- Kategori yang tumpang tindih pada beberapa anggaran aktif harus diperingatkan atau dicegah.

### 7. Tujuan Keuangan

Tujuan keuangan digunakan untuk kebutuhan seperti dana darurat, tabungan perangkat, atau liburan.

- Tujuan adalah maksud penggunaan uang, bukan tempat uang disimpan.
- Dana tujuan dapat dialokasikan dari satu atau beberapa rekening nyata.
- Alokasi tujuan tidak dianggap sebagai pemasukan atau pengeluaran.
- Jika uang benar-benar dipindahkan ke rekening atau celengan terpisah, pengguna membuat rekening baru dan mencatat transfer.

### 8. Utang

- Mencatat utang yang harus dibayar atau piutang yang harus diterima.
- Menyimpan pihak terkait, nominal awal, sisa, tanggal, dan status.
- Pembayaran dapat dikaitkan dengan transaksi rekening.

Fitur ini direncanakan setelah pencatatan transaksi dan anggaran stabil.

### 9. Diagram

- Tren pemasukan dan pengeluaran.
- Komposisi pengeluaran berdasarkan kategori.
- Perubahan saldo.
- Progres anggaran dan tujuan keuangan.

Grafik menggunakan data agregat agar tetap ringan ketika jumlah transaksi bertambah.

### 10. Kalender

- Menampilkan transaksi per tanggal.
- Memudahkan pencatatan transaksi yang sudah terlewat.
- Menampilkan ringkasan pemasukan dan pengeluaran harian.
- Membuka daftar transaksi saat tanggal dipilih.

### 11. Backup dan Restore

- Database kerja disimpan secara lokal.
- Pengguna dapat membuat backup manual ke lokasi yang dipilih, termasuk penyedia dokumen seperti Google Drive atau OneDrive melalui pemilih berkas Android.
- Format backup memiliki versi agar dapat dimigrasikan pada versi aplikasi berikutnya.
- Backup berisi data lengkap untuk restore, bukan hanya laporan CSV.
- Backup dapat dienkripsi menggunakan kata sandi yang dimiliki pengguna.
- Restore memvalidasi format dan versi, menampilkan ringkasan, lalu membuat safety backup sebelum mengganti data aktif.
- Versi awal menggunakan strategi **replace all**, belum mendukung penggabungan dua database.
- Ekspor CSV disediakan sebagai laporan terpisah dan bukan format utama restore.

## Aturan Data Utama

1. Pemasukan menambah saldo rekening tujuan.
2. Pengeluaran mengurangi saldo rekening sumber.
3. Transfer memindahkan saldo antara dua rekening dan bernilai netral terhadap arus kas.
4. Saldo tidak boleh diedit tanpa catatan; koreksi dibuat sebagai transaksi penyesuaian.
5. Perhitungan periode menggunakan tanggal kejadian (`occurredAt`), bukan waktu data dibuat (`createdAt`).
6. Nilai rupiah disimpan sebagai bilangan bulat untuk menghindari kesalahan pembulatan floating-point.
7. Rekening dan kategori yang sudah digunakan sebaiknya diarsipkan, bukan dihapus permanen.
8. Perubahan transaksi lama harus menghitung ulang rekening, anggaran, dan ringkasan terkait secara konsisten.

## Ruang Lingkup Versi

### Versi 0.1 — Fondasi/MVP

- rekening;
- kategori;
- pemasukan dan pengeluaran;
- transfer antar-rekening;
- transaksi penyesuaian saldo;
- riwayat transaksi;
- kalender;
- ringkasan bulanan;
- dashboard sederhana dengan susunan tetap;
- backup dan restore manual;
- pengujian aturan saldo serta migrasi database.

### Versi 0.2 — Perencanaan dan Analisis

- anggaran multi-kategori;
- tujuan keuangan;
- diagram;
- kustomisasi dashboard;
- pencarian dan filter lanjutan;
- ekspor CSV.

### Versi 0.3 — Kewajiban dan Penyempurnaan

- utang dan piutang;
- transaksi berulang;
- peningkatan keamanan dan kenyamanan;
- penyempurnaan berdasarkan penggunaan nyata.

## Di Luar Ruang Lingkup Awal

- sinkronisasi rekening bank secara otomatis;
- sinkronisasi real-time antarperangkat;
- akun dan server backend wajib;
- pembayaran langsung dari aplikasi;
- pengelolaan investasi dan harga aset;
- pembukuan bisnis atau akuntansi perusahaan;
- penggunaan bersama oleh banyak pengguna;
- pemindaian struk menggunakan OCR;
- rekomendasi keuangan berbasis AI.

## Arah Teknis Awal

Keputusan teknis rinci akan dicatat dalam dokumen arsitektur terpisah. Arah awalnya adalah:

- Flutter dan Dart;
- Material 3;
- MVVM dengan unidirectional data flow;
- Riverpod untuk state management dan dependency injection;
- Repository sebagai batas antara data dan logika tampilan;
- Drift di atas SQLite untuk penyimpanan lokal;
- `go_router` untuk navigasi;
- pekerjaan database berat dijalankan di background isolate;
- Android sebagai platform pertama, dengan peluang ekspansi platform setelah MVP stabil.

## Kriteria Keberhasilan MVP

MVP dianggap berhasil ketika pengguna dapat:

1. membuat beberapa rekening dan melihat saldo yang benar;
2. mencatat pemasukan, pengeluaran, transfer, serta transaksi pada tanggal lampau;
3. melihat riwayat, kalender, dan ringkasan bulanan yang konsisten;
4. menutup dan membuka kembali aplikasi tanpa kehilangan data;
5. membuat backup, menghapus atau mengganti data aktif, kemudian merestore backup dengan hasil yang sama;
6. menggunakan alur utama dengan nyaman pada perangkat referensi;
7. memastikan transfer tidak mengubah total pemasukan, pengeluaran, atau pemakaian anggaran.

## Pertanyaan Terbuka

- Warna, ikon, dan identitas visual final.
- Perlukah penguncian aplikasi menggunakan PIN atau biometrik pada MVP?
- Apakah transaksi berulang perlu dimajukan ke versi 0.2?
- Apakah hanya rupiah yang didukung pada versi awal?
- Apakah alokasi tujuan keuangan perlu dibatasi agar tidak melebihi saldo rekening?
- Kebijakan penghapusan permanen dan masa penyimpanan data yang diarsipkan.

## Keputusan yang Sudah Disepakati

- Nama kerja aplikasi adalah **Waras Arta**.
- Android adalah target pertama.
- Aplikasi menggunakan pendekatan local-first.
- Transfer adalah jenis transaksi tersendiri dan netral terhadap pemasukan/pengeluaran.
- Tujuan keuangan dipisahkan dari rekening nyata.
- Koreksi saldo harus dapat ditelusuri.
- Backup dan restore merupakan bagian dari produk, bukan fitur tambahan opsional.
- MVP didahulukan sebelum dashboard yang sangat fleksibel dan analitik lanjutan.
