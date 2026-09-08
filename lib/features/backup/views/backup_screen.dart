import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../data/backup/backup_service.dart';
import '../../../data/backup/encrypted_backup_codec.dart';
import '../../ledger/views/form_widgets.dart';
import '../view_models/backup_view_model.dart';

class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(backupControllerProvider);
    return PopScope(
      canPop: !state.isBusy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Backup & pulihkan data')),
        body: FormBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Jaga catatan keuanganmu',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Backup adalah salinan pada saat dibuat. Simpan file di Drive, '
                'komputer, atau tempat lain di luar HP ini.',
              ),
              const SizedBox(height: 20),
              const _PasswordWarning(),
              const SizedBox(height: 20),
              if (state.error != null) ...[
                FormMessage(state.error!, isError: true),
                const SizedBox(height: 16),
              ],
              if (state.isBusy) ...[
                Semantics(
                  liveRegion: true,
                  label: _phaseLabel(state.phase),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        _phaseLabel(state.phase),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              _ActionCard(
                icon: Icons.cloud_upload_outlined,
                title: 'Buat backup terenkripsi',
                description:
                    'Menyimpan seluruh rekening, kategori, transaksi, transfer, '
                    'penyesuaian saldo, dan anggaran dalam satu file .warasarta.',
                buttonKey: const Key('create-backup'),
                buttonLabel: 'Buat backup',
                onPressed: state.isBusy
                    ? null
                    : () => _createBackup(context, ref),
              ),
              const SizedBox(height: 16),
              _ActionCard(
                icon: Icons.settings_backup_restore,
                title: 'Pulihkan dari backup',
                description:
                    'Pilih file .warasarta, buka dengan kata sandinya, lalu '
                    'periksa ringkasan sebelum mengganti data saat ini.',
                buttonKey: const Key('restore-backup'),
                buttonLabel: 'Pilih file backup',
                outlined: true,
                onPressed: state.isBusy
                    ? null
                    : () => _restoreBackup(context, ref),
              ),
              const SizedBox(height: 16),
              const FormMessage(
                'Backup hanya memuat data yang ada saat file dibuat. Buat '
                'backup baru setelah mengubah transaksi, rekening, kategori, '
                'atau anggaran penting.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createBackup(BuildContext context, WidgetRef ref) async {
    ref.read(backupControllerProvider.notifier).clearError();
    final password = await _showPasswordDialog(
      context,
      title: 'Kata sandi backup',
      confirmPassword: true,
    );
    if (password == null || !context.mounted) return;

    final outcome = await ref
        .read(backupControllerProvider.notifier)
        .createBackup(password);
    if (!context.mounted || outcome != BackupActionOutcome.success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Backup berhasil disimpan. Pastikan file berada di lokasi yang aman.',
        ),
      ),
    );
  }

  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(backupControllerProvider.notifier);
    controller.clearError();
    final selected = await controller.pickRestoreFile();
    if (selected == null || !context.mounted) return;

    final password = await _showPasswordDialog(
      context,
      title: 'Buka backup',
      confirmPassword: false,
    );
    if (password == null || !context.mounted) return;

    final plan = await controller.inspectRestore(selected.bytes, password);
    if (plan == null || !context.mounted) return;
    final confirmed = await _showRestoreConfirmation(
      context,
      fileName: selected.name,
      plan: plan,
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final outcome = await controller.restoreWithSafetyBackup(plan, password);
    if (!context.mounted) return;
    if (outcome != BackupActionOutcome.success) {
      if (outcome == BackupActionOutcome.canceled) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Restore dibatalkan karena backup pengaman belum disimpan.',
            ),
          ),
        );
      }
      return;
    }
    context.go('/');
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Data berhasil dipulihkan. Backup pengaman data sebelumnya juga sudah disimpan.',
        ),
      ),
    );
  }
}

class _PasswordWarning extends StatelessWidget {
  const _PasswordWarning();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      child: Container(
        key: const Key('backup-password-warning'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colors.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ingat kata sandi backup',
                    style: TextStyle(
                      color: colors.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kata sandi tidak disimpan dan tidak dapat dipulihkan. '
                    'Jika lupa, file backup tidak akan bisa direstore.',
                    style: TextStyle(color: colors.onTertiaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
    this.outlined = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: forest),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(description),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (outlined)
            OutlinedButton.icon(
              key: buttonKey,
              onPressed: onPressed,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(buttonLabel),
            )
          else
            FilledButton.icon(
              key: buttonKey,
              onPressed: onPressed,
              icon: const Icon(Icons.lock_outline),
              label: Text(buttonLabel),
            ),
        ],
      ),
    ),
  );
}

Future<String?> _showPasswordDialog(
  BuildContext context, {
  required String title,
  required bool confirmPassword,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _PasswordDialog(title: title, confirmPassword: confirmPassword),
);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, required this.confirmPassword});

  final String title;
  final bool confirmPassword;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscured = true;

  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_password.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Kata sandi ini tidak disimpan dan tidak dapat dipulihkan. '
            'Tanpa kata sandi, backup tidak dapat direstore.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('backup-password'),
            controller: _password,
            obscureText: _obscured,
            maxLength: maximumBackupPasswordLength,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            textInputAction: widget.confirmPassword
                ? TextInputAction.next
                : TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Kata sandi',
              helperText: widget.confirmPassword
                  ? 'Minimal $minimumBackupPasswordLength karakter; gunakan kalimat yang mudah diingat.'
                  : null,
              suffixIcon: IconButton(
                key: const Key('toggle-backup-password'),
                tooltip: _obscured
                    ? 'Tampilkan kata sandi'
                    : 'Sembunyikan kata sandi',
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) => widget.confirmPassword
                ? validateNewBackupPassword(value ?? '')
                : validateBackupPasswordForRestore(value ?? ''),
            onFieldSubmitted: (_) {
              if (!widget.confirmPassword) _submit();
            },
          ),
          if (widget.confirmPassword) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('backup-password-confirmation'),
              controller: _confirmation,
              obscureText: _obscured,
              maxLength: maximumBackupPasswordLength,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Ulangi kata sandi'),
              validator: (value) =>
                  normalizeBackupPassword(value ?? '') ==
                      normalizeBackupPassword(_password.text)
                  ? null
                  : 'Kata sandi tidak sama.',
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Batal'),
      ),
      FilledButton(
        key: const Key('submit-backup-password'),
        onPressed: _submit,
        child: Text(widget.confirmPassword ? 'Lanjut simpan' : 'Buka backup'),
      ),
    ],
  );
}

Future<bool> _showRestoreConfirmation(
  BuildContext context, {
  required String fileName,
  required BackupRestorePlan plan,
}) async {
  final summary = plan.summary;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final colors = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            scrollable: true,
            title: const Text('Ganti seluruh data?'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _PreviewRow(
                  label: 'Dibuat',
                  value: formatDateTime(summary.createdAtUtc.toLocal()),
                ),
                _PreviewRow(
                  label: 'Rekening',
                  value: '${summary.accountCount}',
                ),
                _PreviewRow(
                  label: 'Kategori',
                  value: '${summary.categoryCount}',
                ),
                _PreviewRow(
                  label: 'Transaksi',
                  value: '${summary.ledgerEntryCount}',
                ),
                _PreviewRow(label: 'Anggaran', value: '${summary.budgetCount}'),
                if (plan.clearsBudgets) ...[
                  const SizedBox(height: 12),
                  Container(
                    key: const Key('legacy-backup-budget-warning'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Backup versi lama ini belum memuat anggaran. Setelah '
                      'restore, daftar anggaran akan kosong.',
                      style: TextStyle(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Seluruh data saat ini akan diganti oleh isi backup. '
                  'Pastikan file dan jumlah datanya sudah benar. Sebelum '
                  'restore, kamu akan diminta menyimpan backup pengaman data '
                  'saat ini dengan kata sandi yang sama.',
                  style: TextStyle(
                    color: colors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                key: const Key('confirm-restore-backup'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Backup lalu pulihkan'),
              ),
            ],
          );
        },
      ) ??
      false;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

String _phaseLabel(BackupPhase phase) => switch (phase) {
  BackupPhase.idle => '',
  BackupPhase.preparingExport => 'Menyiapkan dan mengenkripsi backup…',
  BackupPhase.savingFile => 'Menunggu lokasi penyimpanan…',
  BackupPhase.pickingFile => 'Memilih file backup…',
  BackupPhase.decrypting => 'Membuka dan memeriksa backup…',
  BackupPhase.restoring => 'Memulihkan data…',
};
