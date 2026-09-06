import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../view_models/ledger_view_model.dart';
import 'entry_form_screen.dart';
import 'form_widgets.dart';

class EntryDetailScreen extends ConsumerStatefulWidget {
  const EntryDetailScreen({super.key, required this.entryId});

  final int entryId;

  @override
  ConsumerState<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends ConsumerState<EntryDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(financeEntryProvider(widget.entryId));
    return entry.when(
      loading: () => const _EntryStateScreen.loading(),
      error: (_, _) => _EntryStateScreen.error(
        onRetry: () => ref.invalidate(financeEntryProvider(widget.entryId)),
      ),
      data: (value) => value == null
          ? const _EntryStateScreen.notFound()
          : _detail(context, value),
    );
  }

  Widget _detail(BuildContext context, FinanceEntry entry) {
    final save = ref.watch(financeActionsProvider);
    final snapshot = ref.watch(financeSnapshotProvider);
    final accounts = snapshot.asData?.value.accounts;
    String accountName(int id) =>
        accounts?.where((account) => account.id == id).firstOrNull?.name ??
        (accounts == null
            ? snapshot.hasError
                  ? 'Rekening belum tersedia'
                  : 'Memuat rekening…'
            : 'Rekening tidak ditemukan');
    final editable = entry.kind != EntryKind.adjustment;
    final amountColor = entry.kind == EntryKind.expense
        ? const Color(0xFF9D492B)
        : forest;
    final amountPrefix = switch (entry.kind) {
      EntryKind.income => '+ ',
      EntryKind.expense => '− ',
      _ => '',
    };

    return PopScope(
      canPop: !save.isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail transaksi'),
          actions: [
            if (editable)
              IconButton(
                key: const Key('edit-entry'),
                tooltip: 'Edit transaksi',
                onPressed: save.isSaving
                    ? null
                    : () {
                        ref.read(financeActionsProvider.notifier).clearError();
                        context.push('/transactions/${entry.id}/edit');
                      },
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
                          Icon(_entryIcon(entry.kind), color: amountColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              entry.category ?? entry.kind.label,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '$amountPrefix${formatRupiah(entry.amount)}',
                        key: const Key('entry-detail-amount'),
                        style: TextStyle(
                          color: amountColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (snapshot.isLoading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ] else if (snapshot.hasError) ...[
                const SizedBox(height: 16),
                const FormMessage(
                  'Nama rekening belum dapat dimuat. Detail transaksi lainnya tetap tersedia.',
                  isError: true,
                ),
                TextButton.icon(
                  onPressed: () => ref.invalidate(financeSnapshotProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Muat ulang rekening'),
                ),
              ],
              const SizedBox(height: 20),
              _DetailRow(label: 'Jenis', value: entry.kind.label),
              if (entry.kind == EntryKind.transfer) ...[
                _DetailRow(
                  label: 'Dari rekening',
                  value: accountName(entry.accountId),
                ),
                _DetailRow(
                  label: 'Ke rekening',
                  value: accountName(entry.destinationAccountId!),
                ),
              ] else
                _DetailRow(
                  label: entry.kind == EntryKind.income
                      ? 'Ke rekening'
                      : 'Dari rekening',
                  value: accountName(entry.accountId),
                ),
              if (entry.category != null)
                _DetailRow(label: 'Kategori', value: entry.category!),
              _DetailRow(
                label: 'Tanggal kejadian',
                value: formatDate(entry.occurredAt),
              ),
              _DetailRow(
                label: 'Catatan',
                value: entry.note.isEmpty ? 'Tidak ada catatan' : entry.note,
              ),
              _DetailRow(
                label: 'Dicatat pada',
                value: formatDateTime(entry.createdAt),
              ),
              if (!editable) ...[
                const SizedBox(height: 12),
                const FormMessage(
                  'Saldo awal menjadi dasar perhitungan rekening dan belum dapat diedit atau dihapus dari halaman ini.',
                ),
              ],
              if (save.error != null) ...[
                const SizedBox(height: 16),
                FormMessage(save.error!, isError: true),
              ],
              if (editable) ...[
                const SizedBox(height: 24),
                FilledButton.tonalIcon(
                  onPressed: save.isSaving
                      ? null
                      : () {
                          ref
                              .read(financeActionsProvider.notifier)
                              .clearError();
                          context.push('/transactions/${entry.id}/edit');
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit transaksi'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('delete-entry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    minimumSize: const Size(48, 52),
                  ),
                  onPressed: save.isSaving ? null : () => _confirmDelete(entry),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(save.isSaving ? 'Menghapus…' : 'Hapus transaksi'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(FinanceEntry entry) async {
    ref.read(financeActionsProvider.notifier).clearError();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: Text(
          '${formatRupiah(entry.amount)} pada ${formatDate(entry.occurredAt)} akan dihapus permanen. Saldo dan ringkasan akan dihitung ulang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
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
        .read(financeActionsProvider.notifier)
        .deleteEntry(entry.id);
    if (deleted && mounted) {
      router.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Transaksi telah dihapus.')),
      );
    }
  }
}

class EntryEditScreen extends ConsumerWidget {
  const EntryEditScreen({super.key, required this.entryId});

  final int entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(financeEntryProvider(entryId));
    return entry.when(
      loading: () => const _EntryStateScreen.loading(),
      error: (_, _) => _EntryStateScreen.error(
        onRetry: () => ref.invalidate(financeEntryProvider(entryId)),
      ),
      data: (value) {
        if (value == null) return const _EntryStateScreen.notFound();
        if (value.kind == EntryKind.adjustment) {
          return const _EntryStateScreen(
            title: 'Edit transaksi',
            icon: Icons.lock_outline,
            message: 'Saldo awal belum dapat diedit dari halaman transaksi.',
          );
        }
        return EntryFormScreen(
          key: ValueKey('entry-editor-${value.id}'),
          initialEntry: value,
        );
      },
    );
  }
}

class _EntryStateScreen extends StatelessWidget {
  const _EntryStateScreen({
    required this.title,
    required this.icon,
    required this.message,
    this.onRetry,
  }) : loading = false;

  const _EntryStateScreen.loading()
    : title = 'Detail transaksi',
      icon = Icons.receipt_long_outlined,
      message = '',
      onRetry = null,
      loading = true;

  const _EntryStateScreen.notFound()
    : title = 'Transaksi tidak ditemukan',
      icon = Icons.search_off,
      message = 'Catatan ini mungkin sudah dihapus atau alamatnya tidak valid.',
      onRetry = null,
      loading = false;

  factory _EntryStateScreen.error({required VoidCallback onRetry}) =>
      _EntryStateScreen(
        title: 'Detail transaksi',
        icon: Icons.error_outline,
        message:
            'Transaksi belum dapat dimuat. Coba kembali beberapa saat lagi.',
        onRetry: onRetry,
      );

  final String title;
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FormBody(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(icon, size: 48, color: forest),
                const SizedBox(height: 16),
                FormMessage(message, isError: onRetry != null),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba lagi'),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Kembali'),
                ),
              ],
            ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 128,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        const SizedBox(width: 12),
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

IconData _entryIcon(EntryKind kind) => switch (kind) {
  EntryKind.income => Icons.south_west,
  EntryKind.expense => Icons.north_east,
  EntryKind.transfer => Icons.swap_horiz,
  EntryKind.adjustment => Icons.savings_outlined,
};
