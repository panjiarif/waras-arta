# Anggaran Waras Arta

## Status implementasi dan tujuan

Dokumen ini adalah kontrak **Anggaran v1** untuk versi produk 0.2. Status implementasi: **selesai pada 8 September 2026** dengan schema database v6 dan payload backup v4 aktif. Domain, persistence, CRUD bulanan/tahunan/kustom, pilihan multi-subkategori, progres dari allocation, penolakan overlap, backup/restore, dan pengujian otomatis sudah tersedia. Smoke test pada perangkat fisik tetap menjadi verifikasi manual sebelum aplikasi dipakai sebagai satu-satunya catatan keuangan; dokumen ini tidak menyatakan bahwa smoke test tersebut sudah dilakukan.

Perubahan aturan di dokumen ini harus disertai penyesuaian model, migrasi database, format backup, dan pengujian agar kontrak implementasi tetap sinkron.

Anggaran membantu pengguna membatasi pengeluaran untuk suatu rentang tanggal. Anggaran bukan rekening, pemindahan uang, atau tujuan keuangan. Membuat atau mengubah anggaran tidak mengubah saldo serta tidak membuat transaksi.

Versi pertama mendukung tiga alternatif periode:

- **Bulanan:** satu bulan kalender penuh;
- **Tahunan:** satu tahun kalender penuh, 1 Januari sampai 31 Desember;
- **Kustom:** rentang tanggal inklusif pilihan pengguna, termasuk satu hari atau lintas bulan/tahun.

Tujuan versi pertama:

- menetapkan batas rupiah untuk satu atau beberapa subkategori pengeluaran;
- menghitung pemakaian otomatis dari alokasi kategori transaksi untuk seluruh periode;
- memperbarui progres ketika transaksi berubah;
- mencegah satu kategori dihitung ganda pada periode yang saling beririsan;
- mempertahankan histori ketika kategori kemudian diarsipkan;
- memasukkan seluruh data anggaran ke backup terenkripsi berikutnya.

## Istilah

- **Jenis periode** (`periodKind`) adalah `monthly`, `yearly`, atau `custom`.
- **Rentang anggaran** adalah `startDay` sampai `endDay` secara inklusif. Keduanya tanggal sipil `YYYYMMDD` dalam rentang `20000101..99991231`, tanpa konversi zona waktu.
- **Batas** (`limitAmount`) adalah nominal maksimum yang direncanakan untuk seluruh rentang anggaran dalam rupiah bulat.
- **Terpakai** (`spentAmount`) adalah jumlah transaksi pengeluaran yang tanggal dan subkategorinya cocok dengan anggaran.
- **Sisa** adalah `limitAmount - spentAmount` ketika hasilnya positif.
- **Terlampaui** adalah `spentAmount - limitAmount` ketika hasilnya positif.
- **Kategori terpilih** selalu berarti ID subkategori pengeluaran, bukan kelompok induk atau salinan nama.

## Aturan produk

### Identitas dan periode

1. Setiap anggaran mempunyai tepat satu jenis dan rentang periode.
2. Periode bulanan wajib tepat dari hari pertama sampai hari terakhir bulan yang sama.
3. Periode tahunan wajib tepat dari 1 Januari sampai 31 Desember tahun yang sama.
4. Periode kustom menerima setiap rentang tanggal Gregorian valid dengan `startDay <= endDay`. Rentang satu hari diperbolehkan.
5. Batas berlaku untuk keseluruhan periode. Anggaran tahunan atau kustom tidak otomatis dibagi, dirata-ratakan, atau di-rollover per bulan.
6. Periode lampau, sedang berjalan, dan mendatang boleh dibuat. Anggaran tahunan yang dibuat di tengah tahun langsung memperhitungkan pengeluaran sejak 1 Januari.
7. Jenis dan kedua batas tanggal tidak dapat diubah setelah anggaran dibuat pada v1. Kesalahan periode diperbaiki dengan menghapus dan membuat ulang. Nama, batas, serta kategori tetap dapat diedit.
8. Nama wajib 1–80 karakter setelah di-trim dan setiap rangkaian whitespace diringkas menjadi satu spasi. `normalizedName` wajib sama persis dengan nama canonical tersebut dalam lowercase, mengikuti aturan nama rekening/kategori saat ini.
9. Nama wajib unik tanpa membedakan huruf besar/kecil pada rentang tanggal yang sama. Jenis tidak menjadi bagian identitas unik: periode kustom yang kebetulan sama dengan satu bulan tetap berbagi ruang nama dengan periode bulanan itu.
10. Batas wajib berupa bilangan bulat rupiah dari `1` sampai `maxAmount`.
11. Tidak diperlukan flag aktif atau arsip. Status diturunkan dari `referenceDay`: aktif jika `startDay <= referenceDay <= endDay`, mendatang jika `startDay > referenceDay`, dan riwayat jika `endDay < referenceDay`.

Jenis periode mengatur input dan label di UI. Perhitungan progres serta konflik selalu memakai `startDay` dan `endDay`.

`referenceDay` adalah integer tanggal sipil `YYYYMMDD` dari kalender lokal perangkat, bukan tanggal UTC. Nilainya dihitung ulang ketika layar dibuka, aplikasi resume, hari lokal berganti, atau zona waktu perangkat berubah.

### Pilihan kategori dan konflik

1. Anggaran wajib memiliki minimal satu subkategori pengeluaran.
2. Kategori pemasukan dan kelompok induk tidak dapat dipilih langsung.
3. Subkategori baru dapat dipilih hanya ketika subkategori dan induknya sama-sama tidak diarsipkan.
4. Satu subkategori tidak boleh berada pada dua anggaran yang rentang tanggalnya beririsan, termasuk antarjenis periode.
5. Dua rentang berkonflik bila:

   `A.startDay <= B.endDay && B.startDay <= A.endDay`

6. Batas tanggal bersifat inklusif. Anggaran yang berakhir 31 Januari dan anggaran yang dimulai 1 Februari tidak berkonflik; dua rentang yang sama-sama mencakup 31 Januari berkonflik.
7. Bulan Januari dan Februari boleh memakai subkategori yang sama. Sebaliknya, anggaran Tahunan 2026 dan Bulanan September 2026 tidak boleh memakai subkategori yang sama.
8. Periode kustom 15 Januari–15 Februari berkonflik dengan anggaran Januari maupun Februari jika subkategorinya sama.
9. Rentang tanggal boleh beririsan jika ID subkategorinya berbeda. Dua anak dari induk yang sama tetap merupakan kategori berbeda.
10. Konflik ditolak secara atomik saat create, edit, dan restore, bukan sekadar diberi peringatan. Ini mencegah satu pengeluaran terhitung ganda.
11. Ringkasan tahunan dari kumpulan anggaran bulanan merupakan fitur laporan mendatang, bukan anggaran tahunan yang menumpuk kategori sama pada v1.
12. Aksi **Pilih semua** pada kelompok hanya memilih anak yang aktif dan tidak berkonflik saat itu. UI menyebut jumlah yang dilewati serta alasan singkat; subkategori yang dibuat kemudian tidak otomatis masuk ke anggaran lama.
13. Jika subkategori atau induknya diarsipkan setelah dipilih, relasinya dipertahankan dan transaksi historisnya tetap dihitung.
14. Saat edit, kategori arsip yang sudah terhubung tetap terlihat dengan label **Arsip**. Kategori itu boleh dipertahankan atau dilepas, tetapi tidak dapat ditambahkan kembali sampai dipulihkan.

Validasi edit memakai selisih set. Status aktif hanya diwajibkan untuk `newCategoryIds - existingCategoryIds`; ID arsip pada irisan `newCategoryIds ∩ existingCategoryIds` boleh dipertahankan, dan ID lama yang tidak dipilih boleh dilepas. Aturan yang sama berlaku ketika anak maupun induknya diarsipkan.

### Pemakaian dan progres

Pemakaian dihitung saat query dan tidak disimpan sebagai kolom:

```text
spentAmount = SUM(allocation.amount)
  ketika transaction.kind = expense
  dan allocation.categoryId termasuk kategori anggaran
  dan startDay <= transaction.occurredDay <= endDay
```

`createdAt`, rekening, saldo, catatan, total header transaksi, dan batas pagination riwayat tidak memengaruhi progres. Satu transaksi split dapat menyumbang nominal berbeda ke beberapa anggaran melalui alokasinya, tetapi total header tidak pernah dijumlahkan sekali untuk setiap kategori.

- Pemasukan, transfer, serta penyesuaian saldo tidak dihitung.
- Rename atau perubahan ikon kategori tidak mengubah hasil karena relasi menggunakan ID.
- Menambah, mengedit, menghapus, memindahkan tanggal, atau mengganti jenis/kategori transaksi langsung mengubah progres terkait.
- Kategori yang diarsipkan tidak dikeluarkan dari query histori.
- Saldo rekening negatif tidak mengubah cara pemakaian dihitung.
- Mencapai atau melewati batas tidak memblokir pencatatan pengeluaran.

Persentase aktual boleh melebihi 100%. Progress bar visual dijepit pada 100%, tetapi teks tetap menampilkan nominal dan persentase sebenarnya. Klasifikasi wajib memeriksa keadaan habis/terlampaui lebih dahulu. Hanya ketika `spentAmount < limitAmount`, status **Hampir habis** dimulai pada 80% melalui perbandingan integer `spentAmount * 5 >= limitAmount * 4`. Urutan ini menghindari pembulatan floating-point dan overflow karena kedua nominal pada cabang tersebut berada di bawah atau sama dengan `maxAmount`.

Keadaan tampilan:

- `spentAmount < limitAmount` dan `spentAmount * 5 < limitAmount * 4`: status normal dan nominal sisa;
- `spentAmount < limitAmount` dan ambang 80% tercapai: **Hampir habis** dan nominal sisa;
- `spentAmount == limitAmount`: **Anggaran habis**;
- `spentAmount > limitAmount`: **Melebihi Rp…** dengan peringatan yang tidak hanya mengandalkan warna.

### Perubahan dan penghapusan

- Pembuatan anggaran dan seluruh pilihan kategorinya berlangsung dalam satu transaksi database.
- Edit nama, batas, dan penggantian penuh pilihan kategori juga berlangsung atomik dan divalidasi ulang.
- Anggaran tidak boleh di-commit tanpa kategori. SQLite boleh melihat row tanpa mapping sementara di dalam transaksi, lalu repository memeriksa minimal satu mapping sebelum commit.
- Hapus memerlukan konfirmasi.
- Menghapus anggaran hanya menghapus definisi dan relasi pilihannya. Kategori, rekening, serta transaksi tidak pernah ikut dihapus.

## Pengalaman pengguna v1

Anggaran tidak menambah tujuan kelima pada bottom navigation. Empat tujuan utama tetap **Ikhtisar**, **Riwayat**, **Kalender**, dan **Rekening**.

Pintu masuk:

- kartu **Anggaran aktif** pada Ikhtisar;
- item **Kelola anggaran** pada menu aplikasi;
- rute khusus untuk daftar serta form tambah/edit.

### Daftar anggaran

Daftar membuka tab **Aktif** dan filter jenis **Semua** secara default. Pilihan statusnya **Aktif**, **Mendatang**, dan **Riwayat**; filter jenisnya **Semua**, **Bulanan**, **Tahunan**, dan **Kustom**. Filter dipertahankan ketika kembali dari form, tetapi kunjungan baru kembali ke default.

Pada layar sempit atau text scale besar, kontrol status boleh tersusun vertikal dan filter jenis dibuka lewat tombol/bottom sheet. Filter aktif selalu terlihat. Empty state hasil filter menyediakan aksi **Reset filter** atau **Lihat semua** agar tidak tampak seperti kehilangan data.

Daftar dikelompokkan berdasarkan rentang tanggal yang sama. Label kelompok diturunkan dari bentuk tanggal, bukan jenis: satu bulan kalender penuh memakai label bulan, satu tahun kalender penuh memakai label tahun, selain itu memakai rentang umum. Contoh:

- **September 2026**;
- **Tahun 2026**;
- **7 Sep–31 Des 2026**.

Jenis tetap ditampilkan sebagai badge teks **Bulanan**, **Tahunan**, atau **Kustom** pada setiap kartu. Dengan demikian periode kustom yang persis menyerupai bulan/tahun tidak kehilangan identitasnya.

Total hanya boleh dihitung di dalam kelompok dengan rentang persis sama: `groupLimit = Σ limitAmount`, `groupSpent = Σ spentAmount`, dan `groupNet = groupLimit - groupSpent`. Ringkasan kelompok juga menyebut jumlah kartu hampir habis, habis, dan terlampaui agar nilai net tidak menyamarkan masalah. Jangan menampilkan satu total global yang mencampur periode berdurasi berbeda.

Pada tab Aktif, peringkat kelompok mengikuti status terburuk anggotanya: terlampaui, habis, hampir habis, lalu normal; tie-breaker berikutnya adalah `endDay`, `startDay`, lalu ID terkecil. Kartu dalam kelompok memakai peringkat status yang sama, lalu `normalizedName` dan ID. Kelompok Mendatang diurutkan menurut `startDay`, `endDay`, lalu ID terkecil; Riwayat menurut `endDay` dan `startDay` menurun, lalu ID terkecil. Urutan ini wajib deterministik.

Setiap kartu menampilkan nama, badge jenis, label periode, batas, terpakai, sisa/kelebihan, persentase, dan progress bar. Ringkasan kategori menampilkan maksimal dua nama lalu **+N lainnya**. Semantic label juga ringkas—jumlah kategori, maksimal dua contoh, dan jumlah sisanya—sedangkan daftar lengkap tersedia setelah membuka detail. Layar juga mempunyai tombol tambah, empty state yang sesuai status/filter, serta state loading, error, dan retry tanpa angka nol palsu.

Kartu Ikhtisar ditempatkan sebelum pemilih bulan transaksi dan diberi konteks eksplisit **Aktif hari ini · <tanggal lokal>** karena acuannya tidak mengikuti bulan transaksi. **Perlu perhatian** berarti hampir habis, habis, atau terlampaui. Kartu menampilkan jumlah aktif, jumlah perlu perhatian, maksimal dua item, serta **Lihat semua**. Dua item dipilih dengan ranking global per anggaran tanpa mengikuti kelompok: status terlampaui, habis, hampir habis, normal; lalu `endDay`, `startDay`, `normalizedName`, dan ID. Jika tidak ada yang aktif, tampilkan keadaan kosong dan anggaran mendatang terdekat bila ada.

### Form tambah/edit

Form tambah memuat:

- nama;
- batas rupiah;
- jenis periode **Bulanan**, **Tahunan**, atau **Kustom**;
- bulan berjalan sebagai default bulanan;
- tahun berjalan sebagai default tahunan;
- pemilih rentang wajib untuk kustom, tanpa default satu hari secara diam-diam;
- teks bantuan bahwa batas berlaku untuk seluruh periode dan tidak dibagi otomatis per bulan;
- pemilih multi-subkategori yang dikelompokkan berdasarkan induk;
- **Pilih semua** hanya memilih anak yang aktif dan tidak berkonflik serta menjelaskan jumlah yang dilewati;
- **Hapus semua** melepas seluruh pilihan dalam kelompok, termasuk pilihan yang kemudian menjadi arsip atau konflik.

Pada form edit, jenis dan rentang periode read-only. Pemilih kategori membuka bottom sheet dengan jumlah pilihan, aksi per kelompok, dan tombol **Selesai (N)**. Kategori konflik yang belum dipilih dinonaktifkan dan menjelaskan seluruh nama anggaran serta rentang penyebabnya. Kategori konflik yang sudah terpilih tetap mempunyai aksi uncheck/**Hapus**, tetapi tidak dapat ditambahkan kembali selama konflik ada. Kategori arsip yang sudah terhubung tetap terlihat dan juga dapat dilepas.

Jika periode pada form tambah diubah setelah kategori dipilih, konflik dihitung ulang segera. Pilihan yang kini konflik tidak dihapus diam-diam: tetap terlihat sebagai error yang memblokir simpan sampai pengguna melepasnya atau mengembalikan periode.

Form yang kotor meminta konfirmasi sebelum ditutup. Seluruh kontrol minimal 48 dp, aman pada lebar 320 px dan text scale 200%, serta memakai label/ikon semantik selain warna. Progress mempunyai semantic label yang menyebut nominal dan status.

## Model domain dan arsitektur

Anggaran memakai kontrak repository tersendiri agar `FinanceRepository` tidak terus membesar.

Model minimum:

- `BudgetPeriodKind`: `monthly`, `yearly`, dan `custom` dengan encoding database yang dipin oleh test;
- `BudgetPeriod`: jenis, `startDay`, `endDay`, serta validasi bentuk canonical;
- `Budget`: identitas, nama, periode, batas, dan timestamp;
- `BudgetDetails`: anggaran beserta kategori terpilih;
- `BudgetProgress`: terpakai serta getter sisa, terlampaui, rasio aktual, dan rasio visual;
- `BudgetConflict`: ID kategori, ID/nama anggaran penyebab, dan periodenya;
- `BudgetListFilter`: status tanggal, jenis opsional, dan tanggal referensi;
- `BudgetListSnapshot`: daftar progres dan kelompok rentang, tanpa total global lintas rentang;
- `BudgetDraft`: periode, nama, batas, dan set ID subkategori;
- `BudgetUpdateDraft`: nama, batas, dan set ID subkategori tanpa periode.

Kontrak `BudgetRepository` minimum:

```dart
abstract interface class BudgetRepository {
  Stream<BudgetListSnapshot> watchBudgets(BudgetListFilter filter);
  Future<BudgetListSnapshot> loadBudgets(BudgetListFilter filter);
  Stream<BudgetDetails?> watchBudget(int id);
  Future<BudgetDetails?> getBudget(int id);
  Stream<Map<int, List<BudgetConflict>>> watchCategoryConflicts(
    BudgetPeriod period, {
    int? excludingBudgetId,
  });
  Future<int> createBudget(BudgetDraft draft);
  Future<void> updateBudget(int id, BudgetUpdateDraft draft);
  Future<void> deleteBudget(int id);
}
```

`BudgetUpdateDraft` sengaja tidak membawa periode. Repository memberi pesan validasi yang ramah, sedangkan constraint dan trigger SQLite menjadi pertahanan kedua.

Filter tanggal hanya menentukan anggaran mana yang tampil. `spentAmount` selalu dihitung untuk seluruh rentang milik anggaran, tidak dipotong oleh tab, tanggal referensi, atau window tampilan.

Invariant minimal satu mapping tidak dapat dinyatakan sebagai constraint row langsung atau trigger commit-tertunda di SQLite karena row `budgets` harus ada sebelum mapping pertama. Create/update dijalankan dalam satu transaksi, jumlah mapping diperiksa setelah penulisan dan sebelum commit, dan pemeriksaan integritas restore mengulang aturan yang sama. Trigger tidak boleh memblokir keadaan kosong sementara yang diperlukan untuk mengganti seluruh pilihan atau menjalankan cascade saat anggaran dihapus.

Anggaran dibangun setelah fondasi alokasi kategori pada [spesifikasi alokasi transaksi](transaction-allocations.md). `databaseProvider` sudah ditempatkan pada composition root netral di `lib/app/providers.dart`. Ledger, kategori, kalender, backup, dan anggaran mengonsumsi provider bersama tanpa dependensi silang antarfitur.

## Schema Drift v6

Schema anggaran adalah versi 6 dan menambahkan dua tabel di atas schema v5. Schema dasar tersebut sudah menormalkan kategori transaksi ke `ledger_allocations` serta menyimpan `balanceGroup` rekening.

### `budgets`

| Kolom | Aturan |
| --- | --- |
| `id` | integer primary key autoincrement |
| `period_kind` | integer: 0 bulanan, 1 tahunan, 2 kustom |
| `start_day` | tanggal sipil awal `YYYYMMDD`, inklusif |
| `end_day` | tanggal sipil akhir `YYYYMMDD`, inklusif |
| `name` | nama canonical 1–80 karakter |
| `normalized_name` | nama canonical lowercase untuk pemeriksaan unik |
| `limit_amount` | integer rupiah `1..maxAmount` |
| `created_at` | timestamp UTC pembuatan |
| `updated_at` | timestamp UTC perubahan terakhir |

Constraint database wajib memastikan:

- `period_kind` hanya `0..2` dan mapping enum ini dipin dengan test;
- `start_day` dan `end_day` merupakan tanggal Gregorian nyata dalam `20000101..99991231`, bukan hanya integer di dalam rentang;
- `start_day <= end_day`;
- jenis bulanan tepat hari pertama sampai hari terakhir bulan yang sama;
- jenis tahunan tepat 1 Januari sampai 31 Desember tahun yang sama;
- jenis kustom menerima satu atau lebih hari;
- `limit_amount` berada dalam `1..999999999999`;
- nama canonical/normalized tidak kosong dan panjangnya paling banyak 80;
- `updated_at >= created_at`.

Uji tanggal nyata mencakup aturan tahun kabisat. Validasi nama canonical dan lowercase Unicode tetap diulang oleh repository serta parser backup; jangan mengandalkan `lower()` SQLite sebagai satu-satunya kebenaran.

Saat edit, repository menetapkan `updatedAt = max(nowUtc, existing.updatedAt)`. Dengan begitu invariant timestamp tetap sah jika jam perangkat mundur; kondisi tersebut dipin dengan test clock rollback.

Nama unik menggunakan indeks (`start_day`, `end_day`, `normalized_name`). `period_kind` sengaja tidak masuk indeks unik karena dua jenis dengan rentang persis sama mewakili ruang waktu yang sama.

### `budget_categories`

| Kolom | Aturan |
| --- | --- |
| `budget_id` | foreign key ke `budgets`, `ON DELETE CASCADE` |
| `category_id` | foreign key ke `categories`, `ON DELETE RESTRICT` |

Primary key gabungan adalah (`budget_id`, `category_id`); tabel tidak memiliki ID atau sequence sendiri.

Constraint/trigger database wajib:

- mapping hanya menerima kategori leaf berjenis pengeluaran pada `INSERT` dan `UPDATE OF category_id`;
- mapping kategori yang sama ke budget lain yang rentangnya beririsan ditolak pada `INSERT` dan `UPDATE OF budget_id, category_id`;
- trigger update mengecualikan tuple `OLD` yang sedang dipindah, bukan sekadar semua row dengan budget ID baru;
- perubahan `period_kind`, `start_day`, atau `end_day` ditolak bila nilainya berubah;
- menghapus anggaran menghapus mapping, bukan kategori;
- menghapus kategori yang direferensikan anggaran ditolak.

Kondisi overlap trigger adalah:

```text
candidate.start_day <= existing.end_day
AND existing.start_day <= candidate.end_day
```

Status arsip tidak diperiksa trigger agar mapping historis dan restore tetap sah. Repository bertanggung jawab melarang assignment baru ketika subkategori atau induknya sedang diarsipkan.

Indeks awal:

- unique `budgets_unique_period_name(start_day, end_day, normalized_name)`;
- `budgets_kind_period_order(period_kind, start_day, end_day, normalized_name, id)`;
- `budget_categories_category_budget(category_id, budget_id)`; primary key sudah melayani arah budget ke kategori.

Query progres berjalan dari `budget_categories` ke `ledger_allocations` berdasarkan `category_id`, lalu ke header `ledger_entries` untuk jenis dan tanggal. Evaluasi `EXPLAIN QUERY PLAN` terhadap reverse index allocation dari schema v4. Kandidat terukur adalah menambahkan `amount` sebagai kolom covering pada indeks allocation dan/atau partial index header `ledger_entries(occurred_day, id) WHERE kind = 1`; jangan menambah indeks sebelum benchmark menunjukkan manfaat.

Migrasi v5 ke v6 hanya membuat tabel, constraint, trigger, dan indeks anggaran. Rekening beserta `balanceGroup`, kategori, header ledger, allocation, saldo, serta ID lama tidak ditulis ulang. Snapshot schema v6, fresh-create v6, dan jalur migrasi v1→v6, v2→v6, v3→v6, v4→v6, serta v5→v6 diuji agar schema extras dibuat pada `onCreate` maupun `onUpgrade`.

## Query dan performa

Daftar tidak boleh memakai satu query per kartu. Bentuk query aman memakai CTE `selected_budgets`, lalu CTE `spent_by_budget` yang menggabungkan mapping anggaran ke `ledger_allocations` dan header `ledger_entries`, kemudian menjumlahkan `allocation.amount` tepat sekali per ID budget. Hasil agregat itu baru di-`LEFT JOIN` ke metadata kategori. Saat fold, `spentAmount` di-assign sekali per budget dan `categoryId` dideduplikasi; jangan menjumlahkan ulang agregat untuk setiap row kategori.

Alternatif dua query diperbolehkan bila keduanya dijalankan dalam snapshot/transaksi baca yang konsisten: satu query agregat progres dan satu query detail mapping/kategori. Jumlah query tetap dan tidak bergantung pada jumlah kartu.

Stream snapshot wajib mengamati `budgets`, `budget_categories`, `categories`, `ledger_allocations`, dan `ledger_entries`. Perubahan header transaksi, alokasi, kategori, atau anggaran lalu memuat ulang data relevan otomatis.

Target performa menggunakan data representatif sampai batas ledger yang didukung backup pada HP Snapdragon 460/RAM 4 GB. Nominal uang dan agregasi tetap integer; `double` hanya boleh dipakai untuk rasio tampilan setelah klasifikasi integer selesai.

## Backup payload v4

Schema anggaran dan evolusi backup telah diterapkan bersama agar aplikasi tidak menghasilkan backup parsial.

- Setelah kelompok rekening memakai payload v3/schema 5, `currentBackupVersion` telah naik dari 3 ke 4 bersama penambahan anggaran.
- Versi container enkripsi tetap 1; algoritme, kata sandi, peringatan lupa kata sandi, dan ekstensi `.warasarta` tidak berubah.
- Backup baru berasal dari schema 6 dan selalu menghasilkan payload v4.
- `data.budgets` ditambahkan. Setiap record berisi `id`, `periodKind` sebagai string `monthly`/`yearly`/`custom`, `startDay`, `endDay`, `name`, `normalizedName`, `limitAmount`, `categoryIds`, `createdAtUtc`, dan `updatedAtUtc`.
- Record anggaran diurutkan berdasarkan ID. `categoryIds` wajib strictly ascending dan unik agar wire deterministik.
- `sequences.budgets` ditambahkan. `budget_categories` tidak memiliki sequence.
- Preview restore menampilkan jumlah anggaran.
- Batas awal adalah 10.000 record anggaran, maksimal 20.000 mapping pada satu anggaran, dan 100.000 mapping total. Total dihitung inkremental sebelum alokasi besar atau mutasi.
- Batas keras lama tetap berlaku: plaintext maksimal 10 MiB dan container terenkripsi maksimal 16 MiB. Estimator `_validatePayloadBudget` wajib memasukkan overhead setiap record anggaran beserta seluruh `categoryIds` sebelum encoder membangun JSON besar.

Parser tetap strict per versi:

- parser v1 hanya menerima struktur lama;
- parser v2 hanya menerima struktur allocation tanpa `balanceGroup` dan tanpa anggaran;
- parser v3 hanya menerima struktur allocation beserta `balanceGroup`, tanpa anggaran;
- parser v4 hanya menerima struktur allocation, `balanceGroup`, dan anggaran;
- field semantik yang tidak dikenal ditolak;
- pasangan yang didukung hanya (`payload v1`, `schema 3`), (`payload v2`, `schema 4`), (`payload v3`, `schema 5`), dan (`payload v4`, `schema 6`);
- aplikasi lama menolak versi yang lebih baru dan tidak boleh mengabaikan allocation atau anggaran diam-diam.

Wire DTO, parser, dan encoder dipisahkan per versi. Parser v1 menormalkan kategori/nominal ledger lama menjadi satu allocation. Parser v1 dan v2 memberi setiap rekening `balanceGroup = primary`, sedangkan parser v3 mempertahankan nilai kelompok eksplisitnya. Parser v1, v2, dan v3 sama-sama menghasilkan `budgets = []` serta sequence anggaran `0`; allocation v2+ tetap dipertahankan. Exporter schema 6 selalu menulis wire payload v4. Objek hasil normalisasi versi lama tidak boleh diserialisasi kembali dengan label lama tetapi field versi baru.

Restore backup v1, v2, atau v3 pada aplikasi schema 6 menggunakan replace-all sehingga daftar anggaran hasil restore kosong. Preview wajib menyebut dampak tersebut sebelum konfirmasi. Safety backup aplikasi schema 6 selalu dibuat sebagai payload v4 sebelum restore v1, v2, v3, maupun v4; pembatalan atau kegagalannya menghentikan restore sehingga anggaran aktif masih dapat dipulihkan.

Payload v4 wajib mengulang seluruh validasi header/allocation v2 serta validasi `balanceGroup` v3 sebelum memeriksa bagian anggaran berikut:

- exact keys, ID, sequence, timestamp UTC, serta `updatedAtUtc >= createdAtUtc`;
- `periodKind` dikenal, kedua tanggal Gregorian nyata, `startDay <= endDay`, dan bentuk canonical sesuai jenis;
- nama canonical dan invariant `normalizedName == canonicalName.toLowerCase()`;
- batas nominal valid;
- minimal satu `categoryId` unik dan strictly ascending per anggaran;
- setiap kategori tersedia, merupakan leaf pengeluaran, dan boleh berstatus arsip untuk histori;
- tidak ada nama normalized duplikat pada rentang persis sama;
- tidak ada interval overlap per kategori di seluruh jenis periode;
- ID sequence tidak lebih kecil dari ID maksimum dan tetap menyisakan headroom yang diwajibkan format backup;
- jumlah record/mapping berada dalam batas;
- tidak ada nilai turunan seperti terpakai, sisa, status, atau persentase.

Validasi overlap payload tidak boleh pairwise `O(M²)`. Kelompokkan interval berdasarkan `categoryId`, urutkan (`startDay`, `endDay`, `budgetId`), lalu bandingkan interval berurutan. Target kompleksitasnya `O(M log M)` dengan memori `O(M)` untuk `M` mapping.

Guard cakupan adapter backup diperbarui bersama payload v4, schema 6, tabel anggaran, tabel allocation yang diwarisi, `balanceGroup`, dan seluruh kolom persistennya.

## Restore atomik

Restore pada schema 6 dilakukan dalam satu transaksi database setelah payload v1/v2/v3/v4 dinormalisasi ke model terkini. Urutan konseptual:

1. validasi dan normalisasi payload sebelum transaksi mutasi;
2. ubah seluruh rekening pada database aktif menjadi nonarsip sementara agar trigger mengizinkan penghapusan ledger;
3. hapus allocation ledger, header ledger, mapping anggaran, anggaran, anak kategori, induk kategori, lalu rekening;
4. masukkan seluruh rekening incoming sebagai nonarsip beserta `balanceGroup`, lalu induk kategori, subkategori, anggaran, mapping, header ledger, dan allocation ledger;
5. setelah ledger lengkap, pulihkan status arsip rekening incoming tanpa mengubah kelompok tersimpannya;
6. pulihkan sequence rekening, kategori, ledger, serta anggaran;
7. jalankan verifier warisan schema v5: jumlah allocation kind 0/1 adalah 1–50, kind 2/3 adalah 0, posisi rapat, kategori unik/leaf/jenis cocok, jumlah allocation sama dengan total header, `balanceGroup` dikenal, nominal dalam batas, dan saldo rekening arsip valid;
8. periksa invariant anggaran: foreign key, jumlah row/mapping, minimal satu mapping, tanggal/periode canonical, leaf pengeluaran, overlap, serta sequence;
9. commit hanya bila seluruh pemeriksaan lulus.

Kesalahan apa pun me-rollback transaksi dan mempertahankan data aktif sebelum restore.

## Matriks pengujian minimum

### Repository dan aturan domain

- create periode bulanan, tahunan, kustom satu hari, dan kustom lintas tahun;
- tanggal `2000-02-29` dan `9999-12-31` diterima;
- `2025-02-29`, `2100-02-29`, `2026-04-31`, `startDay > endDay`, serta tanggal di luar rentang ditolak;
- bentuk bulanan/tahunan noncanonical ditolak;
- nama, nominal, atau kategori kosong/tidak valid ditolak;
- kategori tidak ada, pemasukan, induk, atau arsip baru ditolak;
- subkategori sama pada rentang bersebelahan diterima;
- endpoint yang sama serta overlap bulanan–tahunan, bulanan–kustom, tahunan–kustom ditolak;
- kandidat yang melintasi beberapa anggaran berurutan mengembalikan seluruh `BudgetConflict` dengan ID, nama, dan periode penyebab;
- rentang tumpang tindih dengan subkategori berbeda diterima;
- kategori atau induk arsip yang sudah terhubung boleh dipertahankan/dilepas berdasarkan selisih set, tetapi tidak boleh baru ditambahkan;
- edit atomik tidak meninggalkan mapping parsial saat gagal;
- create/update memeriksa minimal satu mapping sebelum commit;
- edit tetap berhasil dengan timestamp monotonik ketika jam perangkat mundur;
- delete hanya menghapus budget dan mapping;
- periode tidak dapat diedit.

### Progres

- tanpa transaksi, batas status 79%/80%/99%/100%, lebih dari 100%, dan nominal mendekati `maxAmount` tanpa overflow;
- beberapa subkategori dijumlahkan tanpa double count;
- satu transaksi split Rp15.000 Makan dan Rp2.000 Parkir menambah masing-masing anggaran tepat sebesar allocation-nya tanpa menjumlahkan total header Rp17.000 dua kali;
- kedua endpoint inklusif pada periode bulanan, tahunan, dan kustom;
- tahun kabisat, Desember→Januari, dan custom satu hari;
- kategori atau induk yang diarsipkan tetap dihitung;
- pemasukan, transfer, serta penyesuaian tidak dihitung;
- add/edit/delete transaksi maupun perubahan nominal/kategori allocation memperbarui progres;
- perpindahan tanggal, kategori, atau jenis transaksi memindahkan kontribusi ke anggaran yang benar;
- filter tampilan tidak memotong rentang agregasi anggaran;
- rename kategori tidak memutus relasi.

### Database dan migrasi

- migrasi v5→v6 menjaga seluruh data allocation, kelompok rekening, dan saldo;
- migrasi berantai v1→v6, v2→v6, v3→v6, dan v4→v6;
- raw `INSERT` maupun `UPDATE` mapping ke kategori root/pemasukan/overlap ditolak trigger;
- pemindahan tuple mapping tidak salah berkonflik dengan row lamanya;
- update periode ditolak;
- cascade budget→mapping dan restrict kategori terbukti;
- schema snapshot, indeks, trigger, constraint tanggal, dan foreign key sesuai kontrak.

### Backup dan restore

- JSON dan enkripsi round-trip payload v4;
- fixture v1, v2, dan v3 permanen direstore dengan anggaran kosong dan safety backup v4; fixture v1/v2 menghasilkan `balanceGroup = primary`, sedangkan v3 mempertahankan kelompoknya;
- v4 menjaga ID, sequence, allocation, `balanceGroup`, periode, kategori arsip, dan seluruh mapping;
- fixture payload v4 dengan allocation kosong/posisi gap/kategori duplikat atau salah jenis/mismatch total/kelompok rekening tidak dikenal ditolak sebelum mutasi walaupun bagian anggarannya valid;
- invalid kind/tanggal/bentuk periode, struktur asing, mismatch `normalizedName`, urutan/duplikasi `categoryIds`, kategori tidak valid, mapping kosong, serta overlap ditolak sebelum mutasi;
- batas jumlah record dan total mapping ditolak sebelum alokasi besar;
- estimator byte memasukkan seluruh record/mapping; plaintext di atas 10 MiB dan container di atas 16 MiB tetap ditolak;
- kegagalan di tengah restore me-rollback tabel lama dan baru;
- provider anggaran dimuat ulang setelah restore;
- guard cakupan gagal bila schema, tabel, atau kolom berubah tanpa pembaruan adapter.

### UI dan perangkat

- tab Aktif/Mendatang/Riwayat dan seluruh filter jenis;
- empty/loading/error/retry;
- create/edit/delete serta pesan konflik lengkap;
- pemilih bulanan/tahunan/kustom, custom tanpa silent default, dan periode read-only saat edit;
- kategori terpilih yang menjadi konflik setelah periode berubah dapat dilepas, sedangkan kategori konflik baru tidak dapat ditambahkan;
- bulanan dan kustom dengan rentang identik berbagi label kelompok tetapi mempunyai badge jenis berbeda;
- kelompok campuran under/over menghasilkan `groupLimit`, `groupSpent`, `groupNet`, dan jumlah status yang tepat;
- tie-breaker kelompok/kartu dan ranking global dua item Ikhtisar deterministik;
- satu kategori dapat menjelaskan beberapa `BudgetConflict` tanpa memotong sumber konflik;
- dashboard memakai hari ini, bukan bulan transaksi yang sedang dipilih;
- tidak ada total global yang mencampur rentang berbeda;
- nominal dan status overspending tidak hanya dibedakan lewat warna;
- lebar 320 px dan text scale 200% tidak overflow;
- perubahan hari, resume aplikasi, atau perubahan zona waktu menghitung ulang `referenceDay` lokal dan status;
- query data representatif terasa responsif pada HP referensi.

## Di luar ruang lingkup v1

- rollover atau membawa sisa ke periode berikutnya;
- anggaran berulang dan copy otomatis;
- pemecahan otomatis anggaran tahunan/kustom menjadi target per bulan;
- hierarki anggaran tahunan dengan child bulanan pada kategori yang sama;
- mengedit jenis atau tanggal periode setelah dibuat;
- notifikasi ambang 50/80/100%;
- rekomendasi batas otomatis;
- pemblokiran transaksi ketika batas tercapai;
- pembagian anggaran per rekening;
- histori perubahan batas atau audit log anggaran;
- tujuan keuangan, utang/piutang, serta sinkronisasi cloud.

## Lokasi implementasi dan pengujian

- Domain dan kontrak repository: `lib/domain/budget.dart` serta `lib/domain/budget_repository.dart`.
- Schema, migrasi, constraint, trigger, dan integritas: `lib/data/database/app_database.dart`, `lib/data/database/app_database.steps.dart`, serta snapshot `drift_schemas/app_database/drift_schema_v6.json`.
- Repository Drift: `lib/data/repositories/drift_budget_repository.dart`.
- State dan antarmuka CRUD/progres: `lib/features/budgets/`, dengan dependency wiring di `lib/app/providers.dart`, rute di `lib/app/router.dart`, dan ringkasan aktif pada Ikhtisar.
- Backup v4 dan restore legacy: `lib/domain/backup.dart` serta `lib/data/backup/`.
- Pengujian utama: `test/domain/budget_test.dart`, `test/data/drift_budget_repository_test.dart`, `test/drift/app_database/migration_test.dart`, `test/data/drift_backup_data_store_test.dart`, `test/data/encrypted_backup_codec_test.dart`, `test/features/budgets/`, dan `test/app_test.dart`.

## Kriteria selesai

Kriteria implementasi dan integritas data Anggaran v1 telah dipenuhi: pengguna dapat membuat, melihat, mengubah, dan menghapus anggaran bulanan, tahunan, maupun kustom dengan banyak subkategori; progres mengikuti nominal allocation pada seluruh rentang; overlap lintas jenis ditolak; histori kategori arsip tetap akurat; backup v1, v2, v3, dan v4 dipulihkan sesuai kontrak; serta migrasi lama aman. Kenyamanan, aksesibilitas, dan performa alur utama pada HP referensi tetap harus dibuktikan lewat checklist perangkat fisik sebelum pemakaian nyata atau rilis.
