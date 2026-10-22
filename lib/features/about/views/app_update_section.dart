import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ledger/views/form_widgets.dart';
import '../view_models/app_update_view_model.dart';

class AppUpdateSection extends ConsumerWidget {
  const AppUpdateSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    final actions = ref.read(appUpdateProvider.notifier);
    final release = state.release;
    final downloaded = state.path != null;
    return Column(
      key: const Key('about-app-update'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pembaruan aplikasi',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Periksa rilis GitHub, termasuk versi alpha. Koneksi hanya digunakan saat kamu memeriksa atau mengunduh pembaruan; catatan keuangan tidak dikirim.',
        ),
        const SizedBox(height: 12),
        if (state.phase == AppUpdatePhase.current) ...[
          const Text(
            'Aplikasi sudah menggunakan versi terbaru yang tersedia.',
            key: Key('update-current'),
          ),
          const SizedBox(height: 10),
        ],
        if (release != null) ...[
          Text(
            'Tersedia ${release.tag}${release.prerelease ? ' · Versi pengujian' : ''}',
            key: const Key('update-release-version'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('APK Android · ${_megabytes(release.size)} MB'),
          if (release.notes.trim().isNotEmpty)
            ExpansionTile(
              key: const Key('update-release-notes'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Catatan pembaruan'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(release.notes),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (state.phase == AppUpdatePhase.downloading) ...[
            LinearProgressIndicator(
              key: const Key('update-download-progress'),
              value: state.progress?.fraction,
              semanticsLabel: 'Progres unduhan APK',
            ),
            const SizedBox(height: 8),
            Text(
              '${((state.progress?.fraction ?? 0) * 100).floor()}% · ${_megabytes(state.progress?.received ?? 0)} / ${_megabytes(release.size)} MB',
              key: const Key('update-download-size'),
            ),
            TextButton(
              key: const Key('cancel-update-download'),
              onPressed: actions.cancelDownload,
              child: const Text('Batalkan unduhan'),
            ),
          ] else if (!downloaded)
            FilledButton.icon(
              key: const Key('download-update'),
              onPressed: state.isBusy ? null : actions.download,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Unduh pembaruan'),
            ),
          if (downloaded) ...[
            const Text(
              'APK telah lolos pemeriksaan ukuran dan SHA-256. Identitas aplikasi, versi, dan tanda tangan diperiksa lagi sebelum pemasangan.',
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('install-update'),
              onPressed: state.isBusy
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Pasang pembaruan?'),
                          content: const SingleChildScrollView(
                            child: Text(
                              'Sebaiknya buat backup terbaru terlebih dahulu. Pembaruan dipasang menimpa aplikasi lama; jangan uninstall atau hapus data.\n\nJika diminta, izinkan Waras Arta memasang aplikasi dari sumber ini. Setelah itu, konfirmasikan pembaruan pada pemasang Android.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Batal'),
                            ),
                            FilledButton(
                              key: const Key('confirm-install-update'),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Lanjutkan'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        await actions.install();
                      }
                    },
              icon: const Icon(Icons.system_update_outlined),
              label: Text(
                state.phase == AppUpdatePhase.installing
                    ? 'Menyiapkan pemasangan…'
                    : 'Pasang pembaruan',
              ),
            ),
            TextButton(
              key: const Key('redownload-update'),
              onPressed: state.isBusy ? null : actions.download,
              child: const Text('Unduh ulang APK'),
            ),
          ],
        ],
        if (state.error != null) ...[
          const SizedBox(height: 10),
          FormMessage(state.error!, isError: true),
        ],
        if (state.message != null) ...[
          const SizedBox(height: 10),
          FormMessage(state.message!),
        ],
        if (state.phase == AppUpdatePhase.checking) ...[
          const LinearProgressIndicator(semanticsLabel: 'Memeriksa pembaruan'),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          key: const Key('check-app-update'),
          onPressed: state.isBusy ? null : actions.check,
          icon: const Icon(Icons.refresh),
          label: Text(
            state.phase == AppUpdatePhase.checking
                ? 'Memeriksa…'
                : 'Cek pembaruan',
          ),
        ),
      ],
    );
  }

  String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');
}
