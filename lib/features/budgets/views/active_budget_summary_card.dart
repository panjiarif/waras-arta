import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../domain/budget.dart';
import '../view_models/budget_view_model.dart';
import 'budget_widgets.dart';

class ActiveBudgetSummaryCard extends ConsumerWidget {
  const ActiveBudgetSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBudgetSummaryProvider);
    final referenceDay = ref.watch(budgetReferenceDayProvider);
    return Card(
      key: const Key('active-budget-summary'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: active.when(
          loading: () => const _SummaryLoading(),
          error: (_, _) => _SummaryError(
            onRetry: () => ref.invalidate(activeBudgetSummaryProvider),
          ),
          data: (snapshot) {
            if (snapshot.items.isNotEmpty) {
              return _ActiveSummary(
                snapshot: snapshot,
                referenceDay: referenceDay,
              );
            }
            return _NoActiveSummary(
              upcoming: ref.watch(upcomingBudgetSummaryProvider),
              referenceDay: referenceDay,
            );
          },
        ),
      ),
    );
  }
}

class _ActiveSummary extends StatelessWidget {
  const _ActiveSummary({required this.snapshot, required this.referenceDay});

  final BudgetListSnapshot snapshot;
  final int referenceDay;

  @override
  Widget build(BuildContext context) {
    final attentionCount = snapshot.items
        .where(
          (item) =>
              item.usageStatus == BudgetUsageStatus.nearLimit ||
              item.usageStatus == BudgetUsageStatus.exhausted ||
              item.usageStatus == BudgetUsageStatus.exceeded,
        )
        .length;
    final rankedItems = snapshot.items.toList()
      ..sort(_compareActiveSummaryItems);
    final visibleItems = rankedItems.take(2).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryHeader(
          referenceDay: referenceDay,
          subtitle:
              '${snapshot.items.length} aktif'
              '${attentionCount == 0 ? '' : ' · $attentionCount perlu perhatian'}',
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < visibleItems.length; index++) ...[
          _BudgetSummaryRow(item: visibleItems[index]),
          if (index != visibleItems.length - 1) const SizedBox(height: 14),
        ],
        if (snapshot.items.length > 2) ...[
          const SizedBox(height: 12),
          Text(
            '+${snapshot.items.length - 2} anggaran aktif lainnya',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _NoActiveSummary extends StatelessWidget {
  const _NoActiveSummary({required this.upcoming, required this.referenceDay});

  final AsyncValue<BudgetListSnapshot> upcoming;
  final int referenceDay;

  @override
  Widget build(BuildContext context) {
    final items = upcoming.asData?.value.items ?? const <BudgetProgress>[];
    final next = items.isEmpty ? null : items.first;
    final hasAnyUpcoming = next != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryHeader(
          referenceDay: referenceDay,
          subtitle: 'Belum ada yang aktif hari ini',
        ),
        const SizedBox(height: 12),
        Text(
          hasAnyUpcoming
              ? 'Berikutnya: ${next.budget.name}, mulai '
                    '${formatDate(civilDayToDateTime(next.budget.period.startDay))}.'
              : upcoming.hasError
              ? 'Anggaran mendatang belum dapat dibaca.'
              : upcoming.isLoading
              ? 'Memeriksa anggaran mendatang…'
              : 'Buat anggaran untuk menjaga pengeluaran tetap sesuai rencana.',
        ),
        if (!hasAnyUpcoming && !upcoming.isLoading && !upcoming.hasError) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('create-budget-from-summary'),
              onPressed: () => context.push('/budgets/new'),
              icon: const Icon(Icons.add),
              label: const Text('Buat anggaran'),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.referenceDay, required this.subtitle});

  final int referenceDay;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 250 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anggaran aktif',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Aktif hari ini · '
              '${formatDate(civilDayToDateTime(referenceDay))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
        final action = TextButton(
          key: const Key('view-all-budgets'),
          onPressed: () => context.push('/budgets'),
          child: const Text('Lihat semua'),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 8),
            action,
          ],
        );
      },
    );
  }
}

class _BudgetSummaryRow extends StatelessWidget {
  const _BudgetSummaryRow({required this.item});

  final BudgetProgress item;

  @override
  Widget build(BuildContext context) {
    final percentage = budgetPercentage(item);
    final amount =
        '${formatRupiah(item.spentAmount)} dari '
        '${formatRupiah(item.budget.limitAmount)}';
    void openBudget() {
      context.push('/budgets/${item.budget.id}');
    }

    return Semantics(
      key: Key('budget-summary-semantics-${item.budget.id}'),
      container: true,
      button: true,
      onTap: openBudget,
      label:
          '${item.budget.name}, $amount, $percentage persen, '
          '${budgetUsageText(item)}',
      child: ExcludeSemantics(
        child: InkWell(
          key: Key('budget-summary-item-${item.budget.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: openBudget,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 250 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (stacked) ...[
                      Text(
                        item.budget.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(amount),
                      Text(
                        '$percentage% · ${budgetUsageText(item)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.budget.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  amount,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$percentage%',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: item.visualRatio,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

int _compareActiveSummaryItems(BudgetProgress left, BudgetProgress right) {
  var result = _summaryUsageRank(left.usageStatus)
      .compareTo(_summaryUsageRank(right.usageStatus));
  if (result != 0) return result;
  result = left.budget.period.endDay.compareTo(right.budget.period.endDay);
  if (result != 0) return result;
  result = left.budget.period.startDay.compareTo(right.budget.period.startDay);
  if (result != 0) return result;
  result = left.budget.normalizedName.compareTo(right.budget.normalizedName);
  return result != 0 ? result : left.budget.id.compareTo(right.budget.id);
}

int _summaryUsageRank(BudgetUsageStatus status) => switch (status) {
  BudgetUsageStatus.exceeded => 0,
  BudgetUsageStatus.exhausted => 1,
  BudgetUsageStatus.nearLimit => 2,
  BudgetUsageStatus.normal => 3,
};

class _SummaryLoading extends StatelessWidget {
  const _SummaryLoading();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Anggaran aktif', style: TextStyle(fontWeight: FontWeight.w700)),
      SizedBox(height: 12),
      LinearProgressIndicator(),
    ],
  );
}

class _SummaryError extends StatelessWidget {
  const _SummaryError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Anggaran aktif',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text('Ringkasan anggaran belum dapat dibaca.'),
      TextButton.icon(
        key: const Key('retry-budget-summary'),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Coba lagi'),
      ),
    ],
  );
}
