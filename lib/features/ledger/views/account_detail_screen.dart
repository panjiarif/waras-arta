import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../view_models/account_view_model.dart';
import 'account_widgets.dart';
import 'form_widgets.dart';

class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final int accountId;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(accountActionsProvider.notifier).clearError();
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(accountDetailsProvider(widget.accountId));
    return details.when(
      loading: () => const AccountAsyncScreen.loading(title: 'Detail rekening'),
      error: (_, _) => AccountAsyncScreen.error(
        title: 'Detail rekening',
        onRetry: () => ref.invalidate(accountDetailsProvider(widget.accountId)),
      ),
      data: (value) => value == null
          ? const AccountAsyncScreen.notFound(title: 'Rekening tidak ditemukan')
          : _detail(value),
    );
  }

  Widget _detail(AccountDetails details) {
    final account = details.account;
    final action = ref.watch(accountActionsProvider);
    final busy = action.isSaving && action.targetId == account.id;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail rekening'),
          actions: [
            IconButton(
              key: const Key('edit-account'),
              tooltip: 'Edit rekening',
              onPressed: busy ? null : () => _openEditor(account.id),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: FormBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            foregroundColor: forest,
                            child: Icon(accountIconFor(account.type)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              account.name,
                              key: const Key('account-detail-name'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          AccountStatusBadge(archived: account.isArchived),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'SALDO SAAT INI',
                        style: TextStyle(
                          color: forest,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatRupiah(account.balance),
                        key: const Key('account-detail-balance'),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AccountDetailRow(label: 'Jenis', value: account.type.label),
              AccountDetailRow(
                label: 'Status',
                value: account.isArchived ? 'Diarsipkan' : 'Aktif',
              ),
              AccountDetailRow(
                label: 'Dibuat pada',
                value: formatDate(details.createdAt),
              ),
              AccountDetailRow(
                label: 'Riwayat',
                value:
                    '${details.ledgerEntryCount} transaksi terkait, termasuk transfer',
              ),
              if (account.isArchived) ...[
                const SizedBox(height: 12),
                const FormMessage(
                  'Rekening arsip tetap muncul pada riwayat lama, tetapi tidak dapat dipakai untuk transaksi baru.',
                ),
              ] else if (account.balance != 0) ...[
                const SizedBox(height: 12),
                const FormMessage(
                  'Saldo harus Rp 0 sebelum rekening dapat diarsipkan. Gunakan penyesuaian saldo atau transfer terlebih dahulu.',
                ),
              ],
              if (action.error != null && action.targetId == account.id) ...[
                const SizedBox(height: 16),
                FormMessage(action.error!, isError: true),
              ],
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                key: const Key('open-account-edit'),
                onPressed: busy ? null : () => _openEditor(account.id),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit nama dan jenis'),
              ),
              if (!account.isArchived) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  key: const Key('open-balance-adjustment'),
                  onPressed: busy ? null : () => _openAdjustment(account.id),
                  icon: const Icon(Icons.tune),
                  label: const Text('Sesuaikan saldo'),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('toggle-account-archive'),
                onPressed: busy || (!account.isArchived && account.balance != 0)
                    ? null
                    : () => account.isArchived
                          ? _restore(account)
                          : _confirmArchive(account),
                icon: Icon(
                  account.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                label: Text(
                  account.isArchived
                      ? 'Pulihkan rekening'
                      : 'Arsipkan rekening',
                ),
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Zona berbahaya',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                details.canDelete
                    ? 'Rekening belum pernah dipakai sehingga dapat dihapus permanen.'
                    : 'Rekening yang sudah memiliki riwayat tidak dapat dihapus. Arsipkan agar transaksi lama tetap utuh.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('delete-account'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size(48, 52),
                ),
                onPressed: busy || !details.canDelete
                    ? null
                    : () => _confirmDelete(account),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Hapus rekening permanen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(int accountId) async {
    ref.read(accountActionsProvider.notifier).clearError();
    await context.push('/accounts/$accountId/edit');
    if (mounted) ref.read(accountActionsProvider.notifier).clearError();
  }

  Future<void> _openAdjustment(int accountId) async {
    ref.read(accountActionsProvider.notifier).clearError();
    await context.push('/accounts/$accountId/adjust');
    if (mounted) ref.read(accountActionsProvider.notifier).clearError();
  }

  Future<void> _confirmArchive(FinanceAccount account) async {
    ref.read(accountActionsProvider.notifier).clearError();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Arsipkan ${account.name}?'),
        content: const Text(
          'Rekening tidak dapat dipilih untuk transaksi baru. Seluruh riwayat lama tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('confirm-archive-account'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Arsipkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final saved = await ref
        .read(accountActionsProvider.notifier)
        .setArchived(account.id, true);
    if (!saved || !mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Rekening diarsipkan.')));
  }

  Future<void> _restore(FinanceAccount account) async {
    ref.read(accountActionsProvider.notifier).clearError();
    final saved = await ref
        .read(accountActionsProvider.notifier)
        .setArchived(account.id, false);
    if (!saved || !mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Rekening dipulihkan.')));
  }

  Future<void> _confirmDelete(FinanceAccount account) async {
    ref.read(accountActionsProvider.notifier).clearError();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Hapus ${account.name}?'),
        content: const Text(
          'Rekening ini belum memiliki transaksi. Penghapusan permanen tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('confirm-delete-account'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus permanen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final deleted = await ref
        .read(accountActionsProvider.notifier)
        .deleteAccount(account.id);
    if (!deleted || !mounted) return;
    router.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Rekening telah dihapus.')),
    );
  }
}
