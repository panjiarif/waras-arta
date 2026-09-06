# Arsitektur Waras Arta

## Status dan lingkup

Dokumen ini menjelaskan fondasi alpha pertama, bukan seluruh fitur target pada [product brief](product-brief.md). Target runtime pertama adalah Android. Mata uang yang didukung saat ini hanya rupiah tanpa pecahan.

Identitas Android yang dipertahankan dari proyek awal adalah `io.github.panjiarif.waras_arta`. Identitas `io.github.panjiarif.warasarta` pada product brief masih berupa rencana; implementasi ini tidak menggantinya. Nama tampilan adalah **Waras Arta**. Mengganti application ID harus menjadi keputusan tersendiri karena Android akan memperlakukannya sebagai aplikasi berbeda.

## Pembagian tanggung jawab

Waras Arta memakai MVVM dengan repository dan aliran data satu arah. Pemisahan View, ViewModel, dan data layer mengikuti arah [rekomendasi arsitektur Flutter](https://docs.flutter.dev/app-architecture/recommendations). Riverpod dipilih untuk penyediaan dependensi serta pengamatan state; penggunaan Riverpod sendiri bukan definisi MVVM.

```text
Interaksi pengguna
        |
        v
View -> ViewModel -> FinanceRepository -> Drift / SQLite
  ^         ^                                |
  |         +----------- data ---------------+
  +-------------- state ---------------------+
```

- **View:** widget Material 3 berbahasa Indonesia, input form, tampilan loading/error, dan navigasi.
- **ViewModel:** pilihan bulan, batas jumlah riwayat, pemuatan data, serta operasi tambah, edit, dan hapus. Tidak menyimpan `BuildContext` atau mengakses SQL secara langsung.
- **Domain:** model immutable, jenis rekening/transaksi, kategori awal, draft input, dan kontrak repository. Belum ada lapisan use case terpisah.
- **Repository:** validasi aturan keuangan, operasi database, dan pemetaan hasil query ke model domain.
- **Database:** tabel, constraint, indeks, dan koneksi persisten. SQLite adalah sumber data utama, bukan cache tampilan.

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
├── core/
│   └── formatters.dart
├── domain/
│   ├── finance.dart
│   └── finance_repository.dart
├── data/
│   ├── database/
│   │   ├── app_database.dart
│   │   └── app_database.g.dart
│   └── repositories/
│       └── drift_finance_repository.dart
└── features/
    └── ledger/
        ├── view_models/ledger_view_model.dart
        └── views/
            ├── home_screen.dart
            ├── account_form_screen.dart
            ├── entry_detail_screen.dart
            ├── entry_form_screen.dart
            └── form_widgets.dart
```

Fitur rekening dan transaksi dikelompokkan sebagai satu irisan `ledger` untuk tahap awal. Pecah menjadi fitur terpisah ketika tanggung jawabnya bertambah, bukan dengan menambahkan direktori kosong sejak awal. `go_router` menangani rute layar; [Riverpod](https://riverpod.dev/docs/introduction/getting_started) menghubungkan repository dan ViewModel agar dependensi bisa diganti saat pengujian.

## Model saldo dan transaksi

Database menyimpan rekening dan ledger. Rekening tidak memiliki saldo yang diedit langsung; saldo dihitung dari transaksi sepanjang waktu.

| Jenis | Perubahan saldo | Ringkasan pemasukan/pengeluaran |
| --- | --- | --- |
| Pemasukan | Menambah rekening yang dipilih | Menambah pemasukan |
| Pengeluaran | Mengurangi rekening yang dipilih | Menambah pengeluaran |
| Transfer | Mengurangi asal, menambah tujuan | Tidak dihitung |
| Penyesuaian saldo awal | Menambah rekening baru | Tidak dihitung |

Aturan alpha:

- Nilai uang disimpan sebagai `int` rupiah, bukan `double`. Nominal transaksi harus positif dan dalam batas validasi aplikasi.
- Transfer disimpan sebagai **satu baris**, bukan sepasang pemasukan/pengeluaran. Asal dan tujuan harus berbeda dan keduanya harus ada.
- Membuat rekening dengan saldo awal positif juga membuat entri penyesuaian dalam satu transaksi database. Saldo awal nol tidak memerlukan entri bernilai nol.
- Form penyesuaian saldo umum belum tersedia. Entri penyesuaian pada tahap ini khusus saldo awal nonnegatif.
- Kategori pemasukan dan pengeluaran menggunakan pilihan tetap dari domain; belum ada CRUD kategori. Transfer dan saldo awal tidak memiliki kategori.
- Saldo negatif akibat pengeluaran atau transfer diperbolehkan untuk pencatatan manual; aplikasi bukan sistem otorisasi pembayaran bank.
- Transaksi biasa dapat dilihat, diedit, dan dihapus permanen setelah konfirmasi. Edit mempertahankan `id` serta `createdAt`; nilai lama belum memiliki audit trail atau undo.
- Edit atau hapus transaksi menghitung ulang saldo sepanjang waktu dan ringkasan bulan terkait. Transaksi dapat berpindah jenis, rekening, atau bulan selama hasil akhirnya memenuhi seluruh validasi ledger.
- Entri saldo awal dilindungi dari edit/hapus pada alur transaksi. Pengarsipan rekening belum tersedia.

## Tanggal dan periode

`occurredAt` adalah tanggal kejadian yang dipilih pengguna. Alpha menerima tanggal 1 Januari 2000 sampai hari ini, belum transaksi terjadwal di masa depan. Di database tanggal ini disimpan sebagai bilangan `YYYYMMDD` (`occurredDay`), bukan timestamp yang dikonversi zona waktu. `createdAt` mencatat waktu entri dibuat dan tidak menentukan periode keuangan.

Ringkasan bulanan dan riwayat menggunakan tanggal kejadian. Saldo rekening dan saldo total tetap **sepanjang waktu**, tidak berubah menjadi saldo historis ketika pengguna berpindah bulan. Transaksi bertanggal lampau langsung memengaruhi saldo saat ini dan ringkasan bulan lampau. Pencatatan tanggal lampau tersedia melalui pemilih tanggal; tampilan kalender grid belum ada.

## Penyimpanan, performa, dan keamanan

Koneksi `drift_flutter` menyimpan database SQLite di direktori dukungan aplikasi Android. Pekerjaan database native dijalankan melalui isolate yang dikelola Drift. Pemisahan ini menjaga operasi SQL sinkron tidak berjalan pada isolate UI; lihat [dokumentasi isolate Drift](https://drift.simonbinder.eu/isolates/).

Ringkasan dihitung melalui agregasi database, dan riwayat dimuat bertahap dengan awal 50 entri. Indeks tanggal/ID dan rekening mendukung pengambilan data. Ini adalah keputusan desain, bukan klaim bahwa benchmark pada data besar atau HP referensi sudah lulus.

Alpha belum menambahkan enkripsi database, PIN, atau biometrik. Penyimpanan privat Android bukan pengganti backup ataupun enkripsi aplikasi. Tidak ada sinkronisasi cloud atau backup/restore buatan aplikasi. Jangan mengandalkan salinan otomatis sistem untuk pemulihan; uninstall, hapus data, kerusakan, atau kehilangan HP dapat menghilangkan data.

## Skema dan pengembangan berikutnya

Skema database saat ini versi **1**. Inisialisasi skema baru tidak sama dengan pengujian migrasi versi lama. Sebelum menaikkan `schemaVersion`:

1. Simpan ekspor skema versi lama sebagai artefak versi.
2. Tulis langkah migrasi yang menjaga rekening dan ledger.
3. Uji upgrade menggunakan data representatif, termasuk transfer dan tanggal lampau.
4. Verifikasi saldo dan ringkasan sebelum/sesudah upgrade.

Backup lengkap yang berversi, enkripsi backup berbasis kata sandi, dan restore atomik masih rencana produk. Kalender grid, pengelolaan kategori, anggaran, tujuan keuangan, diagram, serta utang/piutang belum termasuk alpha ini. Lihat [product brief](product-brief.md) untuk urutan ruang lingkup produk.
