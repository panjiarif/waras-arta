# Pembaruan aplikasi dari GitHub

## Perilaku

Halaman **Tentang → Pembaruan aplikasi** menyediakan cek rilis, catatan perubahan, unduh APK dengan progres/pembatalan, unduh ulang, dan pemasangan melalui Android. Tidak ada pemeriksaan atau unduhan otomatis saat startup. Pencatatan keuangan tetap offline; updater tidak membaca database, mengirim data keuangan, atau mengubah format backup.

Pemeriksaan menggunakan API publik `GET /repos/panjiarif/waras-arta/releases`, tanpa token. Rilis alpha/pre-release disertakan; draft dan tag yang bukan versi semantik canonical diabaikan. Versi tertinggi dibandingkan secara numerik, bukan menurut urutan tanggal atau string. Versi sama/lebih lama tidak ditawarkan. Untuk rilis berikutnya, naikkan **versi dan build number**, bukan hanya build number. Tag memakai `v0.1.1`, bukan `v0.1.1+2`. Endpoint `/releases/latest` tidak dipakai karena mengecualikan pre-release.

Metadata dibatasi 2 MiB per halaman dan maksimal tiga halaman berisi 100 rilis. Jika batas tercapai, tampilkan kegagalan pemeriksaan, bukan klaim bahwa aplikasi sudah terbaru. Jika rilis terbaru belum mempunyai APK atau checksum yang valid, pemeriksaan juga gagal secara eksplisit; jangan diam-diam menawarkan rilis lama.

## Kontrak publikasi

Untuk contoh `version: 0.1.1+2`:

1. Jalankan analyze, seluruh tes, dan smoke test pada data yang dibackup.
2. Build APK **universal release** dengan application ID serta keystore yang sama. Jangan unggah APK debug atau mengganti keystore.
3. Buat tag `v0.1.1` dari commit yang benar.
4. Unggah tepat satu APK bernama **`waras-arta-v0.1.1-android.apk`** pada GitHub Release tag tersebut; format umumnya `waras-arta-<tag>-android.apk`. Catatan rilis menjadi sumber teks pada aplikasi.
5. Pastikan asset berstatus `uploaded`, mempunyai ukuran positif (maksimal 256 MiB), URL HTTPS repository yang sesuai, dan field API `digest` berbentuk `sha256:<64 hex>`. GitHub menyediakan digest asset; jika belum tersedia, aplikasi menolak unduhan sampai metadata rilis lengkap. Teks SHA-256 manual pada release notes bukan sumber verifikasi updater.
6. Rilis alpha tetap diberi label **Pre-release**. Selesaikan unggahan sebelum publikasi agar pengguna tidak menemukan rilis yang belum lengkap.

Tidak ada token GitHub, password, private key, atau kredensial signing dalam aplikasi. Public API mempunyai rate limit; kegagalan/offline dapat dicoba ulang secara manual.

## Unduhan dan keamanan pemasangan

- Seluruh request HTTPS dibatasi ke host GitHub/API/penyimpanan aset resmi yang diizinkan. Pengalihan dibatasi lima lompatan; HTTP, domain lain, credential URL, dan port selain 443 ditolak. Tidak ada override sertifikat TLS.
- APK dialirkan ke `cache/updates/update-<asset-id>.apk.part`, bukan dimuat penuh ke RAM. SHA-256 dihitung inkremental; jumlah byte harus tepat sesuai metadata. Hanya setelah lolos, file dipromosikan menjadi `.apk`. Progres UI dibatasi frekuensinya untuk HP kelas bawah.
- File gagal/dibatalkan dibersihkan. Percobaan ulang dimulai dari awal, bukan resume. Cache unduhan lama dibersihkan hanya di folder khusus updater, bukan database atau backup.
- Unduhan dapat tetap berjalan saat pengguna berpindah halaman selama proses aplikasi hidup. Belum ada foreground service, notifikasi unduhan, atau resume setelah aplikasi dimatikan OS. Cache dapat dihapus Android; tombol **Unduh ulang APK** tersedia jika file hilang.
- Sebelum pemasangan, Android memeriksa lagi path cache yang diizinkan, ukuran dan SHA-256 file, application ID, `versionName` yang sesuai tag, `versionCode` lebih tinggi, minimum Android, serta signer APK yang sama dengan aplikasi terpasang. Rotasi signing key belum didukung: gunakan keystore yang sama.
- FileProvider tidak diekspor dan hanya membagikan folder `cache/updates/` dengan akses baca sementara kepada pemasang. Tidak ada izin membaca seluruh penyimpanan atau seluruh paket aplikasi.
- Izin `REQUEST_INSTALL_PACKAGES` hanya diminta setelah pengguna memilih memasang dan menyetujui penjelasan. Pada Android 8+, halaman izin sumber ini dibuka bila diperlukan. Menolak izin mempertahankan APK untuk percobaan ulang.
- Membuka pemasang **bukan** bukti pemasangan berhasil. Pengguna tetap mengonfirmasi di Android; membatalkannya tidak ditampilkan sebagai sukses. Tidak ada uninstall, penghapusan data, atau pemasangan paksa.

## Uji manual sebelum dibagikan

- Cek dengan internet/offline; pastikan catatan keuangan tetap dapat digunakan dan pemeriksaan bisa diulang.
- Dengan versi saat ini sama dengan rilis GitHub, hasil **sudah terbaru** memang benar. Jangan menurunkan versi produksi atau memalsukan rilis publik hanya untuk menguji.
- Gunakan dua build release pengujian yang ditandatangani keystore sama dan dua rilis/tag sungguhan untuk uji menyeluruh. Versi penerima harus sudah mempunyai updater. APK v0.1.0 lama belum mempunyai tombol ini; tester memasang satu pembaruan manual terlebih dahulu.
- Unduh versi lebih baru; periksa catatan rilis, progres, pembatalan, ulang unduh, putus koneksi, ruang penyimpanan tidak cukup, dan kembali ke Tentang setelah berpindah halaman.
- Tolak izin sumber tidak dikenal, kembali, lalu berikan izin. Batalkan dialog pemasang dan coba lagi tanpa unduh ulang.
- Pastikan APK korup, signer berbeda, application ID salah, versi tidak cocok, atau build number tidak lebih tinggi ditolak sebelum pemasang dibuka. Jalankan pengujian APK negatif pada perangkat/emulator uji, bukan data keuangan satu-satunya.
- Setelah pemasangan sungguhan, buka aplikasi; periksa versi baru, transaksi, rekening, kategori, anggaran, serta backup–restore. Backup sebelum uji; jangan uninstall atau hapus data.

Unit/widget tests menggunakan metadata/byte/installer palsu untuk memeriksa alur dan kegagalan. Tes tersebut tidak menggantikan verifikasi pemasang Android pada HP.

Referensi: [GitHub Releases API](https://docs.github.com/en/rest/releases/releases), [Release assets API](https://docs.github.com/en/rest/releases/assets), [FileProvider Android](https://developer.android.com/reference/androidx/core/content/FileProvider), dan [app signing Android](https://developer.android.com/studio/publish/app-signing).
