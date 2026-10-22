# Changelog

Perubahan penting Waras Arta dicatat di sini. Versi alpha ditujukan untuk pengujian awal, bukan satu-satunya tempat menyimpan catatan keuangan penting.

## 0.1.1 — Alpha 2 (belum dirilis)

### Ditambahkan

- Pilihan ikon kategori untuk listrik, air, bahan bakar, laptop, perangkat, gaji, freelance, dan sumber pendapatan lainnya. Ikon tetap dapat dikustomisasi serta dibackup.
- Ikon anggaran pilihan pengguna, termasuk untuk anggaran multi-subkategori. Mode **Otomatis** tetap tersedia; ikon manual ikut tersimpan pada salinan anggaran bulanan dan backup.
- **Pembaruan aplikasi** di halaman Tentang: cek rilis GitHub termasuk alpha, baca catatan perubahan, unduh APK dengan progres dan pembatalan, unduh ulang, lalu buka pemasang Android.
- Verifikasi ukuran dan SHA-256 unduhan, serta pemeriksaan identitas aplikasi, versi, dan tanda tangan APK sebelum pemasangan.

### Diperbaiki

- Input nominal menampilkan pemisah ribuan, misalnya `1500000` menjadi `1.500.000`, tanpa mengubah penyimpanan nominal rupiah bulat.
- Pemilih subkategori anggaran memakai daftar ringkas berkelompok dengan pencarian, ikon, centang grup, serta jumlah pilihan. Pilihan tidak berubah jika pemilih dibatalkan.
- Kategori anggaran yang diarsipkan atau berkonflik tetap diberi penjelasan dan tidak dapat ditambahkan kembali setelah dilepas selama masih terblokir.
- Dokumentasi serta penjelasan privasi diperbarui untuk penggunaan jaringan atas permintaan pengguna saat cek/unduh pembaruan. Catatan keuangan tidak dikirim ke GitHub.

### Data dan kompatibilitas

- Database naik dari schema v6 ke v7 untuk menyimpan ikon anggaran nullable. Migrasi mempertahankan data lama; anggaran lama tetap memakai ikon otomatis. Tidak perlu menghapus data atau uninstall.
- Backup baru memakai payload v5/schema v7 dengan container enkripsi tetap v1. Backup lama v1–v4 tetap didukung; backup v4 mempertahankan anggaran dengan ikon otomatis.
- Backup yang dibuat versi ini tidak dapat dipulihkan pada v0.1.0. Saat pindah perangkat, gunakan v0.1.1 atau aplikasi lebih baru yang mendukung format tersebut.
- APK publik v0.1.0 belum mempunyai updater. Pengguna memasang v0.1.1 secara manual di atas aplikasi lama untuk mendapatkan fitur pembaruan internal.

### Batas pengujian

- Smoke test perangkat pada 22 Oktober 2026 berhasil: APK release `0.1.1 (2)` dipasang tanpa uninstall, data tetap utuh, dan backup baru berhasil dibuat. Ini belum menguji alur pembaruan internal secara menyeluruh.
- Cek versi telah dicoba pada perangkat dan pemeriksaan metadata GitHub telah diuji langsung. Pemasangan pembaruan menyeluruh melalui aplikasi masih perlu smoke test dengan rilis yang lebih baru dan signing yang sama.
- Unduhan belum mendukung resume setelah aplikasi dihentikan OS; unduh ulang dimulai dari awal. Membuka pemasang Android bukan konfirmasi bahwa pembaruan selesai terpasang.

## 0.1.0 — Alpha 1

Rilis publik pertama untuk Android.

- Pencatatan pemasukan, pengeluaran, transfer antar-rekening, serta transaksi dengan beberapa rincian nominal dan subkategori.
- Kelola rekening, Saldo utama, Simpanan & investasi, koreksi saldo, dan arsip rekening.
- Kategori/subkategori yang dapat dikustomisasi; riwayat, detail transaksi, dan kalender.
- Anggaran bulanan, tahunan, atau kustom, progres berdasarkan kategori, serta salin anggaran bulanan manual.
- Ikhtisar, ringkasan bulanan, dan grafik ringan.
- Backup dan restore manual terenkripsi berformat `.warasarta`.
- Branding, halaman Tentang, kebijakan privasi, dan ketentuan penggunaan.
- Database schema v6 dan backup payload v4.
