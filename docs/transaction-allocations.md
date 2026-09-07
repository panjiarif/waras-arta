# Alokasi Transaksi Waras Arta

## Status dan tujuan

Dokumen ini adalah kontrak implementasi **Alokasi Transaksi v1**. Implementasi belum dimulai. Fitur ini dikerjakan sebelum anggaran karena nominal per subkategori menjadi sumber data bagi progres anggaran, rincian kategori, dan diagram.

Satu pencatatan pemasukan atau pengeluaran tetap tampil sebagai satu transaksi, tetapi dapat dibagi menjadi beberapa pasangan nominal dan subkategori. Contoh: satu pembayaran Rp17.000 dapat terdiri dari **Makan Rp15.000** dan **Parkir Rp2.000**.

Tujuan versi pertama:

- mempertahankan satu identitas, rekening, tanggal, dan catatan untuk satu pembayaran;
- memungkinkan satu sampai 50 alokasi nominal–subkategori pada pemasukan atau pengeluaran;
- menghitung total transaksi dari jumlah seluruh baris alokasi;
- mempertahankan perhitungan saldo, ringkasan, kalender, dan jumlah transaksi yang sudah ada;
- menyediakan fondasi kategori–nominal yang langsung dapat dipakai anggaran;
- memigrasikan data lama dan backup versi 1 tanpa kehilangan saldo maupun identitas transaksi.

## Istilah

- **Header transaksi** adalah row `ledger_entries`. Header menyimpan identitas transaksi, jenis, rekening, total, tanggal kejadian, catatan, dan waktu pencatatan.
- **Alokasi** adalah satu row `ledger_allocations` yang memasangkan sebagian nominal transaksi dengan tepat satu subkategori.
- **Total transaksi** adalah jumlah seluruh nominal alokasi untuk pemasukan/pengeluaran. Total ini disimpan pada header sebagai nilai canonical hasil perhitungan repository, bukan input kedua dari pengguna.
- **Transaksi split** adalah pemasukan atau pengeluaran dengan lebih dari satu alokasi. Transaksi dengan satu alokasi memakai model data yang sama dan bukan representasi khusus.
- **Posisi** adalah urutan stabil alokasi di dalam satu transaksi, dimulai dari `0` dan selalu rapat sampai `N - 1`.

## Keputusan model utama

1. `ledger_entries` tetap menjadi header serta ID stabil satu transaksi.
2. Semua pemasukan dan pengeluaran mempunyai satu sampai 50 row `ledger_allocations`, termasuk transaksi biasa yang hanya mempunyai satu subkategori.
3. Transfer dan penyesuaian saldo tidak mempunyai alokasi.
4. Kolom `category_id` dihapus dari `ledger_entries` pada schema v4. Tidak ada mode campuran antara kategori langsung pada header dan kategori pada tabel alokasi.
5. Satu alokasi hanya mempunyai nominal dan subkategori. Rekening, jenis, tanggal, catatan, serta `createdAt` berlaku bagi seluruh transaksi dan tidak diduplikasi ke setiap alokasi.
6. Total pemasukan/pengeluaran selalu diturunkan dari jumlah baris. Form tidak mempunyai field total lain yang dapat berbeda dari jumlah tersebut.
7. Saldo, ringkasan arus kas, jumlah transaksi, pagination, dan kalender tetap memakai satu header sebagai satu transaksi. Rincian kategori, diagram kategori, dan anggaran memakai nominal alokasi.
8. Split bukan transfer antar-rekening dan bukan model akuntansi double-entry. Seluruh alokasi dalam satu pemasukan/pengeluaran memakai rekening header yang sama.

## Aturan produk dan invariant

### Pemasukan dan pengeluaran

- Wajib mempunyai minimal satu dan maksimal 50 alokasi.
- Setiap nominal alokasi berupa bilangan bulat rupiah dari `1` sampai `maxAmount`.
- Setiap alokasi wajib menunjuk subkategori leaf yang jenisnya sama dengan transaksi.
- Subkategori yang sama hanya boleh muncul sekali dalam satu transaksi. Pengguna menambah nominal pada baris yang sudah ada, bukan membuat dua baris kategori identik.
- Posisi wajib unik, dimulai dari `0`, berurutan tanpa celah, dan sesuai urutan yang ditampilkan serta disimpan.
- Total header wajib sama persis dengan jumlah seluruh nominal alokasi dan berada dalam `1..maxAmount`.
- Penjumlahan serta pemeriksaan batas dilakukan dengan integer. Overflow atau jumlah di atas `maxAmount` ditolak sebelum database ditulis.
- `destinationAccountId` wajib `null`.

### Transfer

- Tetap merupakan satu header dengan rekening asal, rekening tujuan, dan nominal positif.
- Rekening asal dan tujuan wajib berbeda.
- Wajib mempunyai tepat nol alokasi.
- Tidak dihitung sebagai pemasukan, pengeluaran, maupun pemakaian anggaran.

### Penyesuaian saldo

- Tetap merupakan satu header dengan delta bertanda nonnol.
- Wajib mempunyai tepat nol alokasi.
- Tidak dapat dibuat atau diedit melalui form transaksi biasa.
- Tidak dihitung sebagai pemasukan, pengeluaran, maupun pemakaian anggaran.

### Kategori arsip

Kategori arsip tetap diperlukan untuk membaca histori. Trigger database tidak menolak alokasi hanya karena anak atau induknya berstatus arsip.

Saat membuat transaksi, seluruh subkategori baru beserta induknya wajib aktif. Saat mengedit, validasi memakai selisih set:

- kategori pada `newCategoryIds - existingCategoryIds` wajib aktif;
- kategori arsip pada irisan kedua set boleh dipertahankan dan nominalnya boleh diubah;
- kategori lama boleh dilepas;
- kategori arsip yang sudah dilepas tidak dapat ditambahkan kembali sampai dipulihkan;
- perubahan jenis pemasukan ↔ pengeluaran membuat seluruh kategori dianggap pilihan baru karena jenis kategori harus berubah.

Aturan rekening arsip tetap berlaku pada tingkat header: transaksi lama tetap dapat dilihat, tetapi tidak dapat diedit atau dihapus sampai semua rekening yang disentuhnya dipulihkan.

## Pengalaman pengguna

### Form pemasukan/pengeluaran

Form baru membuka satu baris kosong berisi:

- input nominal;
- pemilih subkategori yang sesuai jenis transaksi;
- label urutan yang dapat dipahami pembaca layar.

Di bawah daftar tersedia tombol dengan **ikon plus dan teks `Tambah kategori lain`**. Ikon tanpa teks tidak cukup. Menekan tombol menambah satu baris kosong pada posisi terakhir. Tombol dinonaktifkan ketika sudah ada 50 baris dan menampilkan keterangan bahwa batas pembagian tercapai.

Total ditampilkan sebagai ringkasan read-only yang diperbarui ketika nominal berubah. Selama masih ada baris kosong/tidak valid, kategori belum dipilih/duplikat, atau jumlah melampaui batas, labelnya **Total sementara Rp…** dengan pesan bagian yang perlu diperbaiki; jangan menampilkan Rp0 atau total lama seolah final. Setelah semua baris valid, label berubah menjadi **Total transaksi Rp…**. Total bukan `TextFormField` dan tidak dapat diedit tersendiri.

Perilaku baris:

- baris dapat dihapus selama masih tersisa minimal satu;
- setelah penghapusan, posisi berikutnya dirapatkan kembali menjadi `0..N-1`;
- pada pemilih suatu baris, kategori yang dipakai baris lain dinonaktifkan dengan subtitle **Dipakai pada Bagian N**; kategori milik baris itu sendiri tetap dapat diganti atau dilepas;
- pilihan subkategori tetap dikelompokkan berdasarkan induk dan menampilkan ikon yang ada;
- kategori atau induk arsip yang sudah tersimpan tetap tampil pada baris edit dengan badge teks **Arsip**; nominalnya boleh diubah dan barisnya boleh dilepas, tetapi kategori itu tidak tersedia untuk assignment baru;
- urutan input disimpan. Drag-and-drop tidak wajib; versi pertama memakai urutan penambahan dan hasil penghapusan yang sudah dirapatkan;
- error berada dekat baris penyebab dan ringkasan form tetap menjelaskan mengapa simpan ditolak.

Rekening, tanggal kejadian, dan catatan tetap satu untuk seluruh pembayaran. Form tidak menawarkan rekening, tanggal, atau catatan berbeda per alokasi.

Pada lebar 320 px atau text scale 200%, satu bagian wajib disusun vertikal: identitas bagian, pemilih kategori, input nominal, lalu aksi hapus. Jangan memaksa kategori–nominal–hapus ke dalam satu `Row` sempit. Setelah tambah, fokus berpindah ke pemilih kategori bagian baru; setelah hapus, fokus menuju bagian sebelumnya atau tombol tambah.

Ringkasan total tidak menjadi live region pada setiap digit karena akan terlalu berisik bagi TalkBack. Perubahan status valid/invalid diumumkan setelah tambah/hapus bagian atau ketika pengguna mencoba menyimpan; semantic label membedakan **total sementara** dari **total transaksi**.

### Perubahan jenis transaksi

- Pemasukan ↔ pengeluaran mempertahankan nominal dan posisi baris, tetapi harus mengosongkan seluruh kategori lama. Jika setidaknya satu kategori sudah dipilih, tampilkan konfirmasi lebih dahulu; pembatalan mempertahankan jenis dan seluruh baris tanpa perubahan.
- Pemasukan/pengeluaran → transfer memerlukan konfirmasi bila form sudah berisi data. Nilai total turunan dapat menjadi nilai awal nominal transfer; seluruh alokasi kemudian dilepas.
- Transfer → pemasukan/pengeluaran membuat satu baris dengan nominal transfer sebagai nilai awal dan subkategori kosong.
- Perubahan jenis tidak pernah meninggalkan alokasi pada transfer atau kategori dengan jenis yang salah.

### Edit dan penghapusan

Form edit memuat seluruh alokasi sesuai `position`. Simpan mengganti set alokasi secara penuh dalam satu transaksi database, mempertahankan ID header dan `createdAt`. Posisi dinormalisasi kembali sebelum validasi dan penulisan.

Menghapus transaksi meminta konfirmasi satu kali pada tingkat header. Jika disetujui, penghapusan header menghapus seluruh alokasinya melalui cascade. Aplikasi tidak menanyakan atau menghapus alokasi satu per satu, dan transaksi tidak dapat tersisa sebagian.

Penekanan tombol simpan/hapus berulang ketika operasi berjalan tidak boleh menghasilkan transaksi ganda atau update parsial. Form yang kotor meminta konfirmasi sebelum ditutup.

### Riwayat dan detail

- Satu header selalu menghasilkan satu kartu/baris riwayat, berapa pun jumlah alokasinya.
- Nominal utama kartu adalah total header.
- Satu alokasi menampilkan nama serta ikon subkategori seperti perilaku sekarang.
- Beberapa alokasi memakai ikon netral `receipt_long`, label teks **N kategori**, dan maksimal dua nama subkategori lalu **+N lainnya**; ikon kategori pertama tidak boleh mewakili seluruh transaksi.
- Semantic label kartu tetap ringkas: jenis, total, rekening, tanggal, dan jumlah kategori; daftar lengkap tersedia pada detail.
- Detail menampilkan total, rekening, tanggal, catatan, waktu pencatatan, lalu seluruh alokasi sesuai posisi dengan nominal masing-masing. Allocation yang kategorinya diarsipkan mempunyai badge teks **Arsip**, bukan hanya perbedaan warna.
- Rename atau perubahan ikon kategori langsung tercermin karena alokasi menyimpan ID, bukan salinan nama.
- Pagination, urutan tanggal, dan navigasi ke detail menggunakan ID header, bukan row alokasi.

### Kalender dan ringkasan

- Satu transaksi split menambah jumlah catatan harian sebanyak satu, bukan sebanyak jumlah alokasi.
- Total pemasukan/pengeluaran harian dan bulanan memakai total header sehingga hasilnya sama dengan jumlah alokasi tanpa duplikasi.
- Penanda kalender tetap diturunkan dari jenis header.
- Daftar tanggal terpilih menampilkan satu transaksi dan memakai aturan ikon, label jumlah kategori, serta ringkasan yang sama dengan riwayat.
- Breakdown berdasarkan kategori menjumlahkan `ledger_allocations.amount`, bukan seluruh total header untuk setiap kategori.

Seluruh tampilan wajib aman pada lebar 320 px, text scale 200%, keyboard terbuka, dan perangkat referensi. Tombol tambah/hapus baris mempunyai target minimal 48 dp, tooltip, label semantik yang menyebut bagian sasaran, serta tidak dibedakan hanya melalui warna.

## Model domain dan repository

Model minimum:

- `EntryAllocationDraft`: `categoryId` dan `amount`;
- `FinanceEntryAllocation`: posisi, identitas/metadata kategori, nominal, dan status arsip;
- `EntryDraft`: data header serta daftar allocation untuk pemasukan/pengeluaran;
- `FinanceEntry`: data header, total, dan daftar allocation immutable;
- hasil query/detail tidak mengekspos row database mutable ke UI.

Daftar draft berada dalam urutan UI. Repository menormalisasinya menjadi posisi `0..N-1`, memvalidasi semua baris, menghitung total satu kali, lalu baru membuka operasi tulis. Pemanggil tidak boleh mengirim total pemasukan/pengeluaran yang terpisah dari daftar alokasi.

Kontrak `FinanceRepository` yang ada dapat mempertahankan operasi berikut:

```dart
Future<int> addEntry(EntryDraft draft);
Future<void> updateEntry(int id, EntryDraft draft);
Future<void> deleteEntry(int id);
```

Makna `EntryDraft` berevolusi. Untuk membantu migrasi call site, constructor/factory satu alokasi boleh disediakan, tetapi akhirnya harus menghasilkan daftar berisi satu `EntryAllocationDraft`, bukan menulis `categoryId` langsung ke header.

Create berlangsung atomik:

1. validasi dan normalisasi seluruh draft;
2. validasi rekening aktif dan kategori baru yang dapat dipakai;
3. insert header dengan total turunan;
4. insert seluruh alokasi dengan posisi canonical;
5. periksa jumlah, posisi, jenis kategori, dan jumlah nominal;
6. commit hanya bila semua invariant terpenuhi.

Update berlangsung atomik:

1. baca header serta alokasi lama;
2. terapkan aturan rekening/kategori arsip dan validasi draft baru;
3. hapus alokasi lama;
4. update header, termasuk total turunan;
5. insert seluruh alokasi baru;
6. periksa invariant akhir;
7. commit atau rollback seluruh perubahan.

Keadaan sementara tanpa alokasi di dalam transaksi update diperbolehkan. Tidak ada trigger row SQLite yang dapat menegakkan secara deferred bahwa jumlah alokasi minimal satu, posisi rapat, atau jumlah nominal sama dengan header setelah beberapa insert. Repository, parser backup, dan pemeriksaan integritas restore menjadi penegak invariant transaksi tersebut.

## Schema Drift v4

Schema database v4 menormalkan hubungan kategori transaksi dengan menambah `ledger_allocations` dan membangun ulang `ledger_entries` tanpa `category_id`.

### `ledger_entries` sebagai header

Kolom yang dipertahankan:

| Kolom | Aturan |
| --- | --- |
| `id` | integer primary key autoincrement dan ID transaksi stabil |
| `kind` | 0 pemasukan, 1 pengeluaran, 2 transfer, 3 penyesuaian |
| `account_id` | rekening utama, foreign key `accounts.id` |
| `destination_account_id` | hanya wajib untuk transfer |
| `amount` | total turunan untuk pemasukan/pengeluaran; nominal transfer; delta penyesuaian |
| `note` | satu catatan transaksi, maksimal 500 karakter |
| `occurred_day` | tanggal sipil `YYYYMMDD` |
| `created_at` | waktu pencatatan |

Constraint nominal serta tanggal tetap mengikuti schema v3. Constraint bentuk jenis berubah menjadi:

- pemasukan/pengeluaran: tujuan `null` dan `amount` positif;
- transfer: tujuan wajib ada, berbeda dari sumber, dan `amount` positif;
- penyesuaian: tujuan `null` dan `amount` bertanda nonnol;
- header tidak lagi mempunyai foreign key kategori.

### `ledger_allocations`

| Kolom | Aturan |
| --- | --- |
| `entry_id` | foreign key ke `ledger_entries.id`, `ON DELETE CASCADE` |
| `position` | integer `0..49` |
| `category_id` | foreign key ke `categories.id`, `ON DELETE RESTRICT` |
| `amount` | integer rupiah `1..999999999999` |

Primary key gabungan adalah (`entry_id`, `position`). Unique constraint tambahan adalah (`entry_id`, `category_id`). Tabel tidak memiliki ID autoincrement atau row `sqlite_sequence` sendiri.

`position BETWEEN 0 AND 49` bersama primary key membatasi satu header maksimal 50 row. Keutuhan `0..N-1` tanpa celah diperiksa repository dan restore karena CHECK per-row tidak dapat melihat posisi lain.

Trigger dan indeks wajib:

- `BEFORE INSERT` serta `BEFORE UPDATE OF entry_id, category_id` pada allocation menolak parent yang tidak ada, parent transfer/penyesuaian, kategori root, dan kategori dengan jenis berbeda;
- `BEFORE UPDATE OF kind` pada header menolak hasil yang membuat allocation tersisa pada transfer/penyesuaian atau tidak cocok dengan jenis pemasukan/pengeluaran baru;
- status arsip tidak menjadi syarat trigger agar histori dan restore tetap sah;
- penghapusan header melakukan cascade ke allocation, sedangkan penghapusan kategori yang direferensikan dibatasi;
- indeks `ledger_allocations_category_entry(category_id, entry_id)` melayani reverse lookup kategori; primary key melayani lookup detail berdasarkan header;
- indeks serta trigger `ledger_entries.category_id` schema lama dihapus/diganti;
- trigger rekening aktif yang sudah ada tetap menjaga mutasi header dan tidak diduplikasi pada allocation.

Invariant lintas-row yang diperiksa sebelum commit dan saat pemeriksaan integritas:

- kind 0/1 mempunyai `COUNT(*) BETWEEN 1 AND 50`;
- kind 2/3 mempunyai `COUNT(*) = 0`;
- posisi setiap header persis `0..COUNT(*)-1`;
- kategori unik dan merupakan leaf dengan jenis sama;
- `ledger_entries.amount = SUM(ledger_allocations.amount)` untuk kind 0/1;
- total tetap dalam batas `maxAmount`;
- seluruh foreign key valid.

## Migrasi v3 ke v4

Migrasi harus menjaga data pribadi yang sudah ada dan berlangsung atomik. Strategi konseptual:

1. nonaktifkan pemeriksaan foreign key sesuai pola migrasi yang sudah ada, di luar transaksi schema;
2. catat high-water mark `sqlite_sequence` ledger dan ID maksimum;
3. buat tabel staging tanpa foreign key berisi `entry_id`, `position = 0`, `category_id`, dan `amount` untuk setiap ledger kind pemasukan/pengeluaran;
4. pastikan setiap row lama kind 0/1 mempunyai kategori leaf dengan jenis yang cocok sebelum perubahan destruktif;
5. bangun ulang `ledger_entries` tanpa `category_id`, dengan seluruh ID, jenis, rekening, tujuan, nominal, catatan, tanggal, dan `created_at` lama;
6. buat `ledger_allocations` dan masukkan seluruh row staging;
7. hapus staging, buat ulang trigger/indeks schema v4, dan pulihkan sequence ledger sekurang-kurangnya `max(oldSequence, maximumLedgerId)`;
8. jalankan pemeriksaan integritas serta `PRAGMA foreign_key_check` sebelum commit;
9. aktifkan kembali foreign key pada blok `finally`.

Pembuatan allocation lebih aman dilakukan setelah rebuild header dengan data staging, bukan membuat tabel ber-FK lalu menjatuhkan tabel header yang sedang direferensikan.

Migrasi wajib membuktikan:

- jumlah header dan seluruh ID tidak berubah;
- setiap pemasukan/pengeluaran lama menjadi tepat satu allocation pada posisi 0 dengan kategori dan nominal lama;
- transfer dan penyesuaian menjadi nol allocation;
- saldo per rekening, saldo total, ringkasan bulanan, kalender, tanggal, catatan, serta urutan riwayat identik sebelum/sesudah;
- sequence ledger tidak mundur dan insert berikutnya tidak bertabrakan;
- kegagalan validasi atau insert me-rollback seluruh migrasi.

Snapshot schema v4, fresh-create v4, serta jalur v1→v4, v2→v4, dan v3→v4 wajib diuji. Schema extras harus terbentuk baik melalui `onCreate` maupun `onUpgrade`.

## Query dan performa

Query yang memakai total transaksi tetap membaca header:

- saldo rekening dan saldo total;
- ringkasan pemasukan/pengeluaran harian atau bulanan;
- jumlah transaksi;
- penanda serta total kalender.

Query yang mengelompokkan berdasarkan kategori membaca allocation dan bergabung ke header untuk jenis/tanggal/rekening:

- breakdown kategori;
- filter transaksi berdasarkan kategori;
- diagram komposisi;
- progres anggaran.

Riwayat tidak boleh melakukan `JOIN ledger_allocations` sebelum `LIMIT/OFFSET`, karena satu header split akan menggandakan row dan dapat membuat transaksi hilang dari halaman. Pilih halaman ID/header lebih dahulu, kemudian muat seluruh allocation untuk kumpulan ID tersebut dengan satu query tambahan, atau gunakan CTE page header. Kedua hasil harus berasal dari snapshot baca konsisten dan jumlah query tidak bertambah per kartu.

Detail satu transaksi dapat memakai satu query header dan satu query allocation. Daftar tanggal kalender juga tetap mem-page/mengurutkan header, lalu mengambil allocation untuk seluruh ID dalam satu batch. Tidak boleh ada pola N+1.

Penghitungan referensi kategori, aturan hapus kategori, dan tampilan histori kategori dipindahkan dari `ledger_entries.category_id` ke `ledger_allocations.category_id`. Rename/ikon tetap diambil dari tabel kategori saat query.

Indeks awal cukup primary key allocation dan `ledger_allocations_category_entry`. Indeks tambahan untuk filter tanggal+category atau anggaran hanya ditambahkan setelah `EXPLAIN QUERY PLAN` dan benchmark data representatif. Pengujian dilakukan dalam profile mode pada HP Snapdragon 460/RAM 4 GB; debug mode bukan dasar kesimpulan performa.

## Backup payload v2

Schema v4 dan dukungan allocation harus dirilis bersama evolusi payload backup agar split tidak pernah hilang saat restore.

Matrix format yang dikunci:

| Payload | Schema sumber | Representasi kategori transaksi | Anggaran |
| --- | --- | --- | --- |
| v1 | 3 | satu `categoryId` langsung pada record ledger kind 0/1 | tidak ada |
| v2 | 4 | `allocations` pada record ledger kind 0/1 | tidak ada |
| v3 (direncanakan) | 5 (direncanakan) | `allocations` | `data.budgets` |

Versi container enkripsi tetap 1 untuk ketiganya. Perubahan algoritme atau profil kriptografi tidak diperlukan oleh perubahan payload ini.

### Bentuk wire v2

Record ledger v2 mempunyai exact keys header yang sama dengan v1, kecuali `categoryId` diganti dengan `allocations`. Setiap item allocation mempunyai exact keys:

```json
{
  "position": 0,
  "categoryId": 10,
  "amount": 15000
}
```

Allocation diurutkan strictly ascending menurut `position`; posisi wajib sama dengan indeks array `0..N-1`. `categoryId` wajib unik di dalam record. Record ledger tetap diurutkan berdasarkan ID.

Validasi payload v2 mencakup seluruh aturan payload v1 yang masih relevan dan invariant berikut:

- kind pemasukan/pengeluaran mempunyai 1..50 allocation;
- kind transfer/penyesuaian mempunyai array allocation kosong;
- posisi canonical, category ID unik, nominal allocation valid, dan jumlah tidak overflow;
- seluruh kategori allocation tersedia, merupakan leaf, dan jenisnya sama dengan ledger; kategori arsip diperbolehkan untuk histori;
- jumlah nominal allocation sama persis dengan `ledger.amount` dan total berada dalam batas;
- total allocation pada satu dokumen tidak melebihi `maxBackupLedgerAllocationRecords = 200000`;
- seluruh exact keys, foreign key, ID, tanggal, timestamp, catatan, rekening, dan saldo arsip valid sebelum mutasi.

`ledger_allocations` tidak menambah sequence. `sequences` v2 tetap berisi high-water mark accounts, categories, dan ledger entries. Guard cakupan adapter dipindahkan ke pasangan payload v2/schema v4 dan mematok seluruh tabel serta kolom persisten, termasuk hilangnya `ledger_entries.category_id` dan hadirnya `ledger_allocations`.

Batas plaintext 10 MiB serta container 16 MiB tetap berlaku. Estimator pra-encoding wajib memperhitungkan setiap allocation sebelum membangun JSON besar. Batas jumlah record adalah pertahanan tambahan dan bukan janji bahwa kombinasi maksimum semua record akan muat di bawah batas byte.

### Kompatibilitas decoder

- Parser v1 tetap strict terhadap wire lama dan hanya menerima pasangan payload v1/schema 3.
- Decoder v1 menormalisasi pemasukan/pengeluaran menjadi satu allocation posisi 0 dari `categoryId` dan `amount`; transfer/penyesuaian menjadi daftar kosong.
- Parser v2 strict terhadap wire baru dan hanya menerima pasangan payload v2/schema 4.
- Exporter schema 4 selalu menghasilkan payload v2. Model hasil normalisasi v1 tidak boleh diserialisasi kembali dengan label v1 tetapi field v2.
- Aplikasi schema 3 menolak payload v2. Aplikasi schema 4 menerima v1/v2.
- Ketika anggaran schema 5 ditambahkan, payload v3 mempertahankan bentuk allocation v2 dan menambahkan anggaran. Aplikasi schema 5 menerima v1/v2/v3; restore v1 atau v2 menghasilkan `budgets = []` dan sequence budget 0, dengan dampaknya dijelaskan pada preview.

## Restore atomik

Restore schema v4 tetap menggunakan replace-all dan safety backup wajib. Setelah file didekripsi, parser menormalisasi v1 maupun v2 ke model allocation terkini serta memvalidasi seluruh invariant sebelum transaksi mutasi.

Urutan konseptual schema v4:

1. validasi dan normalisasi payload;
2. ubah seluruh rekening yang sudah ada pada database tujuan menjadi nonarsip sementara agar trigger ledger mengizinkan penghapusan, termasuk rekening yang sebelumnya berstatus arsip;
3. hapus allocation lama, ledger, anak kategori, induk kategori, lalu rekening;
4. insert rekening incoming sebagai nonarsip, induk kategori, subkategori, header ledger, lalu allocation;
5. pulihkan status arsip rekening hanya setelah seluruh header selesai dimasukkan;
6. pulihkan sequence accounts, categories, dan ledger;
7. periksa foreign key, jumlah row, posisi, jenis, category uniqueness, jumlah nominal, saldo arsip, serta sequence;
8. commit hanya bila semua pemeriksaan lulus.

Urutan konseptual schema v5 mendatang juga harus menghapus `ledger_allocations` dan `budget_categories` sebelum kategori. Insert berlangsung accounts → categories → budgets → budget mappings → ledger headers → allocations, lalu status arsip dan seluruh sequence dipulihkan.

Sebelum replace-all v1 maupun v2, aplikasi schema v4 membuat safety backup payload v2 dari keadaan aktif dan mewajibkan penyimpanan serta verifikasi ukuran/SHA-256 berhasil. Pembatalan atau kegagalan safety backup menghentikan restore tanpa perubahan database. Aplikasi schema v5 kelak selalu membuat safety backup payload v3 sebelum restore v1/v2/v3.

Kesalahan apa pun di tengah restore harus me-rollback header dan allocation bersama-sama. Tidak boleh ada keadaan berhasil yang kehilangan satu bagian split.

## Matriks pengujian minimum

### Domain dan repository

- create pemasukan/pengeluaran dengan satu, dua, dan 50 allocation;
- allocation kosong, 51 baris, nominal nol/negatif/di atas batas, total di atas batas, posisi tidak canonical, dan kategori duplikat ditolak;
- kategori tidak ada, root, jenis salah, atau arsip baru ditolak;
- kategori/induk arsip lama boleh dipertahankan, diubah nominalnya, atau dilepas, tetapi tidak ditambahkan kembali;
- total header selalu sama dengan jumlah allocation dan tidak menerima total input kedua;
- edit satu→split, split→satu, tambah/hapus baris, perubahan posisi, serta perubahan kind berlangsung atomik;
- pembatalan konfirmasi perubahan pemasukan↔pengeluaran mempertahankan jenis dan seluruh baris;
- transfer dan adjustment menolak setiap allocation;
- kegagalan insert/update di tengah batch me-rollback header maupun seluruh allocation;
- delete header menghapus seluruh allocation, sedangkan category referenced tidak dapat dihapus.

### Migrasi dan schema

- fresh-create v4 mempunyai seluruh table, constraint, trigger, index, dan seed yang benar;
- migrasi v3→v4 serta chain v1→v4 dan v2→v4 menjaga data;
- setiap legacy income/expense menjadi satu allocation posisi 0; transfer/adjustment tetap tanpa allocation;
- ID, sequence, saldo per rekening, total saldo, ringkasan, tanggal, catatan, dan jumlah transaksi sama sebelum/sesudah;
- raw insert/update allocation ke parent kind salah, kategori root, atau kategori kind salah ditolak trigger;
- raw update header menjadi transfer/adjustment dengan allocation ditolak;
- gap posisi atau mismatch SUM yang tidak dapat dicegah row trigger ditemukan pemeriksaan integritas;
- foreign-key error atau fixture lama tidak valid membuat migrasi rollback.

### Query dan tampilan

- satu transaksi split muncul sekali di riwayat, kalender, pagination, serta jumlah transaksi;
- total saldo/harian/bulanan menggunakan total header tepat sekali;
- breakdown kategori memakai nominal setiap allocation;
- halaman 50 header tidak terpotong oleh jumlah allocation dan load-more tidak duplikat;
- batch allocation tidak menghasilkan N+1;
- detail menampilkan seluruh baris dalam urutan posisi dan total yang cocok;
- edit/hapus memperbarui rekening, bulan/tanggal lama dan baru, kategori, serta stream terkait;
- form default satu baris, tombol ikon+teks menambah sampai 50, fokus berpindah dengan benar, dan total sementara/final read-only bereaksi sesuai validitas;
- picker menonaktifkan kategori duplikat dengan sumber bagian, kategori arsip mempunyai badge per baris, serta ikon single/split tidak menyesatkan;
- baris invalid, double submit, dirty Back, layout vertikal 320 px, keyboard, text scale 200%, dan TalkBack tanpa pengumuman setiap digit ditangani;
- profile benchmark pada data representatif terasa responsif di HP referensi.

### Backup dan restore

- round-trip JSON/enkripsi payload v2 menjaga header, posisi, kategori, nominal, dan split;
- fixture payload v1 permanen dinormalisasi menjadi satu allocation tanpa mengubah saldo;
- payload v2 dengan allocation kosong/lebih dari 50 pada kind 0/1, allocation pada kind 2/3, posisi gap/duplikat, category duplikat, jenis kategori salah, mismatch total, batas record, atau struktur asing ditolak sebelum mutasi;
- estimator byte menghitung allocation; batas plaintext/container tetap ditegakkan;
- restore v1 dan v2 menjaga ID serta sequence, lalu insert baru tidak bertabrakan;
- kegagalan restore setelah sebagian header/allocation ditulis me-rollback seluruh database;
- safety backup v2 dibuat dan diverifikasi sebelum restore v1/v2;
- guard cakupan gagal bila schema, tabel, atau kolom berubah tanpa evolusi adapter.

## Di luar ruang lingkup v1

- rekening, tanggal, atau catatan berbeda untuk tiap alokasi;
- alokasi pada transfer atau penyesuaian saldo;
- biaya transfer sebagai allocation dalam header transfer yang sama;
- lebih dari 50 alokasi dalam satu transaksi;
- nominal pecahan, multi-mata-uang, pajak, diskon, atau tip sebagai field khusus;
- memo, lampiran, tag, atau status rekonsiliasi per allocation;
- drag-and-drop untuk mengurutkan allocation;
- OCR/pemindaian struk dan pemecahan otomatis;
- akuntansi double-entry, jurnal debit/kredit umum, atau pembukuan bisnis;
- audit log nilai lama, undo, dan soft delete transaksi.

## Urutan implementasi dan commit

1. `docs(ledger): define transaction allocation model`
2. `feat(ledger): normalize allocations and evolve backup v2`
3. `feat(ledger): add split transaction form and presentation`
4. `docs: document implemented allocation workflow`
5. revisi dan implementasikan Anggaran v1 di atas schema v5/payload v3.

Schema v4, migrasi, repository, payload v2, decoder v1, restore, guard cakupan, dan test fondasi harus berada dalam satu commit fitur yang utuh. Jangan pernah meninggalkan commit yang dapat menulis allocation tetapi membuat backup tanpa membawanya.

## Kriteria selesai

Alokasi Transaksi v1 selesai ketika pengguna dapat mencatat dan mengedit satu pembayaran sebagai satu sampai 50 pasangan nominal–subkategori; total selalu diturunkan tanpa input ganda; riwayat, detail, kalender, saldo, dan ringkasan tetap menghitung satu header secara benar; migrasi schema lama serta backup v1 aman; payload v2 menjaga seluruh split; restore atomik; dan alur utama nyaman pada HP referensi.
