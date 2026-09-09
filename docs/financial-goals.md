# Tujuan Keuangan Waras Arta

## Status dan tujuan

Dokumen ini adalah kontrak rancangan **Tujuan Keuangan v1** untuk versi produk 0.2. Implementasi belum dimulai. Schema database aktif tetap v6 dan payload backup aktif tetap v4 sampai seluruh domain, persistence, UI, migrasi, backup, serta pengujiannya selesai sebagai satu perubahan yang konsisten. Implementasi fitur ini direncanakan menaikkan schema menjadi v7 dan payload backup menjadi v5; versi container enkripsi tetap v1.

Tujuan keuangan digunakan untuk dana darurat, tabungan perangkat, liburan, atau kebutuhan lain yang mempunyai sasaran nominal. Tujuan adalah **maksud penggunaan uang**, bukan tempat uang disimpan. Uang nyata tetap hanya berada pada rekening, sedangkan tujuan menandai sebagian saldo rekening tersebut secara virtual.

Tujuan versi pertama:

- membuat target rupiah dengan tanggal target opsional;
- mengalokasikan dana dari satu atau beberapa rekening nyata tanpa menggandakan saldo;
- mendukung beberapa tujuan yang memakai rekening sama selama saldo yang belum dialokasikan masih cukup;
- memperlihatkan progres, sisa target, surplus, tenggat, dan kekurangan saldo sumber secara jujur;
- mempertahankan aturan bahwa transaksi, transfer, anggaran, dan saldo tidak berubah karena alokasi tujuan;
- membawa seluruh definisi serta alokasi tujuan dalam backup terenkripsi berikutnya.

## Keputusan inti v1

1. Tujuan memakai **alokasi keadaan saat ini** per pasangan tujuan–rekening, bukan ledger kontribusi.
2. Alokasi hanya merupakan penandaan dana. Membuat, mengubah, memindahkan, atau melepaskannya tidak membuat transaksi dan tidak mengubah saldo.
3. Saat alokasi dinaikkan atau dipindahkan masuk, saldo yang belum dialokasikan pada rekening wajib cukup agar rupiah yang sama tidak dialokasikan ke beberapa tujuan.
4. Pengeluaran, transfer, pemasukan, penyesuaian, serta edit/hapus transaksi berikutnya tetap boleh berjalan. Jika saldo kemudian lebih kecil daripada total alokasi tujuan, aplikasi menampilkan **Saldo sumber kurang** dan tidak mengurangi tujuan mana pun secara otomatis.
5. Satu tujuan boleh memakai banyak rekening dan satu rekening boleh mendukung banyak tujuan.
6. Transfer antar-rekening tidak otomatis memindahkan alokasi tujuan. Lokasi uang dan maksud penggunaan tetap dua tindakan yang berbeda.
7. Alokasi boleh melebihi target selama saldo rekening mencukupi. UI menampilkan surplus dan persentase aktual di atas 100%.
8. Tujuan boleh dibuat tanpa alokasi awal. Tidak ada periode overlap atau konflik tanggal seperti pada Anggaran.
9. V1 tidak menyimpan histori kontribusi, status selesai permanen, atau arsip tujuan. Tujuan yang sudah tidak dipakai hanya dapat dihapus setelah seluruh alokasinya dilepaskan.

Keputusan current-state pada poin pertama berarti `updatedAt` tidak boleh diperlakukan sebagai histori menabung. Grafik perubahan progres dari waktu ke waktu memerlukan funding-event ledger pada versi mendatang dan tidak dapat direkonstruksi dari data v1.

## Istilah

- **Target** (`targetAmount`) adalah sasaran nominal tujuan dalam rupiah bulat.
- **Tanggal target** (`deadlineDay`) adalah tanggal sipil opsional `YYYYMMDD`. Ini bukan tanggal pemindahan uang dan bukan batas yang memblokir perubahan.
- **Alokasi tujuan** adalah nominal saat ini yang ditandai dari satu rekening untuk satu tujuan.
- **Dana teralokasi** (`fundedAmount`) adalah jumlah seluruh alokasi suatu tujuan.
- **Sisa target** adalah `max(targetAmount - fundedAmount, 0)`.
- **Surplus** adalah `max(fundedAmount - targetAmount, 0)`.
- **Dialokasikan dari rekening** adalah jumlah seluruh tujuan yang memakai rekening tersebut.
- **Tersedia untuk dialokasikan** (`freeAmount`) adalah bagian saldo positif rekening yang belum dialokasikan ke tujuan mana pun.
- **Saldo sumber kurang** (`coverageDeficit`) terjadi ketika total alokasi tujuan pada rekening lebih besar daripada saldo positif rekening saat ini.

Istilah UI yang dipakai adalah **Alokasikan dana**, **Lepaskan alokasi**, **Pindahkan alokasi**, **Dana teralokasi**, **Tersedia untuk dialokasikan**, dan **Belum dialokasikan ke tujuan**. Hindari **rekening tujuan**, **saldo tujuan**, **setor**, **tarik dana**, **top up**, atau label pendek **Dana bebas** karena dapat disalahartikan sebagai uang yang pasti aman untuk dibelanjakan.

## Model mental dan contoh

Misalnya rekening BNI mempunyai saldo Rp10.000.000. Pengguna mengalokasikan Rp4.000.000 untuk Dana Darurat dan Rp2.000.000 untuk Laptop:

- saldo BNI tetap Rp10.000.000;
- total seluruh rekening tetap sama;
- Dana Darurat menunjukkan Rp4.000.000;
- Laptop menunjukkan Rp2.000.000;
- nominal BNI yang tersedia untuk dialokasikan ke tujuan baru adalah Rp4.000.000.

Jika Rp4.000.000 benar-benar dipindahkan dari BNI ke rekening Tabungan, pengguna melakukan dua tindakan yang berbeda:

1. mencatat **Transfer** BNI → Tabungan agar saldo nyata benar;
2. memakai **Pindahkan alokasi** pada Dana Darurat agar penanda virtual berpindah dari BNI ke Tabungan.

Aplikasi tidak menggabungkan kedua tindakan secara otomatis karena satu transfer dapat berisi saldo yang belum dialokasikan, beberapa tujuan, atau hanya sebagian dari sebuah tujuan.

Jika saldo BNI turun menjadi Rp5.000.000 tanpa alokasi diubah, total alokasinya tetap Rp6.000.000 dan muncul **Saldo sumber kurang Rp1.000.000**. Progres kedua tujuan tidak dikurangi secara acak karena tidak ada aturan yang jujur untuk menentukan tujuan mana yang kehilangan dukungan lebih dahulu.

## Aturan produk

### Identitas tujuan

1. Nama wajib 1–80 karakter setelah di-trim dan setiap rangkaian whitespace diringkas menjadi satu spasi.
2. `normalizedName` adalah nama canonical dalam lowercase dan wajib unik tanpa membedakan huruf besar/kecil.
3. Target wajib berupa integer rupiah dari `1` sampai `maxAmount` yang dipakai ledger saat ini.
4. Tanggal target boleh kosong atau berupa tanggal Gregorian valid dari `20000101` sampai `99991231`.
5. Tanggal lampau diperbolehkan agar pengguna dapat mencatat tujuan yang sudah terlambat. Tanggal tidak memblokir alokasi.
6. Ikon memakai semantic string key dari katalog Material terbatas seperti kategori. File gambar dan warna khusus ditunda.
7. Catatan opsional maksimal 500 karakter.
8. Nama, target, tanggal target, ikon, dan catatan dapat diedit. Mengubah target tidak mengubah alokasi.
9. Menurunkan target di bawah dana teralokasi diperbolehkan dan menghasilkan status surplus. Tidak ada pelepasan otomatis.
10. `createdAt` adalah waktu tujuan dibuat. `updatedAt` adalah aktivitas terakhir dan ikut diperbarui ketika definisi atau alokasinya berubah; timestamp ini bukan histori kontribusi. Semua row yang disentuh satu operasi memakai timestamp UTC yang sama, dihitung monoton sebagai nilai terbesar dari `nowUtc`, `createdAt`, serta timestamp tujuan/alokasi terkait agar jam perangkat yang mundur tidak merusak urutan. Mutasi yang tidak mengubah nilai apa pun adalah no-op dan tidak memperbarui timestamp.

### Alokasi dan kapasitas rekening

Untuk setiap rekening:

```text
reservableBalance = max(accountLedgerBalance, 0)
allocatedAmount   = SUM(goalAllocation.amount untuk rekening)
freeAmount        = max(reservableBalance - allocatedAmount, 0)
coverageDeficit   = max(allocatedAmount - reservableBalance, 0)
```

Aturan mutasi:

1. Alokasi disimpan sebagai nilai akhir per pasangan tujuan–rekening, bukan nilai tambah/kurang sementara.
2. Nilai akhir `0` menghapus row alokasi; database tidak menyimpan row bernominal nol atau negatif.
3. Menaikkan alokasi sebesar `delta` hanya boleh ketika `delta <= freeAmount` yang dihitung ulang di dalam transaksi database.
4. Menurunkan alokasi selalu boleh sampai nol, termasuk ketika saldo rekening sumber sedang kurang.
5. Rekening aktif pada kelompok **Saldo utama** maupun **Simpanan & investasi** boleh dipilih. Kelompok rekening tidak mengubah rumus.
6. Rekening arsip tidak dapat menerima alokasi baru atau kenaikan alokasi.
7. Rekening tidak dapat diarsipkan selama masih mempunyai alokasi tujuan positif. Pengguna harus melepaskan atau memindahkan alokasinya lebih dahulu.
8. Hapus permanen rekening tetap dibatasi oleh riwayat ledger dan juga ditolak selama row alokasi tujuan masih mereferensikannya.
9. Mengubah nama, jenis, atau `balanceGroup` rekening tidak mengubah alokasi karena relasi menggunakan ID.
10. Seluruh penjumlahan memakai integer dengan pemeriksaan overflow. `double` hanya dipakai untuk rasio tampilan setelah status ditentukan.
11. `fundedAmount` satu tujuan dan `allocatedAmount` satu rekening masing-masing tidak boleh melebihi `maxAmount`, termasuk setelah perpindahan. Surplus target tetap diperbolehkan selama batas global ini dipenuhi.

Validasi kapasitas hanya berlaku pada mutasi alokasi positif. Saldo sumber kurang yang muncul karena saldo nyata kemudian berubah adalah keadaan sah yang perlu diperbaiki pengguna, bukan korupsi data.

Integrasi rekening menambah jumlah referensi tujuan pada `AccountDetails`. `canDelete` hanya benar ketika referensi ledger **dan** allocation tujuan sama-sama nol. `setAccountArchived()` serta `deleteAccount()` mengulang pemeriksaan di repository dan mengembalikan pesan domain yang ramah; UI tidak boleh menawarkan aksi berdasarkan ledger saja atau membocorkan error foreign key mentah.

### Operasi alokasi

V1 menyediakan tiga operasi:

- **Atur alokasi:** membuat, menaikkan, menurunkan, atau mengosongkan nilai tujuan pada satu rekening;
- **Lepaskan alokasi:** pintasan untuk menurunkan nilai, tanpa menarik atau memindahkan uang;
- **Pindahkan alokasi:** atomik mengurangi alokasi pada rekening asal dan menambahkannya pada rekening baru untuk tujuan yang sama. Tindakan ini tidak memindahkan saldo.

Pindahkan alokasi wajib memenuhi:

- kedua rekening ada, aktif, dan berbeda;
- nominal positif dan tidak melebihi alokasi tujuan pada rekening asal;
- rekening baru mempunyai nominal **Tersedia untuk dialokasikan** yang cukup;
- pengurangan dan penambahan terjadi dalam satu transaksi database;
- total progres tujuan tidak berubah.

Pemindahan alokasi antar-dua tujuan pada rekening yang sama ditunda dari UI v1. Jika kelak ditambahkan, repository harus menyediakan operasi atomik; UI tidak boleh menirunya melalui dua penyimpanan terpisah yang dapat gagal di tengah jalan.

### Hubungan dengan ledger, anggaran, dan saldo

- Alokasi tujuan tidak menambah atau mengurangi saldo rekening.
- Alokasi tidak dihitung sebagai pemasukan, pengeluaran, transfer, penyesuaian, atau pemakaian anggaran.
- Pemasukan tidak otomatis dialokasikan ke tujuan.
- Transfer tidak otomatis membuat, melepaskan, atau memindahkan alokasi.
- Pengeluaran untuk memakai dana tujuan tetap dicatat sebagai pengeluaran biasa. Pengguna melepaskan alokasi secara terpisah.
- Edit atau hapus transaksi tidak menulis ulang alokasi tujuan.
- Ledger tidak pernah diblokir hanya karena transaksi baru akan membuat saldo sumber tujuan menjadi kurang.
- Saldo, subtotal **Saldo utama**, subtotal **Simpanan & investasi**, dan total seluruh rekening tetap menunjukkan uang nyata tanpa dikurangi alokasi virtual.

Detail rekening dapat menampilkan **Dialokasikan ke tujuan** dan **Belum dialokasikan ke tujuan** sebagai informasi turunan. Teks bantuan harus menyatakan bahwa alokasi tidak mengunci uang dan tidak mengubah saldo.

### Progres, tenggat, dan dukungan saldo

Progres dihitung saat query dan tidak disimpan pada tabel tujuan:

```text
fundedAmount = SUM(goalAllocation.amount untuk tujuan)
actualRatio  = fundedAmount / targetAmount
visualRatio  = clamp(actualRatio, 0, 1)
```

Status progres dipisahkan dari status tenggat:

- `empty`: dana teralokasi `0`;
- `inProgress`: dana teralokasi lebih dari `0` dan di bawah target;
- `reached`: dana teralokasi sama dengan target;
- `exceeded`: dana teralokasi melebihi target.

Status tenggat:

- `none`: tidak ada tanggal target;
- `upcoming`: hari ini sebelum tanggal target;
- `dueToday`: hari ini sama dengan tanggal target;
- `past`: hari ini melewati tanggal target, terlepas dari progres.

Label **Terlambat** adalah status gabungan `deadlineStatus == past && fundedAmount < targetAmount`. `referenceDay` berasal dari kalender lokal perangkat dan dihitung ulang ketika layar dibuka, aplikasi resume, hari lokal berganti, atau zona waktu berubah. Tujuan yang sudah mencapai/melewati target tidak disebut terlambat meskipun tanggalnya telah lewat; tanggalnya tetap berstatus `past` untuk sorting dan detail.

Status dukungan saldo merupakan sumbu ketiga. Bila salah satu rekening sumber mengalami `coverageDeficit`, semua tujuan yang memakai rekening itu mendapat peringatan **Dana sumber perlu disesuaikan**. Nominal progres tetap berdasarkan alokasi; aplikasi tidak melakukan prorata atau memilih prioritas tujuan secara diam-diam.

### Hapus dan penyelesaian tujuan

- Tujuan tidak otomatis selesai atau terhapus ketika mencapai 100%.
- V1 tidak menyimpan status selesai permanen maupun arsip tujuan; tab **Tercapai** berasal dari progres saat ini.
- Tujuan hanya dapat dihapus permanen ketika tidak mempunyai row alokasi.
- Pengguna harus melepaskan seluruh alokasi sebelum menghapus. Pelepasan tidak mengubah uang nyata.
- Hapus memerlukan konfirmasi dan hanya menghapus definisi tujuan. Rekening, saldo, transaksi, kategori, dan anggaran tidak pernah ikut dihapus.
- Jika dana dipakai untuk pembelian, alur yang disarankan adalah melepaskan alokasi, mencatat pengeluaran nyata, lalu menghapus tujuan jika tidak diperlukan lagi.

Ketika pengguna memilih hapus pada tujuan yang masih mempunyai alokasi, aplikasi tidak sekadar menampilkan error. Dialog menjelaskan bahwa pencapaian tidak disimpan sebagai histori, menyediakan aksi **Kembali**, dan menawarkan **Lepaskan semua alokasi**. Setelah pelepasan atomik berhasil, aplikasi meminta konfirmasi kedua sebelum menghapus definisi. Jika penghapusan dibatalkan, tujuan tetap ada pada 0% dan tidak ada saldo yang berubah.

Konsekuensi current-state harus dijelaskan: setelah alokasi dilepas, tujuan tidak lagi menunjukkan bahwa target pernah tercapai. Histori penyelesaian merupakan fitur versi berikutnya.

## Pengalaman pengguna v1

Tujuan Keuangan tidak menambah tujuan keenam pada bottom navigation. Lima tujuan utama tetap **Ikhtisar**, **Riwayat**, **Kalender**, **Anggaran**, dan **Rekening**.

Pintu masuk:

- kartu **Tujuan keuangan** pada Ikhtisar;
- item **Kelola tujuan keuangan** pada menu aplikasi;
- rute khusus daftar, form, detail, dan pengaturan alokasi.

Jika pemakaian nyata menunjukkan Anggaran dan Tujuan sama-sama memerlukan akses satu ketukan, opsi yang dievaluasi adalah mengganti tab Anggaran dengan hub **Rencana** berisi keduanya, bukan menambah destination keenam. Perubahan tersebut bukan bagian dari implementasi Tujuan v1 dan harus diuji sebelum kontrak navigasi diubah.

Rute yang direncanakan adalah `/goals`, `/goals/new`, `/goals/:goalId`, `/goals/:goalId/edit`, serta `/goals/:goalId/allocations/:accountId`. Pemindahan alokasi dapat memakai bottom sheet dari detail dan tidak memerlukan rute publik tambahan.

### Daftar tujuan

Daftar mempunyai filter **Semua**, **Berjalan**, dan **Tercapai**. Berjalan berarti `fundedAmount < targetAmount`; Tercapai berarti `fundedAmount >= targetAmount`. Filter default adalah **Berjalan**. Empty state menyediakan aksi eksplisit **Lihat tujuan berjalan**, **Lihat tujuan tercapai**, atau **Lihat semua**, sesuai filter saat itu.

Urutan Berjalan:

1. tujuan dengan status **Saldo sumber kurang**;
2. tujuan terlambat;
3. tanggal target terdekat, dengan tanpa tanggal di bagian akhir;
4. `normalizedName`, lalu ID.

Urutan Tercapai menempatkan saldo sumber kurang lebih dahulu, lalu `updatedAt` aktivitas terakhir menurun, `normalizedName`, dan ID. Semua urutan wajib deterministik.

Setiap kartu cukup menampilkan nama, ikon, status teks, dana teralokasi/target, progress bar, sisa atau surplus, tanggal target, jumlah rekening sumber, dan peringatan dukungan bila ada. Warna tidak boleh menjadi satu-satunya pembeda.

### Buat dan edit tujuan

Form memuat:

- nama tujuan;
- target dana;
- tanggal target opsional;
- ikon;
- catatan opsional.

Teks bantuan wajib terlihat: **Tujuan hanya menandai sebagian saldo rekening. Saldo dan arus kas tidak berubah.** Tujuan boleh disimpan pada 0%, kemudian pengguna diarahkan ke detail untuk mengatur sumber dana. Keluar dari form kotor meminta konfirmasi.

### Detail dan pengaturan alokasi

Detail menampilkan:

- dana teralokasi, target, persentase, sisa atau surplus;
- tanggal target dan status tenggat;
- daftar rekening sumber beserta kelompok, saldo nyata, serta nominal alokasi;
- peringatan **Saldo sumber kurang** bila total alokasi rekening tidak lagi tertutup;
- **Atur alokasi** sebagai aksi utama;
- **Pindahkan alokasi** sebagai aksi sekunder, dengan field **Rekening asal** dan **Rekening baru** serta penjelasan bahwa saldo tidak berpindah;
- **Lepaskan alokasi** pada setiap baris rekening, **Edit tujuan** pada AppBar/menu, dan **Hapus tujuan** pada zona berbahaya.

Pengaturan satu rekening menampilkan **Saldo rekening**, **Dialokasikan ke tujuan lain**, **Tersedia untuk dialokasikan**, dan **Alokasi untuk tujuan ini**. Input adalah nilai akhir. Repository menghitung ulang kapasitas saat simpan; jika saldo/alokasi berubah sejak form dibuka, tampilkan: **Saldo yang tersedia untuk dialokasikan telah berubah. Periksa nominal lalu coba lagi.**

### Ikhtisar dan rekening

Kartu Ikhtisar menampilkan maksimal dua tujuan prioritas dengan urutan yang sama seperti daftar Berjalan. Pada lebar 320 px atau text scale 200%, tampilkan maksimal satu tujuan dalam baris ringkas agar Ringkasan bulanan tidak terdorong terlalu jauh. Bila tidak ada yang berjalan tetapi ada yang tercapai, tampilkan ringkasan pencapaian. Bila belum ada tujuan, tampilkan penjelasan singkat dan aksi **Buat tujuan**.

Saldo utama tidak diganti dengan angka hasil pengurangan alokasi. Pada detail rekening, gunakan label **Dialokasikan ke tujuan** dan **Belum dialokasikan ke tujuan** sebagai rincian tambahan agar nominal ledger tetap menjadi sumber kebenaran.

### State dan aksesibilitas

- Loading tidak menampilkan angka nol palsu.
- Error menyatakan data tidak berubah dan menyediakan **Coba lagi**.
- Rute ID tidak valid menampilkan **Tujuan tidak ditemukan atau sudah dihapus**.
- Tidak ada rekening aktif mengarahkan ke **Tambah rekening**.
- Tidak ada saldo yang tersedia untuk dialokasikan tetap mengizinkan pembuatan tujuan, tetapi pengaturan alokasi menjelaskan mengapa nominal belum dapat dinaikkan.
- Pada lebar 320 px atau text scale 200%, nama, status, tanggal, dan nominal disusun vertikal bila perlu.
- Filter memakai `Wrap` atau susunan vertikal pada teks besar; kelompok aksi tidak dipaksa berada dalam satu baris.
- Nominal panjang memakai scale-down visual dengan semantic label lengkap, bukan dipotong.
- Setiap kartu tujuan dibaca sebagai satu node yang menyebut nama, nominal, persentase, tenggat, dan peringatan dukungan.
- Seluruh tombol ikon memiliki tooltip/label semantik dan target sentuh minimal 48 dp.
- Progress dan error tidak dibedakan hanya melalui warna atau ikon.

## Rancangan domain dan repository

Domain direncanakan pada `lib/domain/financial_goal.dart` serta `lib/domain/financial_goal_repository.dart` dan tidak mengimpor Flutter, Drift, atau `BuildContext`.

Model minimal:

- `FinancialGoal`;
- `GoalAllocation`;
- `FinancialGoalDetails` dengan alokasi per rekening;
- `FinancialGoalProgress` dengan nilai turunan;
- `GoalProgressStatus`, `GoalDeadlineStatus`, dan ringkasan coverage rekening;
- draft create/update/set allocation/move allocation;
- filter serta snapshot daftar yang immutable.

Kontrak repository minimal:

- watch/load daftar dan detail tujuan;
- membuat serta mengubah tujuan;
- mengatur nilai akhir alokasi satu rekening;
- memindahkan alokasi antar-rekening secara atomik;
- menghapus tujuan kosong;
- watch ringkasan alokasi per rekening untuk integrasi layar Rekening;
- memuat data dengan urutan deterministik dan jumlah query tetap.

ViewModel mengelola filter, input, status simpan, retry, serta invalidasi setelah restore. Repository mengulang seluruh validasi identitas, kapasitas, relasi, dan atomicity; UI tidak menjadi batas keamanan data.

## Rencana schema Drift v7

Schema v7 menambah dua tabel tanpa menulis ulang rekening, kategori, ledger, allocation transaksi, atau anggaran.

### `financial_goals`

- `id INTEGER PRIMARY KEY AUTOINCREMENT`;
- `name TEXT NOT NULL`;
- `normalized_name TEXT NOT NULL UNIQUE`;
- `target_amount INTEGER NOT NULL`;
- `deadline_day INTEGER NULL`;
- `icon_key TEXT NOT NULL`;
- `note TEXT NOT NULL DEFAULT ''`;
- `created_at INTEGER NOT NULL`;
- `updated_at INTEGER NOT NULL`.

Constraint memeriksa nama canonical, target `1..maxAmount`, tanggal Gregorian nullable, panjang ikon `1..40`, catatan maksimal 500, serta `updated_at >= created_at`.

### `goal_allocations`

- `goal_id INTEGER NOT NULL REFERENCES financial_goals(id) ON DELETE RESTRICT`;
- `account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT`;
- `amount INTEGER NOT NULL`;
- `updated_at INTEGER NOT NULL`;
- primary key `(goal_id, account_id)`;
- `CHECK (amount BETWEEN 1 AND maxAmount)`.

Tidak ada ID atau sequence terpisah untuk mapping. Row nol dihapus. Indeks tambahan diperlukan pada `(account_id, goal_id)` agar kapasitas rekening, detail rekening, serta guard arsip/hapus tidak melakukan table scan.

Setiap create/update/delete mapping dan pemindahan alokasi juga memperbarui `financial_goals.updated_at` dalam transaksi yang sama. Pada move, row asal, row tujuan, dan goal memakai timestamp monoton yang sama; setiap allocation yang tersimpan wajib mempunyai `updatedAt <= goal.updatedAt`. Ini menyediakan urutan aktivitas terakhir tanpa mengklaim sebagai timeline perubahan nominal.

Trigger/guard schema v7:

- menolak insert/update alokasi ke rekening arsip;
- menolak perubahan rekening menjadi arsip ketika masih mempunyai alokasi;
- foreign key `RESTRICT` mencegah hapus tujuan/rekening yang masih direferensikan;
- tidak memblokir mutasi ledger yang kemudian membuat saldo sumber kurang;
- tidak memaksakan `SUM(allocation) <= balance` sebagai invariant permanen karena state under-backed memang sah setelah saldo berubah.

Validasi kapasitas `freeAmount` dijalankan repository di dalam transaksi tulis. Restore memvalidasi struktur dan relasi, tetapi menerima rekening aktif yang under-backed agar backup sah dari keadaan aplikasi sebelumnya tetap dapat dipulihkan.

`AppDatabase` menyediakan verifier integritas tujuan untuk dipanggil adapter backup setelah restore. Verifier memeriksa foreign key, pasangan unik, nominal/agregat, nama canonical, timestamp, rekening arsip, dan high-water mark; pemeriksaan ini bukan tanggung jawab ViewModel atau kontrak repository UI.

Migrasi dan schema verifier wajib menguji fresh-create v7 serta jalur v1→v7 sampai v6→v7. Snapshot `drift_schema_v7.json`, generated schema test, indeks, trigger, foreign key, identity, dan seluruh data lama harus diverifikasi.

## Query dan performa

Daftar/progres harus memakai agregasi set-based, bukan satu query per tujuan. Satu snapshot memuat tujuan, allocation totals, jumlah sumber, deadline, dan flag coverage dengan jumlah query tetap. Detail boleh memakai query khusus berdasarkan ID.

Target tetap HP Snapdragon 460/RAM 4 GB. Batas awal backup dan validasi:

- maksimal 10.000 tujuan;
- maksimal 1.000 rekening sumber per tujuan;
- maksimal 100.000 row alokasi tujuan di seluruh payload;
- batas plaintext 10 MiB tetap membatasi materialisasi awal oleh `jsonDecode`; setelah decode, panjang array dan jumlah mapping kumulatif diperiksa sebelum DTO/domain tambahan dibangun;
- validasi relasi/agregat ditargetkan `O(N log N)` atau lebih baik, bukan pairwise `O(N²)`.

## Rencana backup payload v5

Schema v7 dan payload v5 wajib masuk dalam perubahan yang sama. Container `.warasarta` tetap versi 1 dengan Argon2id serta XChaCha20-Poly1305 yang sudah aktif.

Payload v5 menambahkan `data.financialGoals`. Setiap record membawa `id`, `name`, `normalizedName`, `targetAmount`, `deadlineDay`, `iconKey`, `note`, `createdAtUtc`, `updatedAtUtc`, dan `allocations[]`. Setiap allocation membawa `accountId`, `amount`, serta `updatedAtUtc`, diurutkan menurut `accountId`.

`sequences.financialGoals` ditambahkan pada wire. Mapping tidak mempunyai sequence. `BackupSummary.financialGoalCount` merupakan nilai preview yang diturunkan dari `data.financialGoals`, bukan key JSON redundan. Exporter selalu menghasilkan urutan deterministik menurut ID.

Kompatibilitas:

| Payload | Schema | Tujuan keuangan | Status setelah v5 aktif |
| --- | --- | --- | --- |
| v1 | 3 | Tidak ada | Legacy, dipulihkan dengan tujuan kosong |
| v2 | 4 | Tidak ada | Legacy, dipulihkan dengan tujuan kosong |
| v3 | 5 | Tidak ada | Legacy, dipulihkan dengan tujuan kosong |
| v4 | 6 | Tidak ada | Legacy, anggaran dipertahankan dan tujuan kosong |
| v5 | 7 | Definisi serta allocation current-state | Format aktif mendatang |

Parser v1–v4 tetap exact-key: field `financialGoals` maupun sequence tujuan ditolak sebagai field asing dan hasil normalisasinya selalu `financialGoals = []` serta sequence `0`. Parser v5 mewajibkan kedua field baru dan hanya menerima pasangan `(payload v5, schema 7)`; schema 7 selalu mengekspor payload v5. Setiap daftar allocation wajib strictly ascending menurut `accountId` dan unik.

Validasi v5 juga menolak ID tujuan duplikat, `normalizedName` duplikat/tidak canonical, `iconKey` di luar katalog yang dikenal, target/tanggal/catatan invalid, timestamp goal/allocation invalid atau melanggar relasi, serta sequence yang lebih rendah daripada ID maksimum maupun melewati batas headroom SQLite/aplikasi. Semua parser versi lama tetap menjalankan invariant formatnya sendiri sebelum normalisasi.

Preview restore legacy memberi peringatan eksplisit bahwa tujuan keuangan akan kosong setelah replace-all. Safety backup aplikasi schema 7 selalu berupa payload v5 sebelum restore v1, v2, v3, v4, maupun v5. Estimator ukuran, batas record, validasi exact-key, restore atomik, count verification, high-water mark, dan invalidasi provider semuanya wajib mencakup tujuan.

Urutan restore penuh:

1. validasi seluruh payload sebelum mutasi;
2. di dalam satu transaksi, jadikan rekening existing nonarsip sementara agar guard ledger mengizinkan pembersihan;
3. hapus `goal_allocations` lalu `financial_goals`;
4. hapus `ledger_allocations` lalu `ledger_entries`, `budget_categories` lalu `budgets`, kategori anak lalu induk, kemudian rekening;
5. insert rekening sebagai nonarsip, kategori induk/anak, anggaran/mapping, ledger/allocation, tujuan, lalu allocation tujuan;
6. pulihkan status arsip rekening dan seluruh sequence;
7. jalankan count check, foreign-key check, verifier database, dan commit hanya bila semuanya lulus.

Kegagalan apa pun me-rollback seluruh replace-all. Failpoint test wajib tersedia setelah penghapusan goal, insert definisi goal, insert allocation goal, pemulihan sequence, dan verifier akhir. `coverageDeficit` pada rekening aktif diterima; orphan, nominal nol/negatif, pasangan duplikat, rekening arsip, ID invalid, nama tidak canonical, sequence invalid, aggregate di atas `maxAmount`, atau overflow ditolak sebelum mutasi.

## Error, konkurensi, dan konsistensi

- UI menampilkan loading, error, dan retry untuk daftar tujuan, detail, rekening sumber, serta perhitungan kapasitas.
- Tombol simpan dinonaktifkan selama operasi berjalan dan ketukan ganda tidak membuat mutasi ganda.
- Repository membaca saldo dan seluruh allocation rekening lagi di dalam transaksi yang sama dengan penulisan.
- Jika dua form memakai kapasitas rekening yang sama, hanya transaksi pertama yang masih memenuhi batas; transaksi kedua gagal dengan pesan yang dapat dipulihkan.
- Pindahkan alokasi, set allocation, create/update/delete, serta restore wajib memiliki uji injected failure dan rollback.
- Setelah restore, provider rekening, ledger, anggaran, tujuan, ikhtisar, serta backup preview yang relevan diinvalidasi.

## Matriks pengujian minimum

### Domain

- canonical name, batas target/catatan/ikon, dan tanggal Gregorian termasuk leap year;
- progres 0, di bawah, sama dengan, serta di atas target;
- deadline kosong, mendatang, hari ini, dan terlambat;
- kombinasi tanggal `past` dengan progres `reached`/`exceeded`, lalu pelepasan hingga kembali di bawah target menghasilkan **Terlambat**;
- rasio visual dijepit tanpa kehilangan nominal surplus;
- koleksi immutable dan filter equality.

### Repository dan database

- create/update/delete tujuan kosong;
- alokasi satu/multi-rekening dan beberapa tujuan pada rekening sama;
- kapasitas mencegah double allocation dan dihitung ulang dalam transaksi;
- set nilai akhir hanya memeriksa delta: pada saldo 100 dengan alokasi tujuan ini 30 dan tujuan lain 50, nilai akhir 50 berhasil sedangkan 51 ditolak;
- penurunan/set nol tetap berhasil ketika rekening under-backed;
- saldo nol/negatif memberi `freeAmount = 0`, pelepasan tetap boleh, dan pemasukan berikutnya dapat menutup deficit tanpa mengubah allocation;
- pindahkan alokasi melakukan merge bila rekening baru sudah mempunyai row untuk goal yang sama dan rollback utuh bila gagal setelah source dikurangi/dihapus;
- transaksi/transfer/penyesuaian mengubah saldo tanpa mengubah allocation, lalu menghasilkan/menyelesaikan coverage warning;
- perubahan target mengubah status tanpa memodifikasi allocation;
- rekening dengan allocation tidak dapat diarsipkan/dihapus;
- raw SQL menolak insert/update allocation ke rekening arsip serta menolak pengarsipan rekening yang masih dialokasikan;
- nama/kelompok rekening berubah tanpa memutus referensi;
- query count tetap dan urutan daftar deterministik;
- fresh schema v7 dan setiap jalur v1→v7, v2→v7, v3→v7, v4→v7, v5→v7, serta v6→v7 memverifikasi snapshot, indeks, trigger, dan foreign key; seluruh ledger/allocation, `balanceGroup`, anggaran/mapping/sequence lama dipertahankan dan goals dimulai kosong.

### Backup

- payload v5 round-trip dengan tujuan kosong, multi-rekening, surplus, tanggal nullable, dan state under-backed;
- v1–v4 menghasilkan tujuan kosong tanpa kehilangan data format masing-masing;
- strict parser menolak key asing, duplicate pair, orphan, rekening arsip, nominal invalid, aggregate overflow, timestamp/sequence invalid, serta batas record;
- restore replace-all, safety backup, provider invalidation, dan rollback mencakup tujuan;
- ukuran container/plaintext tetap dihormati.

### UI dan perangkat

- empty/loading/error/retry, ID route invalid, dan form kotor;
- create/edit/delete, tanggal target opsional/lampau, serta nominal target diturunkan di bawah allocation;
- tambah/ubah/lepas allocation, kapasitas stale, serta pindahkan alokasi;
- dua tujuan berebut saldo yang tersedia untuk dialokasikan;
- transfer tidak otomatis memindahkan allocation dan coverage warning terlihat;
- Berjalan/Tercapai, deadline, surplus, source count, serta ranking Ikhtisar;
- semantics lengkap, target sentuh 48 dp, lebar 320 px, text scale 200%, keyboard terbuka, dan nominal maksimum;
- smoke test backup/restore pada HP referensi.

## Di luar ruang lingkup v1

- rekening virtual atau penggandaan saldo;
- funding-event ledger dan histori kontribusi;
- status selesai permanen, arsip tujuan, serta riwayat tujuan yang pernah tercapai;
- grafik perubahan progres dari waktu ke waktu;
- kontribusi berulang, auto-allocation, pengingat, dan notifikasi;
- pemindahan allocation otomatis ketika transfer dibuat;
- pengaitan langsung antara pengeluaran dan tujuan;
- pemindahan allocation antar-tujuan dari UI;
- pace bulanan, rekomendasi nominal, prediksi tanggal selesai, bunga, dan harga investasi;
- tujuan bersama, multi-mata-uang, sinkronisasi bank, dan cloud sync;
- gambar unggahan pengguna.

## Urutan implementasi dan commit

1. `docs: specify financial goals v1`
2. `feat(goals): add persistence and backup v5`
3. `feat(goals): add financial goal planning UI`
4. `docs: document implemented financial goals workflow`

Schema v7, guard rekening, repository tujuan, payload v5, decoder legacy, restore, dan seluruh test fondasi berada dalam commit persistence yang sama agar tidak ada commit yang dapat menghasilkan backup parsial.

## Kriteria selesai

Tujuan Keuangan v1 selesai ketika pengguna dapat membuat dan mengubah target, mengalokasikan dana dari beberapa rekening tanpa double allocation, memindahkan atau melepaskan alokasi tanpa mengubah saldo/arus kas/anggaran, melihat progres/tenggat/surplus/coverage deficit secara benar, melindungi rekening yang masih direferensikan, menghapus tujuan kosong, serta melakukan backup–restore v1 sampai v5 sesuai kontrak. Migrasi lama, rollback, aksesibilitas, performa, dan alur utama pada HP referensi harus terverifikasi sebelum status dokumen diubah menjadi selesai.
