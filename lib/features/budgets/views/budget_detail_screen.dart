import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/category_icons.dart';
import '../../../core/formatters.dart';
import '../../../domain/budget.dart';
import '../../ledger/views/form_widgets.dart';
import '../view_models/budget_view_model.dart';
import 'budget_widgets.dart';

class BudgetDetailScreen extends ConsumerWidget {
  const BudgetDetailScreen({super.key, required this.budgetId});

  final int budgetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider(budgetId));
    return progress.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Detail anggaran')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Detail anggaran')),
        body: BudgetLoadState(
          message: 'Detail anggaran belum dapat dimuat.',
          onRetry: () {
            ref.invalidate(budgetDetailsProvider(budgetId));
            ref.invalidate(budgetProgressProvider(budgetId));
          },
        ),
      ),
      data: (value) => value == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Detail anggaran')),
              body: const BudgetLoadState(
                message: 'Anggaran tidak ditemukan atau sudah dihapus.',
                icon: Icons.search_off,
              ),
            )
          : _BudgetDetailContent(progress: value),
    );
  }
}

class _BudgetDetailContent extends ConsumerWidget {
  const _BudgetDetailContent({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = progress.budget;
    final action = ref.watch(budgetActionsProvider);
    final busy = action.isSaving && action.targetId == budget.id;

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Detail anggaran',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              key: const Key('edit-budget'),
              tooltip: 'Edit anggaran',
              onPressed: busy
                  ? null
                  : () => context.push('/budgets/${budget.id}/edit'),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: FormBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BudgetProgressCard(
                progress: progress,
                cardKey: const Key('budget-detail-progress'),
              ),
              const SizedBox(height: 20),
              Text(
                'Subkategori pengeluaran',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < progress.categories.length;
                      index++
                    ) ...[
                      ListTile(
                        key: ValueKey(
                          'budget-detail-category-${progress.categories[index].id}',
                        ),
                        leading: Icon(
                          categoryIconFor(progress.categories[index].iconKey),
                        ),
                        title: Text(progress.categories[index].name),
                        subtitle: Text(
                          progress.categories[index].effectiveIsArchived
                              ? '${progress.categories[index].parentName} · Diarsipkan'
                              : progress.categories[index].parentName,
                        ),
                      ),
                      if (index != progress.categories.length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: 'Dibuat',
                value: formatDateTime(budget.createdAt.toLocal()),
              ),
              _DetailRow(
                label: 'Diperbarui',
                value: formatDateTime(budget.updatedAt.toLocal()),
              ),
              if (action.error != null && action.targetId == budget.id) ...[
                const SizedBox(height: 16),
                FormMessage(action.error!, isError: true),
              ],
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                key: const Key('open-budget-edit'),
                onPressed: busy
                    ? null
                    : () => context.push('/budgets/${budget.id}/edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit anggaran'),
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Zona berbahaya',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Menghapus anggaran tidak menghapus kategori, rekening, atau transaksi.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('delete-budget'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size(48, 52),
                ),
                onPressed: busy ? null : () => _confirmDelete(context, ref),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Hapus anggaran permanen',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    ref.read(budgetActionsProvider.notifier).clearError();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Hapus ${progress.budget.name}?'),
        content: const Text(
          'Definisi anggaran dan pilihan kategorinya akan dihapus. Seluruh transaksi tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('confirm-delete-budget'),
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
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final deleted = await ref
        .read(budgetActionsProvider.notifier)
        .deleteBudget(progress.budget.id);
    if (!deleted || !context.mounted) return;
    router.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Anggaran telah dihapus.')),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 124,
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
        );
      },
    ),
  );
}
