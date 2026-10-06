import 'package:flutter/material.dart';

import '../../ledger/views/form_widgets.dart';

enum LegalDocumentKind { privacy, terms }

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.kind});

  final LegalDocumentKind kind;

  @override
  Widget build(BuildContext context) {
    final document = _documentFor(kind);
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SelectionArea(
        child: FormBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                document.title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Diperbarui 6 Oktober 2026',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Text(document.introduction),
              const SizedBox(height: 24),
              for (
                var index = 0;
                index < document.sections.length;
                index++
              ) ...[
                _LegalSectionView(
                  index: index + 1,
                  section: document.sections[index],
                ),
                if (index != document.sections.length - 1)
                  const SizedBox(height: 22),
              ],
              if (document.closing != null) ...[
                const SizedBox(height: 24),
                Text(
                  document.closing!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalSectionView extends StatelessWidget {
  const _LegalSectionView({required this.index, required this.section});

  final int index;
  final _LegalSection section;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '$index. ${section.title}',
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(section.body),
    ],
  );
}

class _LegalDocument {
  const _LegalDocument({
    required this.title,
    required this.introduction,
    required this.sections,
    this.closing,
  });

  final String title;
  final String introduction;
  final List<_LegalSection> sections;
  final String? closing;
}

class _LegalSection {
  const _LegalSection(this.title, this.body);

  final String title;
  final String body;
}

_LegalDocument _documentFor(LegalDocumentKind kind) => switch (kind) {
  LegalDocumentKind.privacy => _privacyPolicy,
  LegalDocumentKind.terms => _termsOfUse,
};

const _privacyPolicy = _LegalDocument(
  title: 'Kebijakan privasi',
  introduction: 'Kebijakan ini menjelaskan cara Waras Arta menangani data saat digunakan.',
  sections: [
    _LegalSection(
      'Data yang disimpan',
      'Rekening, kategori, transaksi, catatan, alokasi nominal, dan anggaran '
          'disimpan dalam database privat aplikasi pada perangkat. Saldo dan '
          'ringkasan dihitung dari catatan tersebut.',
    ),
    _LegalSection(
      'Pengumpulan dan pengiriman',
      'Waras Arta tidak meminta akun, tidak memiliki server aplikasi, serta '
          'tidak menyertakan iklan atau analitik. Catatan keuangan tidak '
          'dikirim kepada pengembang.',
    ),
    _LegalSection(
      'Backup',
      'Backup dibuat hanya ketika kamu memintanya dan disimpan ke lokasi yang '
          'kamu pilih sebagai file .warasarta terenkripsi. Kata sandi tidak '
          'disimpan dan tidak dapat dipulihkan. Jika memilih penyedia seperti '
          'Google Drive, file terenkripsi ditangani oleh penyedia tersebut '
          'sesuai kebijakannya.',
    ),
    _LegalSection(
      'Keamanan perangkat',
      'Database aktif belum dienkripsi khusus oleh Waras Arta dan bergantung '
          'pada perlindungan perangkat serta ruang privat Android. Backup '
          'otomatis Android dan pemindahan data aplikasi antardevice '
          'dinonaktifkan; perpindahan data dilakukan dengan backup terenkripsi '
          'manual.',
    ),
    _LegalSection(
      'Menghapus data',
      'Data aktif dapat diubah atau dihapus melalui aplikasi. Menghapus data '
          'aplikasi atau mencopot aplikasi akan menghapus database aktif dari '
          'perangkat. File backup yang disimpan di luar aplikasi tetap ada '
          'sampai kamu menghapusnya sendiri.',
    ),
  ],
  closing:
      'Kebijakan ini berlaku untuk versi saat ini dan perlu diperbarui jika '
      'kelak ditambahkan sinkronisasi, akun, analitik, atau layanan jaringan.',
);

const _termsOfUse = _LegalDocument(
  title: 'Ketentuan penggunaan',
  introduction: 'Waras Arta adalah alat bantu pencatatan keuangan pribadi.',
  sections: [
    _LegalSection(
      'Bukan nasihat keuangan',
      'Informasi, ringkasan, dan grafik di aplikasi bukan nasihat keuangan, '
          'pajak, atau investasi. Keputusan tetap menjadi tanggung jawab '
          'pengguna.',
    ),
    _LegalSection(
      'Ketepatan data',
      'Hasil aplikasi bergantung pada data yang dimasukkan. Periksa nominal, '
          'kategori, rekening, tanggal, dan hasil perhitungan sebelum '
          'menjadikannya dasar keputusan.',
    ),
    _LegalSection(
      'Backup dan pemulihan',
      'Pengguna bertanggung jawab membuat backup berkala, menyimpan file di '
          'lokasi aman, dan mengingat kata sandi. Restore mengganti seluruh '
          'data aktif dengan isi backup setelah backup pengaman berhasil '
          'disimpan.',
    ),
    _LegalSection(
      'Versi pengujian',
      'Versi ini masih dalam tahap pengujian dan dapat memiliki kesalahan '
          'atau perubahan fitur. Simpan lebih dari satu backup dan jangan '
          'jadikan aplikasi sebagai satu-satunya salinan catatan penting.',
    ),
    _LegalSection(
      'Penggunaan wajar',
      'Gunakan aplikasi hanya untuk tujuan yang sah dan pada perangkat atau '
          'data yang berhak kamu kelola.',
    ),
  ],
);
