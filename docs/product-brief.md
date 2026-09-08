# Waras Arta — Product Brief

> Catat, atur, tetap waras.

## Informasi Dokumen

- **Status:** Draft
- **Versi produk awal:** `0.1.0`
- **Terakhir diperbarui:** 8 September 2026
- **Platform pertama:** Android
- **Repository:** `waras-arta`
- **Package Dart:** `waras_arta`
- **Application ID:** `io.github.panjiarif.waras_arta`

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

- saldo utama yang siap digunakan;
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
- Memilih rekening, tanggal, dan catatan yang berlaku untuk seluruh transaksi.
- Memasukkan 1–50 alokasi kategori; setiap alokasi mempunyai nominal positif dan satu subkategori yang sesuai jenis transaksi.
- Membuka form dengan satu alokasi secara default agar pencatatan biasa tetap ringkas, lalu menambah baris melalui tombol **+ Tambah rincian** bila satu pembayaran atau penerimaan mencakup beberapa kategori.
- Melihat riwayat berdasarkan bulan atau tahun.
- Mencari dan memfilter transaksi.
- Mengubah atau menghapus transaksi dengan pembaruan saldo yang konsisten.
- Menyimpan tanggal kejadian terpisah dari waktu pencatatan.

Header tetap mewakili satu transaksi dan satu pergerakan saldo. Total bukan input independen: aplikasi menghitungnya otomatis dari jumlah seluruh alokasi lalu menyimpannya pada header. Saldo rekening, arus kas, kalender, dan jumlah transaksi memakai total header tepat sekali; rincian kategori serta anggaran memakai nominal masing-masing alokasi agar transaksi split tidak dihitung ganda.

Aturan lengkap, evolusi schema/backup, serta matriks pengujiannya didokumentasikan dalam [spesifikasi Alokasi Kategori Transaksi](transaction-allocations.md).

Kategori pemasukan dan pengeluaran memiliki tepat dua tingkat:

- kelompok kategori sebagai induk yang tidak dipilih langsung oleh transaksi;
- subkategori sebagai pilihan alokasi transaksi dan identitas yang dipakai laporan;
- nama serta ikon Material kelompok/subkategori dapat diubah;
- kategori yang tidak lagi digunakan diarsipkan agar transaksi lama tetap utuh;
- kategori bawaan dapat dikustomisasi seperti kategori buatan pengguna;
- gambar unggahan pengguna ditunda sampai format backup dapat menyertakan aset dengan aman.

### 4. Transfer Antar-Rekening

Transfer adalah satu jenis transaksi tersendiri dengan:

- rekening asal;
- rekening tujuan;
- nominal;
- tanggal;
- catatan opsional.

Transfer mengurangi saldo rekening asal dan menambah saldo rekening tujuan, tetapi tidak dianggap sebagai pemasukan, pengeluaran, atau pemakaian anggaran. Aturan ini juga berlaku untuk transfer antara **Saldo utama** dan **Simpanan & investasi**: subtotal kedua kelompok berubah, sedangkan total seluruh rekening tetap netral.

### 5. Rekening

- Mendukung rekening bank, dompet tunai, e-wallet, dan tempat penyimpanan uang lainnya.
- Setiap rekening aktif berada pada tepat satu kelompok `balanceGroup`: **Saldo utama** untuk uang yang siap digunakan atau **Simpanan & investasi** untuk tempat uang nyata yang sengaja dipisahkan.
- Menampilkan saldo setiap rekening serta subtotal kedua kelompok aktif secara terpisah pada tab Rekening. Ikhtisar menonjolkan subtotal Saldo utama agar dana tersimpan tidak tampak sebagai uang belanja.
- Menampilkan detail rekening serta memungkinkan nama, jenis, dan kelompok aktifnya diubah tanpa memutus riwayat atau membuat transaksi.
- Perubahan saldo manual dicatat sebagai transaksi penyesuaian bertanda agar dapat ditelusuri, bukan mengubah saldo secara diam-diam. Penyesuaian tidak dihitung sebagai pemasukan atau pengeluaran.
- **Rekening diarsipkan** adalah status terpisah dari kelompok aktif. Rekening hanya dapat diarsipkan ketika saldonya nol dan bukan satu-satunya rekening aktif; kelompok terakhir tetap disimpan agar pemulihan mengembalikannya ke section semula. Rekening arsip disembunyikan secara default dan tidak tersedia untuk transaksi baru.
- Hapus permanen hanya berlaku untuk rekening yang tidak memiliki referensi ledger. Transaksi tidak pernah ikut dihapus secara berantai.

Kelompok **Simpanan & investasi** bukan fitur tujuan keuangan atau pelacakan harga aset. Jika dana darurat hanya merupakan alokasi di dalam rekening bank yang sama, pengguna tidak membuat rekening bayangan karena itu akan menggandakan saldo; kebutuhan tersebut tetap ditangani oleh Tujuan Keuangan mendatang.

### 6. Anggaran

- Anggaran dapat memakai satu bulan kalender, satu tahun kalender, atau rentang tanggal kustom.
- Satu anggaran dapat memakai satu atau beberapa subkategori pengeluaran.
- Pemakaian anggaran bertambah otomatis dari nominal alokasi pengeluaran pada kategori terkait.
- Pemasukan, transfer, dan penyesuaian saldo tidak menggunakan anggaran.
- Batas berlaku untuk seluruh periode dan tidak otomatis dibagi per bulan.
- Satu subkategori dicegah berada pada beberapa anggaran dengan rentang tanggal yang beririsan, termasuk antarjenis periode.
- Progres tidak disimpan, tetapi dihitung ulang dari alokasi kategori beserta tanggal transaksi induknya agar edit/hapus transaksi tetap konsisten.
- Pengeluaran tetap boleh dicatat setelah batas terlampaui.

Aturan lengkap, schema yang direncanakan, kompatibilitas backup, dan matriks pengujian tersedia pada [spesifikasi Anggaran v1](budgets.md).

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

- Menambah navigasi bawah utama menjadi empat tujuan untuk penggunaan di HP.
- Menampilkan grid bulanan ringan dengan urutan Senin sampai Minggu, mulai Januari 2000 hingga bulan berjalan.
- Menonaktifkan tanggal setelah hari ini karena versi awal belum mendukung transaksi masa depan.
- Memberi penanda terpisah untuk pemasukan, pengeluaran, dan aktivitas lain berupa transfer atau penyesuaian.
- Menampilkan total pemasukan/pengeluaran harian serta jumlah dan daftar lengkap keempat jenis transaksi ketika tanggal dipilih.
- Membuka detail ketika transaksi pada daftar harian diketuk.
- Memudahkan pencatatan transaksi lampau dengan mengisi tanggal awal form dari tanggal kalender yang dipilih.
- Menghitung ringkasan dari seluruh ledger bulan/tanggal terkait, terpisah dari pagination riwayat yang dimulai dari 50 entri.

### 11. Backup dan Restore

- Database kerja disimpan secara lokal.
- Pengguna dapat membuat backup manual ke lokasi yang dipilih, termasuk penyedia dokumen seperti Google Drive atau OneDrive melalui Storage Access Framework Android.
- Dokumen restore dibaca langsung dari URI penyedia sebagai stream berbatas ukuran tanpa salinan cache perantara milik aplikasi.
- Format backup dan container enkripsi memiliki versi terpisah agar dapat dimigrasikan pada versi aplikasi berikutnya.
- Setiap backup memuat seluruh data fitur yang didukung oleh versi pembuatnya untuk restore, bukan hanya laporan CSV.
- Setiap file backup dienkripsi dengan kunci berbasis kata sandi menggunakan Argon2id dan XChaCha20-Poly1305; tidak tersedia mode backup JSON polos pada antarmuka pengguna.
- Kata sandi tidak disimpan dan tidak dapat dipulihkan. Jika pengguna lupa, file backup tidak dapat direstore; peringatan ini harus terlihat sebelum pembuatan backup.
- Restore memvalidasi kata sandi, integritas, format, versi, dan relasi data, lalu menampilkan ringkasan sebelum mengganti data aktif.
- Versi awal menggunakan strategi **replace all**, belum mendukung penggabungan dua database.
- Setelah konfirmasi restore, aplikasi wajib membuat safety backup terenkripsi dari data aktif dengan kata sandi restore yang sama. File harus selesai ditulis, dibuka ulang, serta cocok dalam jumlah byte dan SHA-256 sebelum replace-all dimulai; pembatalan atau kegagalan penulisan/verifikasi menghentikan restore tanpa mengubah database.
- Penggantian berlangsung atomik: kegagalan membatalkan seluruh perubahan database.
- Container v1 hanya menerima profil Argon2id produksi secara persis. Ukuran file terenkripsi dibatasi 16 MiB dan plaintext hasil dekripsi dibatasi 10 MiB.
- Payload v3/schema v5 saat ini mencakup rekening beserta `balanceGroup`, kategori, seluruh header ledger, dan allocation. Payload v1/schema 3 dan v2/schema 4 tetap dapat dibaca dengan `balanceGroup = primary`; Anggaran mendatang menaikkan format ke payload v4/schema v6.
- Backup adalah snapshot manual, bukan sinkronisasi atau jadwal otomatis. Lokasi cloud dipilih pengguna melalui penyedia dokumen Android; aplikasi tidak mengunggah file sendiri.
- Ekspor CSV disediakan sebagai laporan terpisah dan bukan format utama restore.

## Aturan Data Utama

1. Pemasukan menambah saldo rekening tujuan.
2. Pengeluaran mengurangi saldo rekening sumber.
3. Transfer memindahkan saldo antara dua rekening, termasuk lintas kelompok aktif, dan bernilai netral terhadap arus kas serta total seluruh rekening.
4. Saldo tidak boleh diedit tanpa catatan; koreksi dibuat sebagai transaksi penyesuaian.
5. Perhitungan periode menggunakan tanggal kejadian (`occurredAt`), bukan waktu data dibuat (`createdAt`).
6. Nilai rupiah disimpan sebagai bilangan bulat untuk menghindari kesalahan pembulatan floating-point.
7. Setiap rekening aktif tepat berada pada kelompok `primary` atau `savingsInvestment`; arsip adalah status terpisah dan menyimpan kelompok terakhir untuk pemulihan.
8. Rekening bersaldo nol dapat diarsipkan selama masih ada rekening aktif lain; rekening arsip tidak dapat dipakai untuk transaksi baru.
9. Kategori yang sudah digunakan diarsipkan, bukan dihapus, agar referensi transaksi lama tetap utuh.
10. Perubahan transaksi lama harus menghitung ulang rekening, anggaran, dan ringkasan terkait secara konsisten.
11. Transaksi lama yang menyentuh rekening arsip tetap dapat dilihat, tetapi hanya dapat diedit atau dihapus setelah rekening dipulihkan.
12. Rekening hanya dapat dihapus permanen jika tidak memiliki referensi ledger sebagai sumber maupun tujuan; penghapusan tidak pernah melakukan cascade ke transaksi.
13. Setiap pemasukan/pengeluaran memiliki 1–50 alokasi kategori dengan jumlah nominal persis sama dengan total transaksi; transfer dan penyesuaian saldo tidak memiliki alokasi kategori.
14. Alokasi kategori hanya mengklasifikasikan transaksi dan tidak mengubah saldo secara terpisah. Saldo serta arus kas menghitung header satu kali, sedangkan laporan kategori dan anggaran menghitung nominal alokasi.

## Ruang Lingkup Versi

### Versi 0.1 — Fondasi/MVP

- rekening dengan kelompok Saldo utama/Simpanan & investasi serta status arsip terpisah;
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

- fondasi alokasi kategori transaksi dan alur split transaction *(sudah tersedia pada alpha saat ini)*;
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

1. membuat beberapa rekening, mengelompokkannya sebagai Saldo utama atau Simpanan & investasi, dan melihat subtotal serta total yang benar;
2. mencatat pemasukan, pengeluaran, transfer, serta transaksi pada tanggal lampau;
3. melihat riwayat, kalender, dan ringkasan bulanan yang konsisten;
4. menutup dan membuka kembali aplikasi tanpa kehilangan data;
5. membuat backup, menghapus atau mengganti data aktif, kemudian merestore backup dengan hasil yang sama;
6. menggunakan alur utama dengan nyaman pada perangkat referensi;
7. memastikan transfer hanya memindahkan saldo antar-rekening tanpa mengubah total pemasukan atau pengeluaran.

## Pertanyaan Terbuka

- Warna, ikon, dan identitas visual final.
- Perlukah penguncian aplikasi menggunakan PIN atau biometrik pada MVP?
- Apakah transaksi berulang perlu dimajukan ke versi 0.2?
- Apakah hanya rupiah yang didukung pada versi awal?
- Apakah alokasi tujuan keuangan perlu dibatasi agar tidak melebihi saldo rekening?

## Keputusan yang Sudah Disepakati

- Nama kerja aplikasi adalah **Waras Arta**.
- Android adalah target pertama.
- Aplikasi menggunakan pendekatan local-first.
- Transfer adalah jenis transaksi tersendiri dan netral terhadap pemasukan/pengeluaran.
- Rekening aktif dibagi menjadi **Saldo utama** dan **Simpanan & investasi**; Ikhtisar menampilkan Saldo utama, sedangkan arsip tetap merupakan status terpisah.
- Tujuan keuangan dipisahkan dari rekening nyata.
- Koreksi saldo harus dapat ditelusuri.
- Backup dan restore merupakan bagian dari produk, bukan fitur tambahan opsional.
- MVP didahulukan sebelum dashboard yang sangat fleksibel dan analitik lanjutan.
- Pada schema v4, alokasi pemasukan/pengeluaran menyimpan ID subkategori, bukan nama kategori; header transaksi tidak lagi menyimpan kategori langsung.
- Hierarki kategori dibatasi dua tingkat agar kalender, anggaran, diagram, dan filter memiliki fondasi yang konsisten.
- Kategori bawaan lama menjadi kelompok dengan subkategori `Umum` saat migrasi schema v1 ke v2.
- Koreksi saldo disimpan sebagai penyesuaian ledger bertanda dan tidak masuk ringkasan pemasukan/pengeluaran; entri penyesuaian tidak dapat diedit atau dihapus.
- Rekening hanya dapat diarsipkan pada saldo nol, bukan ketika menjadi satu-satunya rekening aktif, dan dapat dipulihkan kapan saja.
- Rekening arsip tidak tersedia untuk transaksi baru. Transaksi lama tetap utuh, sedangkan edit/hapusnya menunggu rekening dipulihkan.
- Hapus rekening permanen hanya berlaku jika tidak ada referensi ledger dan tidak menghapus transaksi secara berantai.
- Migrasi schema v2 ke v3 menambahkan siklus arsip rekening dan dukungan penyesuaian saldo bertanda tanpa mengubah arus kas lama.
- Kalender diperkenalkan dengan memakai `occurredDay` dan indeks ledger yang sudah ada tanpa menaikkan schema 3; schema aktif kemudian naik ke v4 untuk allocation transaksi.
- Schema aktif v5 menambahkan `balanceGroup` rekening. Migrasi memberi seluruh rekening lama nilai `primary`, dan payload backup v3 membawa nilai `primary` atau `savingsInvestment` secara eksplisit.
- Kalender dibatasi Januari 2000 sampai hari ini, menggunakan pekan Senin–Minggu, dan menyertakan seluruh jenis transaksi pada daftar harian.
- Backup manual menggunakan file `.warasarta` terenkripsi berbasis kata sandi, sedangkan restore memakai validasi, preview, konfirmasi replace-all, dan transaksi atomik.
- Enkripsi backup tidak berarti database SQLite aktif sudah terenkripsi; perlindungan database kerja dan PIN/biometrik tetap keputusan terpisah.
- Backup/restore harus diverifikasi pada Downloads, penyedia dokumen cloud, dan instalasi/perangkat berbeda sebelum aplikasi dipercaya sebagai satu-satunya catatan keuangan.
- Pemasukan/pengeluaran mempunyai 1–50 alokasi kategori dengan satu alokasi sebagai default. Tombol plus menambah rincian kategori tanpa mengubah transaksi menjadi beberapa pergerakan saldo.
- Total transaksi menjadi sumber perubahan saldo dan arus kas, sedangkan nominal alokasi menjadi sumber laporan kategori serta progres anggaran; keduanya wajib selalu berjumlah sama.
- Fondasi alokasi kategori dan split transaction sudah dikerjakan sebelum Anggaran v1 agar anggaran sejak awal menghitung bagian kategori, bukan menggandakan total transaksi.
