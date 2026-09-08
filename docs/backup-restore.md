# Backup dan Restore Waras Arta

## Status dan batas fitur

Waras Arta menyediakan backup rutin **manual** berbasis kata sandi. Setiap kali pengguna menekan **Buat backup**, aplikasi mengambil satu snapshot data saat itu, mengenkripsinya, lalu membuka pemilih dokumen Android untuk menentukan lokasi file `.warasarta`. Integrasi ini memakai adapter native Storage Access Framework (SAF), bukan package `file_picker`. Pengguna dapat memilih Downloads atau penyedia dokumen seperti Google Drive jika penyedia tersebut terpasang dan tersedia pada perangkat. Selain itu, aplikasi mewajibkan satu safety backup terenkripsi setelah pengguna mengonfirmasi restore dan sebelum replace-all dimulai.

Backup rutin ini bukan sinkronisasi dan tidak berjalan otomatis. Aplikasi belum menjadwalkan backup, mengunggah file sendiri, merotasi salinan lama, atau memastikan file masih dapat dibuka. Safety backup yang diwajibkan saat restore adalah pengecualian terbatas dan bukan pengganti backup rutin. Perubahan setelah sebuah file dibuat tidak ikut masuk ke file tersebut. Buat backup baru secara berkala dan simpan lebih dari satu salinan di lokasi berbeda.

## Alur pengguna

### Membuat backup

1. Buka **Backup & pulihkan data** dari menu aplikasi.
2. Pilih **Buat backup**.
3. Masukkan kata sandi minimal 12 karakter dan ulangi kata sandi yang sama.
4. Pilih lokasi melalui dialog **Simpan sebagai** Android.
5. Aplikasi menutup hasil penulisan, membuka kembali URI dokumen, lalu mencocokkan jumlah byte dan SHA-256 dengan data sumber. Konfirmasi berhasil hanya ditampilkan jika pemeriksaan ini lolos; pastikan file juga terlihat di lokasi pilihan.

Nama yang disarankan aplikasi berbentuk `waras-arta-backup-YYYYMMDD-HHmmss.warasarta`; safety backup memakai `waras-arta-sebelum-restore-YYYYMMDD-HHmmss.warasarta` agar tidak mudah tertukar dengan file sumber. Nama dan ekstensi hanya membantu pengguna mengenali file; keamanan berasal dari enkripsi, bukan dari ekstensi khusus.

Saat restore, aplikasi tidak mempercayai ekstensi atau MIME sebagai bukti bahwa dokumen adalah backup. Isi yang dipilih tetap harus lolos autentikasi container, pemeriksaan versi, dan validasi payload.

> **Kata sandi tidak disimpan oleh Waras Arta dan tidak dapat dipulihkan. Jika kata sandi dilupakan, backup tidak dapat direstore.** Gunakan frasa sandi yang kuat, unik, dan dapat disimpan secara aman oleh pengguna.

### Melakukan restore

1. Pilih **Pulihkan dari backup**, lalu pilih file `.warasarta`.
2. Masukkan kata sandi file tersebut.
3. Aplikasi mendekripsi dan memvalidasi format, versi, integritas, serta relasi data sebelum menawarkan perubahan database.
4. Periksa waktu pembuatan dan jumlah rekening, kategori, transaksi, serta anggaran pada ringkasan.
5. Konfirmasikan **Backup lalu pulihkan** hanya jika file dan ringkasannya benar.
6. Aplikasi mengekspor data aktif, mengenkripsinya memakai kata sandi restore yang sama, lalu membuka Save As untuk safety backup.
7. Jika Save As dibatalkan, penulisan gagal, atau hasil baca ulang tidak memiliki ukuran dan SHA-256 yang sama, restore dihentikan tanpa mengubah database.
8. Hanya setelah safety backup berhasil ditulis dan diverifikasi, aplikasi menjalankan replace-all dalam satu transaksi database.
9. Setelah transaksi restore berhasil, tampilan keuangan dimuat ulang dari data hasil backup.

Restore versi awal memakai strategi **replace-all**, bukan merge. Seluruh rekening, kategori, anggaran beserta mapping-nya, dan ledger aktif diganti oleh isi backup. Safety backup terenkripsi adalah prasyarat restore dan memakai kata sandi yang sama. Replace-all tidak pernah dimulai jika safety backup belum berhasil disimpan.

## Isi dan versi format

File `.warasarta` adalah container terenkripsi, bukan file SQLite dan bukan JSON polos. Setelah autentikasi serta dekripsi berhasil, payload logis versi 4 saat ini memuat:

- identitas format dan `backupVersion`;
- versi schema database sumber;
- waktu pembuatan dalam UTC;
- rekening, termasuk `balanceGroup` (`primary` atau `savingsInvestment`), status arsip, dan waktu pembuatannya;
- kelompok kategori dan subkategori, termasuk ikon, urutan, status arsip, serta identitas kategori bawaan;
- seluruh ledger pemasukan, pengeluaran, transfer, dan penyesuaian saldo;
- seluruh alokasi nominal–subkategori pada ledger pemasukan dan pengeluaran;
- seluruh anggaran bulanan, tahunan, atau kustom beserta batas, rentang, pilihan subkategori, dan timestamp-nya;
- ID asli dan high-water mark ID SQLite untuk rekening, kategori, ledger, serta anggaran agar identitas berikutnya tetap konsisten setelah restore.

Saldo, ringkasan, dan penanda kalender tidak disimpan sebagai salinan turunan. Nilai tersebut dihitung kembali dari ledger setelah restore.

`backupVersion` dan versi container enkripsi dipisahkan dari `databaseSchemaVersion`. Pemisahan ini memungkinkan format data, skema lokal, dan parameter keamanan berevolusi dengan jalur migrasi masing-masing. Versi aplikasi saat ini hanya menerima versi yang dikenal dan menolak versi yang lebih baru daripada yang didukung.

Payload versi 1 adalah format lama dari schema 3 dan belum berisi allocation terpisah. Payload v2/schema 4 menambahkan seluruh allocation, tetapi belum menyimpan kelompok saldo rekening. Payload v3/schema 5 mempertahankan allocation dan menambahkan `balanceGroup` pada setiap rekening. Versi aplikasi saat ini membuat payload v4/schema 6 yang juga membawa seluruh anggaran. Saat membaca payload v1 atau v2, decoder memetakan seluruh rekening ke `primary`; v3 mempertahankan kelompok rekening yang tersimpan. Payload legacy v1–v3 tidak mempunyai anggaran sehingga dinormalisasi menjadi `budgets = []` dengan sequence anggaran 0. Tujuan keuangan, gambar unggahan, dan utang/piutang belum tersedia sehingga belum masuk backup aktif.

Dukungan format saat ini dan evolusi berikutnya:

| Payload | Schema sumber | Isi kategorisasi dan rekening | Anggaran | Status |
| --- | --- | --- | --- | --- |
| v1 | 3 | Satu `categoryId` langsung pada ledger; tanpa `balanceGroup` | Tidak ada | Legacy, tetap dapat direstore |
| v2 | 4 | `allocations[]` pada ledger; tanpa `balanceGroup` | Tidak ada | Legacy, tetap dapat direstore |
| v3 | 5 | `allocations[]`; setiap rekening membawa `balanceGroup` | Tidak ada | Legacy, tetap dapat direstore |
| v4 | 6 | `allocations[]` dan `balanceGroup` | Seluruh `data.budgets` | Aktif |

Exporter schema 6 saat ini selalu menulis payload v4. Decoder schema 6 menerima v1, v2, v3, maupun v4: v1 dinormalisasi dari `categoryId + amount` menjadi satu allocation, transfer dan penyesuaian menjadi daftar allocation kosong, rekening v1/v2 mendapat `balanceGroup = primary`, dan v3 mempertahankan kelompok eksplisitnya. Restore v1/v2/v3 menginisialisasi anggaran kosong. Parser dan encoder terpisah per versi, field semantik asing ditolak, dan aplikasi lama menolak versi lebih baru daripada yang dipahami. Container enkripsi tetap v1 karena evolusi ini mengubah isi logis, bukan primitive kriptografi.

Kompatibilitas ini adalah persyaratan untuk setiap rilis format baru: file v1 harus tetap dapat dibaca oleh versi aplikasi yang lebih baru dengan bagian fitur baru diinisialisasi kosong/default, sedangkan aplikasi lama harus menolak versi baru dan tidak boleh diam-diam mengabaikan datanya. Parser v1 karena itu menolak field semantik yang tidak dikenal; penambahan data baru wajib disertai kenaikan `backupVersion`.

## Enkripsi dan integritas

Kata sandi dinormalisasi ke Unicode NFC lalu diproses sebagai UTF-8 dengan **Argon2id** menggunakan salt acak untuk menghasilkan kunci 256-bit. Normalisasi memastikan karakter beraksen yang tampak sama tidak menghasilkan kunci berbeda hanya karena komposisi code point dari keyboard berbeda. Decoder container v1 memakai allowlist yang cocok persis dengan profil produksi: Argon2 versi 19, normalisasi NFC, memori 19.456 KiB, 2 iterasi, paralelisme 1, dan panjang kunci 32 byte. Perbedaan apa pun ditolak; decoder tidak menerima rentang parameter yang longgar. Perubahan profil harus memakai versi container atau jalur migrasi baru.

Payload kemudian dienkripsi dan diautentikasi dengan **XChaCha20-Poly1305** menggunakan nonce acak. Header keamanan ikut diautentikasi sebagai additional authenticated data. Perubahan pada ciphertext, tag autentikasi, atau header menyebabkan file ditolak. Pesan untuk kata sandi salah dan file rusak sengaja tidak membedakan penyebab kriptografisnya.

Container tidak menyimpan kata sandi atau kunci hasil derivasi. Password dan buffer plaintext dibersihkan dari objek sementara sejauh yang dapat dilakukan oleh runtime, tetapi aplikasi tidak menjanjikan penghapusan forensik dari memori perangkat.

## Akses dokumen Android

Adapter Android native membuka tujuan simpan dengan `ACTION_CREATE_DOCUMENT` dan sumber restore dengan `ACTION_OPEN_DOCUMENT`. Saat memilih dokumen, ukuran dari metadata diperiksa bila tersedia, kemudian isi dibaca langsung dari URI penyedia sebagai stream berbatas 16 MiB. Pembacaan berhenti dan file ditolak ketika batas terlampaui; Waras Arta tidak lebih dahulu membuat salinan perantara di cache aplikasi.

Saat menyimpan, adapter menulis dan menutup stream, membuka kembali URI yang sama, lalu mencocokkan jumlah byte dan SHA-256 dengan container sumber. Operasi baru dilaporkan berhasil setelah verifikasi ini lolos. Pemeriksaan tersebut hanya membuktikan hasil penulisan yang langsung dapat dibaca saat itu; pemeriksaan tidak menjamin retensi penyedia cloud dan bukan verifikasi backup berkala.

## Konsistensi database

Versi saat ini mengekspor rekening beserta kelompok saldonya, kategori, anggaran beserta mapping-nya, ledger, allocation, dan seluruh sequence terkait dalam satu transaksi baca sehingga bagian-bagian snapshot berasal dari keadaan database yang konsisten.

Sebelum restore, payload diperiksa terhadap batas nominal, bentuk tanggal, keunikan ID/nama, hierarki kategori, foreign key, aturan jenis transaksi, kelompok saldo, dan saldo rekening arsip. Pada payload v2+, setiap pemasukan/pengeluaran wajib mempunyai allocation yang jumlahnya sama dengan total header; transfer/penyesuaian wajib tidak mempunyai allocation. Payload v3+ mewajibkan `balanceGroup` yang dikenal pada setiap rekening, sedangkan hasil normalisasi v1/v2 memakai `primary`. Payload v4 juga memvalidasi periode Gregorian/canonical, kategori leaf pengeluaran, mapping, batas, timestamp, dan overlap anggaran. Penggantian data kemudian dijalankan dalam satu transaksi Drift/SQLite dengan urutan relasi yang aman. ID asli dan sequence dipulihkan, hasilnya diperiksa kembali, dan commit hanya dilakukan jika seluruh langkah berhasil. Jika insert atau pemeriksaan akhir gagal, transaksi di-rollback sehingga data lama tetap ada.

Kontrak rinci evolusi tersebut berada pada [spesifikasi alokasi kategori transaksi](transaction-allocations.md) dan [spesifikasi Anggaran v1](budgets.md).

Atomic rollback melindungi konsistensi database ketika operasi gagal; mekanisme tersebut bukan pengganti salinan cadangan. Kerusakan perangkat, uninstall, atau penghapusan data aplikasi tetap dapat menghilangkan database aktif dan backup yang hanya disimpan pada HP yang sama.

## Batas keamanan

- File `.warasarta` yang berhasil dibuat dienkripsi, termasuk data keuangan di dalam payload.
- Database SQLite aktif di direktori privat aplikasi **belum dienkripsi khusus oleh Waras Arta**. Perlindungan file backup tidak mengenkripsi database kerja.
- Belum tersedia PIN atau biometrik aplikasi.
- Tidak ada server Waras Arta, akun wajib, sinkronisasi cloud, atau pemulihan kata sandi.
- Android Auto Backup dan ekstraksi device-to-device untuk data internal aplikasi dinonaktifkan/dikecualikan. Pindah perangkat harus memakai file `.warasarta` terenkripsi secara manual.
- Memilih Google Drive melalui pemilih dokumen berarti Android menyerahkan file terenkripsi kepada penyedia tersebut; Waras Arta tidak menjalankan sinkronisasi atau memeriksa retensi cloud.
- Batas ukuran container terenkripsi adalah 16 MiB dan batas plaintext hasil dekripsi adalah 10 MiB. Pemilihan membaca URI secara streaming dengan batas keras dan tanpa salinan cache perantara milik aplikasi, tetapi container hasil baca dan payload hasil dekripsi tetap dimuat ke memori. Pengujian dengan data besar pada HP kelas bawah tetap diperlukan.

## Checklist Android

Gunakan data percobaan dan salinan file, bukan satu-satunya catatan keuangan.

- [ ] Buat data yang mencakup rekening Saldo utama, rekening Simpanan & investasi, rekening arsip, kategori kustom/arsip, pemasukan, pengeluaran split, transfer lintas kelompok, penyesuaian positif/negatif, tanggal lampau, serta anggaran bulanan/tahunan/kustom multi-subkategori.
- [ ] Pastikan kata sandi kosong, kurang dari 12 karakter, dan konfirmasi yang berbeda ditolak sebelum dialog simpan dibuka.
- [ ] Simpan backup ke Downloads, pastikan status berhasil baru muncul setelah verifikasi hasil tulis, temukan file `.warasarta`, dan salin file itu ke lokasi kedua.
- [ ] Jika Google Drive tersedia sebagai penyedia dokumen, simpan salinan ke Drive dan pastikan file dapat dipilih kembali setelah dialog ditutup.
- [ ] Tambah satu transaksi setelah backup; pastikan transaksi baru itu tidak dianggap masuk ke snapshot lama.
- [ ] Pilih backup dan masukkan kata sandi salah. Data aktif tidak boleh berubah.
- [ ] Ubah beberapa byte pada salinan file atau gunakan file yang terpotong. Restore harus ditolak dan data aktif tidak boleh berubah.
- [ ] Masukkan kata sandi benar, periksa waktu serta jumlah rekening, kategori, transaksi, dan anggaran pada ringkasan, lalu pilih **Batal**. Data aktif tidak boleh berubah.
- [ ] Konfirmasi restore dan pastikan Save As untuk safety backup muncul sebelum database berubah.
- [ ] Batalkan Save As; restore harus ikut batal dan data aktif tidak boleh berubah.
- [ ] Ulangi restore, simpan safety backup, lalu pastikan replace-all baru berjalan setelah file berhasil disimpan.
- [ ] Buka safety backup dengan kata sandi restore yang sama dan pastikan keadaan lama dapat dipulihkan.
- [ ] Uji kegagalan penulisan atau baca ulang hasil simpan bila memungkinkan; operasi harus dianggap gagal, dan khusus safety backup restore harus batal dengan data aktif tetap utuh.
- [ ] Bandingkan kelompok rekening aktif, kelompok tersimpan milik rekening arsip, kategori, transaksi, anggaran beserta progres/kategorinya, saldo utama, subtotal simpanan, total seluruh rekening, ringkasan bulanan, dan kalender dengan keadaan sumber.
- [ ] Restore fixture payload v1 dan v2, lalu pastikan seluruh rekening lama masuk ke Saldo utama; restore payload v3 harus mempertahankan kedua nilai `balanceGroup`. Ketiganya harus menampilkan peringatan bahwa anggaran akan kosong setelah replace-all.
- [ ] Restore payload v4 dan pastikan anggaran bulanan/tahunan/kustom, kategori, nominal, periode, timestamp, dan sequence tetap utuh.
- [ ] Tambahkan rekening, kategori, transaksi, dan anggaran setelah restore untuk memastikan ID baru tidak bertabrakan.
- [ ] Uji pada perangkat atau instalasi terpisah: ambil file dari Downloads/Drive, restore, tutup aplikasi sepenuhnya, lalu buka kembali dan periksa data.
- [ ] Pastikan container di atas 16 MiB, plaintext di atas 10 MiB, dan parameter KDF v1 yang tidak sama persis dengan profil produksi ditolak tanpa mengubah database.
- [ ] Ulangi pembuatan dan pembukaan backup pada HP referensi untuk menilai durasi, penggunaan memori, keyboard, ukuran teks besar, pembatalan pemilih dokumen, dan ketahanan terhadap ketukan tombol berulang.

Checklist otomatis dan langkah pengembangan umum tersedia di [panduan pengembangan](development.md).
