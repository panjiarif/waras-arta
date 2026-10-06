import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../ledger/views/form_widgets.dart';
import '../view_models/app_version_info_provider.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionInfoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tentang Waras Arta')),
      body: FormBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BrandIntroduction(),
            const SizedBox(height: 8),
            Text(
              version.when(
                data: (info) => info.label,
                loading: () => 'Memuat versi…',
                error: (_, _) => 'Versi tidak tersedia',
              ),
              key: const Key('about-version'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            const _LocalFirstCallout(),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    key: const Key('privacy-policy-link'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Kebijakan privasi'),
                    subtitle: const Text(
                      'Cara data tersimpan, dibackup, dan dihapus.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/about/privacy'),
                  ),
                  const Divider(height: 1, indent: 58),
                  ListTile(
                    key: const Key('terms-of-use-link'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Ketentuan penggunaan'),
                    subtitle: const Text(
                      'Batas penggunaan dan tanggung jawab pengguna.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/about/terms'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('about-backup-link'),
              onPressed: () => context.push('/backup'),
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Backup & pulihkan data'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandIntroduction extends StatelessWidget {
  const _BrandIntroduction();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Image.asset(
        'assets/branding/icons/app_icon_foreground.png',
        key: const Key('about-brand-mark'),
        width: 144,
        height: 88,
        fit: BoxFit.cover,
        cacheWidth: 432,
        excludeFromSemantics: true,
      ),
      const SizedBox(height: 12),
      Text(
        'Waras Arta',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      const Text(
        'Catat, atur, tetap waras.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: forest,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Pencatatan keuangan pribadi yang local-first. Kelola transaksi, '
        'rekening, kategori, dan anggaran tanpa akun.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ],
  );
}

class _LocalFirstCallout extends StatelessWidget {
  const _LocalFirstCallout();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('about-local-first'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.phonelink_lock_outlined, color: forest),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data tetap di tanganmu',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Data aktif tersimpan di perangkat ini. Buat backup '
                  'terenkripsi secara rutin agar catatan dapat dipulihkan '
                  'ketika berganti perangkat atau HP bermasalah.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
