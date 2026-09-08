# Arsitektur Waras Arta

## Status dan lingkup

Dokumen ini menjelaskan fondasi alpha pertama, bukan seluruh fitur target pada [product brief](product-brief.md). Target runtime pertama adalah Android. Mata uang yang didukung saat ini hanya rupiah tanpa pecahan.

Identitas Android yang dipertahankan dari proyek awal adalah `io.github.panjiarif.waras_arta`. Nama tampilan adalah **Waras Arta**. Mengganti application ID harus menjadi keputusan tersendiri karena Android akan memperlakukannya sebagai aplikasi berbeda.

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
- **ViewModel:** pilihan bulan riwayat, batas jumlah riwayat, bulan/tanggal kalender, operasi transaksi, serta state proses backup/restore. Tidak menyimpan `BuildContext` atau mengakses SQL, kriptografi, maupun pemilih dokumen platform secara langsung.
- **Domain:** model immutable, jenis rekening/transaksi/kategori, DTO backup berversi, draft input, dan kontrak repository/data store. Belum ada lapisan use case umum yang terpisah.
- **Repository/data store:** validasi aturan keuangan, operasi database, pemetaan hasil query, ekspor snapshot konsisten, dan restore atomik.
- **Database:** tabel, constraint, indeks, dan koneksi persisten. SQLite adalah sumber data utama, bukan cache tampilan.
- **Backup service:** mengorkestrasi snapshot, codec terenkripsi, nama file, dan preview sebelum restore tanpa mencampurkan tanggung jawab tersebut ke repository keuangan.
- **Backup file gateway:** menjembatani Dart ke adapter SAF native Android untuk memilih, membaca, menulis, dan memverifikasi dokumen tanpa mengekspos detail platform ke ViewModel.

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
├── core/
│   ├── category_icons.dart
│   └── formatters.dart
├── domain/
│   ├── backup.dart
│   ├── backup_repository.dart
│   ├── finance.dart
│   └── finance_repository.dart
├── data/
│   ├── backup/
│   │   ├── backup_file_gateway.dart
│   │   ├── backup_service.dart
│   │   ├── drift_backup_data_store.dart
│   │   └── encrypted_backup_codec.dart
│   ├── database/
│   │   ├── app_database.dart
│   │   ├── app_database.g.dart
│   │   └── app_database.steps.dart
│   └── repositories/
│       └── drift_finance_repository.dart
└── features/
    ├── backup/
    │   ├── view_models/backup_view_model.dart
    │   └── views/backup_screen.dart
    ├── calendar/
    │   ├── view_models/calendar_view_model.dart
    │   └── views/calendar_view.dart
    ├── categories/
    │   ├── view_models/category_view_model.dart
    │   └── views/
    │       ├── category_form_screen.dart
    │       ├── category_list_screen.dart
    │       └── category_widgets.dart
    └── ledger/
        ├── view_models/
        │   ├── account_view_model.dart
        │   └── ledger_view_model.dart
        └── views/
            ├── account_adjustment_screen.dart
            ├── account_detail_screen.dart
            ├── account_edit_screen.dart
            ├── account_form_screen.dart
            ├── account_widgets.dart
            ├── category_selection_field.dart
            ├── entry_detail_screen.dart
            ├── entry_form_screen.dart
            ├── form_widgets.dart
            └── home_screen.dart
```

Fitur rekening dan transaksi dikelompokkan sebagai satu irisan `ledger` untuk tahap awal. Kalender menjadi irisan tersendiri, tetapi memakai model ledger dan rute detail/form transaksi yang sama. Pecah menjadi fitur terpisah ketika tanggung jawabnya bertambah, bukan dengan menambahkan direktori kosong sejak awal. `go_router` menangani rute layar; [Riverpod](https://riverpod.dev/docs/introduction/getting_started) menghubungkan repository dan ViewModel agar dependensi bisa diganti saat pengujian.

Navigasi utama HP menggunakan empat tujuan `NavigationBar`: Ikhtisar, Riwayat, Kalender, dan Rekening. Kalender tidak membuka tumpukan rute baru ketika tanggal dipilih; detail transaksi dan form pencatatan tetap memakai rute ledger yang sudah ada. Backup/restore merupakan alur pemeliharaan data yang dibuka dari menu aplikasi, bukan tujuan navigasi utama kelima.

## Model saldo dan transaksi

Database menyimpan rekening dan ledger. Rekening tidak memiliki saldo yang diedit langsung; saldo dihitung dari transaksi sepanjang waktu.

| Jenis | Perubahan saldo | Ringkasan pemasukan/pengeluaran |
| --- | --- | --- |
| Pemasukan | Menambah rekening yang dipilih | Menambah pemasukan |
| Pengeluaran | Mengurangi rekening yang dipilih | Menambah pengeluaran |
| Transfer | Mengurangi asal, menambah tujuan | Tidak dihitung |
| Penyesuaian saldo | Menambah atau mengurangi rekening sesuai delta bertanda | Tidak dihitung |

Aturan alpha:

- Nilai uang disimpan sebagai `int` rupiah, bukan `double`. Nominal transaksi harus positif dan dalam batas validasi aplikasi.
- Transfer disimpan sebagai **satu baris**, bukan sepasang pemasukan/pengeluaran. Asal dan tujuan harus berbeda dan keduanya harus ada.
- Membuat rekening dengan saldo awal positif juga membuat entri penyesuaian dalam satu transaksi database. Saldo awal nol tidak memerlukan entri bernilai nol.
- Koreksi saldo menerima target saldo aktual. Repository membandingkannya dengan saldo ledger saat ini, lalu menyimpan selisih nonnol sebagai entri penyesuaian positif atau negatif. Mengubah angka saldo rekening secara langsung tidak diperbolehkan.
- Penyesuaian tidak dihitung sebagai pemasukan/pengeluaran dan tidak memakai kategori. Seluruh entri penyesuaian, termasuk saldo awal, tidak dapat diedit atau dihapus agar jejak koreksi tetap utuh.
- Sejak schema v4, pemasukan dan pengeluaran mempunyai 1–50 alokasi nominal–subkategori. Transfer dan saldo awal tidak memiliki alokasi kategori; schema v5 mempertahankan bentuk ini sambil menambahkan kelompok saldo rekening.
- Saldo negatif akibat pengeluaran atau transfer diperbolehkan untuk pencatatan manual; aplikasi bukan sistem otorisasi pembayaran bank.
- Transaksi biasa dapat dilihat, diedit, dan dihapus permanen setelah konfirmasi. Edit mempertahankan `id` serta `createdAt`; nilai lama belum memiliki audit trail atau undo.
- Edit atau hapus transaksi menghitung ulang saldo sepanjang waktu dan ringkasan bulan terkait. Transaksi dapat berpindah jenis, rekening, atau bulan selama hasil akhirnya memenuhi seluruh validasi ledger.
- Entri lama yang menyentuh rekening arsip tetap dapat dilihat, tetapi tidak dapat diedit atau dihapus sampai rekening tersebut dipulihkan. Aturan ini menjaga rekening yang sudah diarsipkan tetap bersaldo nol.

### Alokasi kategori transaksi

Schema v4 mempertahankan `ledger_entries` sebagai header satu kejadian uang nyata: satu ID, jenis, rekening, total, tanggal, catatan, dan waktu pembuatan. `category_id` sudah dipindahkan ke `ledger_allocations` sehingga setiap pemasukan/pengeluaran mempunyai 1–50 pasangan nominal dan subkategori. Transfer serta penyesuaian tetap tidak mempunyai allocation.

Total header pemasukan/pengeluaran diturunkan dari jumlah allocation dan disimpan agar perhitungan saldo tetap sederhana. Saldo, arus kas total, jumlah transaksi, riwayat, dan kalender menjumlahkan header tepat sekali. Anggaran, filter kategori, dan diagram kategori menjumlahkan nominal allocation. Karena itu transaksi Rp17.000 dengan Rp15.000 Makan serta Rp2.000 Parkir tetap satu transaksi dan satu pengurangan saldo, tetapi berkontribusi tepat ke dua kategori.

Form tetap membuka satu pasangan nominal+subkategori. Tombol berikon plus dengan label **Tambah rincian** menambahkan pasangan di bawahnya; total bukan input kedua, melainkan dihitung otomatis. Kontrak schema, migrasi, backup, UX, dan pengujiannya dijelaskan dalam [spesifikasi alokasi kategori transaksi](transaction-allocations.md).

## Siklus rekening

- Nama dan jenis rekening dapat diubah tanpa mengganti ID, saldo, atau relasi riwayatnya. Nama harus unik tanpa membedakan huruf besar/kecil, termasuk terhadap rekening arsip.
- Rekening hanya dapat diarsipkan ketika saldo ledger tepat nol dan setidaknya satu rekening aktif lain tetap tersedia.
- Rekening arsip disembunyikan dari daftar utama secara default, dapat ditampilkan melalui filter, dan selalu dapat dipulihkan.
- Rekening arsip tidak tersedia sebagai sumber maupun tujuan transaksi atau penyesuaian baru.
- Hapus permanen hanya tersedia untuk rekening yang tidak memiliki referensi sebagai sumber maupun tujuan dalam ledger. Tidak ada penghapusan transaksi secara berantai; rekening yang memiliki riwayat harus dipertahankan dan, bila sudah selesai digunakan, diarsipkan.

## Kategori dan subkategori

Kategori dibatasi tepat dua tingkat. Baris induk adalah kelompok, sedangkan alokasi transaksi hanya boleh menunjuk baris anak. Schema v4 menyimpan relasinya pada `ledger_allocations` tanpa menyalin nama kategori. Karena itu rename dan perubahan ikon langsung tercermin pada riwayat tanpa memutus identitas yang dipakai kalender, anggaran, diagram, dan filter.

- Kelompok serta subkategori dapat dibuat, diubah nama/ikonnya, diarsipkan, dan dipulihkan.
- Jenis pemasukan/pengeluaran dan induk subkategori tidak dapat diubah setelah dibuat.
- Kelompok baru dibuat atomik bersama subkategori pertama.
- Minimal satu subkategori efektif harus tetap aktif untuk masing-masing jenis transaksi.
- Kategori yang diarsipkan tidak tersedia untuk transaksi baru, tetapi transaksi lama tetap dapat ditampilkan dan diedit selama referensinya tidak diganti.
- Ikon disimpan sebagai semantic string key yang dipetakan ke katalog Material terbatas. `IconData.codePoint` dan berkas gambar tidak disimpan di database.
- Upload gambar ditunda sampai spesifikasi backup mampu membawa database dan aset sebagai satu paket tervalidasi.

Rencana anggaran mendukung periode bulanan, tahunan kalender, dan rentang tanggal kustom. Semuanya menggunakan ID subkategori pengeluaran dan menghitung progres dari `ledger_allocations.amount`. Kontrak produk, schema v6, payload backup v4, serta batas implementasinya dijelaskan dalam [spesifikasi Anggaran v1](budgets.md).

## Tanggal dan periode

`occurredAt` adalah tanggal kejadian yang dipilih pengguna. Alpha menerima tanggal 1 Januari 2000 sampai hari ini, belum transaksi terjadwal di masa depan. Di database tanggal ini disimpan sebagai bilangan `YYYYMMDD` (`occurredDay`), bukan timestamp yang dikonversi zona waktu. `createdAt` mencatat waktu entri dibuat dan tidak menentukan periode keuangan.

Ringkasan bulanan, riwayat, dan kalender menggunakan tanggal kejadian. Saldo rekening dan saldo total tetap **sepanjang waktu**, tidak berubah menjadi saldo historis ketika pengguna berpindah bulan. Transaksi bertanggal lampau langsung memengaruhi saldo saat ini dan ringkasan bulan lampau.

Kalender menampilkan grid bulanan ringan dari Senin sampai Minggu. Navigasi bulan dibatasi Januari 2000 sampai bulan berjalan; tanggal setelah hari ini pada bulan berjalan terlihat nonaktif. Titik aktivitas membedakan pemasukan, pengeluaran, dan aktivitas lain berupa transfer atau penyesuaian. Ketika tanggal dipilih, layar menampilkan total pemasukan/pengeluaran, jumlah semua jenis entri, dan daftar lengkap pemasukan, pengeluaran, transfer, serta penyesuaian memakai komponen baris ringkas yang sama dengan Ikhtisar dan Riwayat. Entri dapat diketuk menuju detail lengkap. Tombol tambah di tab ini membuka form transaksi dengan tanggal sipil yang dipilih sebagai nilai awal.

## Penyimpanan, performa, dan keamanan

Koneksi `drift_flutter` menyimpan database SQLite di direktori dukungan aplikasi Android. Pekerjaan database native dijalankan melalui isolate yang dikelola Drift. Pemisahan ini menjaga operasi SQL sinkron tidak berjalan pada isolate UI; lihat [dokumentasi isolate Drift](https://drift.simonbinder.eu/isolates/).

Ringkasan dihitung melalui agregasi database, dan riwayat dimuat bertahap dengan awal 50 entri. Agregasi kalender dilakukan langsung di SQLite dengan pengelompokan `occurredDay`, sehingga penanda dan total kalender mencakup seluruh transaksi bulan tersebut dan tidak bergantung pada batas 50 entri riwayat. Daftar tanggal terpilih juga membaca seluruh entri untuk satu tanggal. Indeks `ledger_entries_occurred_day_id` yang sudah ada mendukung kedua query; kalender tidak memerlukan tabel atau indeks baru. Ini adalah keputusan desain, bukan klaim bahwa benchmark pada data besar atau HP referensi sudah lulus.

### Backup manual terenkripsi

Backup memakai dua bentuk yang sengaja dipisahkan:

1. snapshot logis JSON dengan `backupVersion`, versi schema database, timestamp UTC, rekening, kategori, ledger, ID, dan high-water mark ID SQLite;
2. container terenkripsi `.warasarta` dengan versi sendiri.

Saldo, ringkasan, dan data kalender tidak diduplikasi karena dapat dihitung ulang dari ledger. Format payload dibuat eksplisit dan berversi, tidak memakai serialisasi generated Drift sebagai kontrak permanen. Payload v3/schema 5 adalah format saat ini: bentuk allocation dari v2 dipertahankan dan setiap rekening membawa `balanceGroup`. Payload v1/schema 3 serta v2/schema 4 tetap dapat dibaca dan dinormalisasi; rekening dari kedua format lama dipetakan ke Saldo utama. Anggaran mendatang menaikkan format menjadi payload v4/schema 6 tanpa mengubah container enkripsi v1.

Kata sandi dinormalisasi ke Unicode NFC, lalu kunci 256-bit diturunkan menggunakan Argon2id dan salt acak. Snapshot dienkripsi serta diautentikasi dengan XChaCha20-Poly1305 dan nonce acak; header keamanan ikut diautentikasi. Kata sandi maupun kunci tidak disimpan. Akibatnya, kata sandi yang terlupa tidak dapat dipulihkan dan file tidak dapat direstore. Decoder container v1 hanya menerima profil produksi secara persis: Argon2 versi 19, normalisasi NFC, memori 19.456 KiB, 2 iterasi, paralelisme 1, dan panjang kunci 32 byte. Parameter berbeda ditolak; perubahan profil harus diperkenalkan melalui versi container atau jalur migrasi baru. Ukuran container terenkripsi dibatasi 16 MiB dan plaintext hasil dekripsi dibatasi 10 MiB.

Ekspor membaca seluruh tabel terkait dalam satu transaksi baca. Restore memvalidasi container, payload, relasi, dan ringkasan sebelum meminta konfirmasi replace-all. Setelah konfirmasi, satu operasi terkoordinasi pada `BackupController` mengekspor data aktif, mengenkripsinya dengan kata sandi yang sama seperti file restore, lalu mewajibkan pengguna menyimpannya melalui Save As sebagai safety backup. Hanya penyimpanan yang berhasil yang mengizinkan restore berlanjut; pembatalan atau kegagalan menghentikan alur sebelum database diubah. Penggantian rekening, kategori, header ledger, allocation, ID, serta sequence kemudian berlangsung dalam satu transaksi database; kegagalan membuat transaksi di-rollback. Versi ini tidak melakukan merge.

Pemilih dokumen Android menjadi batas penyimpanan. `SafBackupFileGateway` berbicara melalui `MethodChannel` dengan adapter native pada `MainActivity`, menggunakan `ACTION_CREATE_DOCUMENT` dan `ACTION_OPEN_DOCUMENT` tanpa dependency `file_picker`. Dokumen pilihan dibaca langsung dari URI penyedia sebagai stream berbatas 16 MiB, tanpa salinan cache perantara milik aplikasi. Setelah penulisan, URI dibuka kembali dan jumlah byte serta SHA-256 harus sama dengan container sumber sebelum operasi dinyatakan berhasil. Karena itu, safety backup yang batal, gagal ditulis, atau gagal diverifikasi tidak dapat membuka jalan ke replace-all.

Pengguna dapat memilih Downloads atau penyedia seperti Google Drive bila tersedia, tetapi Waras Arta tidak mengunggah, menjadwalkan, menyinkronkan, merotasi, atau memverifikasi backup rutin secara otomatis. Verifikasi baca ulang hanya memeriksa hasil penulisan saat itu dan bukan jaminan retensi jangka panjang. Safety backup wajib dalam alur restore tetap disimpan melalui pemilih dokumen ini. Lihat [spesifikasi backup dan restore](backup-restore.md).

Enkripsi file backup tidak mengubah database kerja: SQLite aktif masih belum dienkripsi khusus oleh Waras Arta. Alpha juga belum menambahkan PIN atau biometrik. Android Auto Backup serta device-to-device extraction dinonaktifkan dan seluruh domain data aplikasi dikecualikan melalui aturan Android 11 dan Android 12+ agar database plaintext tidak berpindah di luar alur `.warasarta`. Penyimpanan privat Android bukan pengganti backup; uninstall, hapus data, kerusakan, atau kehilangan HP dapat menghilangkan perubahan sejak snapshot manual terakhir.

## Skema dan pengembangan berikutnya

Skema database saat ini versi **5**. Snapshot v1 sampai v5 disimpan di `drift_schemas/app_database/`. Migrasi v1 ke v2 membuat kategori dua tingkat, memetakan setiap kategori teks lama ke subkategori `Umum`, lalu membangun ulang ledger dengan foreign key. Migrasi v2 ke v3 menambahkan status arsip rekening dan membangun ulang constraint nominal ledger agar penyesuaian dapat menyimpan delta bertanda. Migrasi v3 ke v4 membangun `ledger_entries` sebagai header tanpa `category_id` dan memindahkan kategori serta nominal pemasukan/pengeluaran ke `ledger_allocations`. Migrasi v4 ke v5 menambahkan `balance_group` dengan default `primary`, sehingga seluruh rekening lama tetap tampil sebagai Saldo utama. Langkah migrasi dijalankan berurutan untuk instalasi yang berpindah langsung dari versi lama ke v5.

Uji migrasi memverifikasi jalur versi lama menuju schema v5, termasuk v4→v5 dan upgrade berurutan dari schema awal, beserta struktur schema, identitas, urutan allocation, nominal, kelompok rekening, tanggal, catatan, saldo, ringkasan, trigger, indeks, dan pemeriksaan integritas.

Sebelum menaikkan `schemaVersion` berikutnya:

1. Simpan ekspor skema versi lama sebagai artefak versi.
2. Tulis langkah migrasi yang menjaga rekening dan ledger.
3. Uji upgrade menggunakan data representatif, termasuk transfer dan tanggal lampau.
4. Verifikasi saldo dan ringkasan sebelum/sesudah upgrade.
5. Perluas DTO, ekspor, restore, dan migrasi decoder backup untuk semua data semantik baru; naikkan `backupVersion` bila kontrak payload berubah, lalu baru perbarui guard cakupan adapter dan tesnya. Guard ekspor maupun restore saat ini sengaja mematok adapter v3 pada schema v5 serta nama tabel dan kolom persisten rekening (termasuk `balance_group`), kategori, ledger, dan allocation secara persis. Penambahan tabel atau kolom—bahkan bila `schemaVersion` lupa dinaikkan—akan berhenti secara fail-closed, bukan menghasilkan backup parsial atau menyisakan data baru saat replace-all.

Kalender dan split transaction memakai `ledger_allocations` sejak schema v4/payload v2. Kelompok Saldo utama serta Simpanan & investasi menaikkan versi aktif menjadi schema v5/payload v3 dengan `balanceGroup`; restore v1/v2 tetap didukung dan memetakan rekening lama ke Saldo utama. Setelah smoke test perangkat untuk alur ini selesai, evolusi data berikutnya adalah Anggaran schema v6/payload v4. Anggaran, tujuan keuangan, diagram, serta utang/piutang belum termasuk alpha saat ini. Lihat [product brief](product-brief.md) untuk urutan ruang lingkup produk.
