import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../domain/budget.dart';

String budgetPeriodLabel(BudgetPeriod period) {
  final start = civilDayToDateTime(period.startDay);
  final end = civilDayToDateTime(period.endDay);
  return '${formatDate(start)} – ${formatDate(end)}';
}

String budgetGroupLabel(int startDay, int endDay) {
  final start = civilDayToDateTime(startDay);
  final end = civilDayToDateTime(endDay);
  final fullMonth =
      start.day == 1 &&
      start.year == end.year &&
      start.month == end.month &&
      end.day == DateTime(start.year, start.month + 1, 0).day;
  if (fullMonth) return formatMonth(start);
  final fullYear =
      start.month == 1 &&
      start.day == 1 &&
      end.year == start.year &&
      end.month == 12 &&
      end.day == 31;
  if (fullYear) return 'Tahun ${start.year}';
  return budgetPeriodLabel(BudgetPeriod.custom(startDay, endDay));
}

int budgetPercentage(BudgetProgress progress) {
  return progress.spentAmount * 100 ~/ progress.budget.limitAmount;
}

String budgetCategorySummary(List<BudgetCategoryRef> categories) {
  if (categories.isEmpty) return 'Tanpa kategori';
  final examples = categories
      .take(2)
      .map((item) => item.displayName)
      .join(', ');
  final remaining = categories.length - 2;
  return remaining > 0 ? '$examples +$remaining lainnya' : examples;
}

String budgetUsageText(BudgetProgress progress) {
  return switch (progress.usageStatus) {
    BudgetUsageStatus.normal =>
      'Sisa ${formatRupiah(progress.remainingAmount)}',
    BudgetUsageStatus.nearLimit =>
      'Hampir habis · Sisa ${formatRupiah(progress.remainingAmount)}',
    BudgetUsageStatus.exhausted => 'Anggaran habis',
    BudgetUsageStatus.exceeded =>
      'Melebihi ${formatRupiah(progress.exceededAmount)}',
  };
}

class BudgetProgressCard extends StatelessWidget {
  const BudgetProgressCard({
    super.key,
    required this.progress,
    this.onTap,
    this.cardKey,
  });

  final BudgetProgress progress;
  final VoidCallback? onTap;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final budget = progress.budget;
    final percentage = budgetPercentage(progress);
    final usage = progress.usageStatus;
    final statusColor = switch (usage) {
      BudgetUsageStatus.exceeded => Theme.of(context).colorScheme.error,
      BudgetUsageStatus.exhausted => Theme.of(context).colorScheme.error,
      BudgetUsageStatus.nearLimit => const Color(0xFF9D5A00),
      BudgetUsageStatus.normal => forest,
    };
    final statusIcon = switch (usage) {
      BudgetUsageStatus.exceeded => Icons.warning_amber_rounded,
      BudgetUsageStatus.exhausted => Icons.block_outlined,
      BudgetUsageStatus.nearLimit => Icons.timelapse,
      BudgetUsageStatus.normal => Icons.check_circle_outline,
    };
    final semanticLabel = [
      budget.name,
      budget.period.kind.label,
      budgetPeriodLabel(budget.period),
      '${progress.categories.length} kategori',
      budgetCategorySummary(progress.categories),
      'Terpakai ${formatRupiah(progress.spentAmount)} dari ${formatRupiah(budget.limitAmount)}',
      '$percentage persen',
      budgetUsageText(progress),
    ].join(', ');

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final title = Text(
            budget.name,
            key: ValueKey('budget-name-${budget.id}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          );
          final badge = _BudgetKindBadge(kind: budget.period.kind);
          final spent = Text(
            'Terpakai ${formatRupiah(progress.spentAmount)} dari '
            '${formatRupiah(budget.limitAmount)}',
            key: ValueKey('budget-spent-${budget.id}'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          );
          final percent = Text(
            '$percentage%',
            key: ValueKey('budget-percent-${budget.id}'),
            style: TextStyle(
              color: statusColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stacked) ...[
                title,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: badge),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    badge,
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                budgetPeriodLabel(budget.period),
                key: ValueKey('budget-period-${budget.id}'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                budgetCategorySummary(progress.categories),
                key: ValueKey('budget-categories-${budget.id}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              if (stacked) ...[
                spent,
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: percent),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: spent),
                    const SizedBox(width: 12),
                    percent,
                  ],
                ),
              const SizedBox(height: 8),
              Semantics(
                label:
                    'Progres anggaran $percentage persen. ${budgetUsageText(progress)}',
                child: ExcludeSemantics(
                  child: LinearProgressIndicator(
                    key: ValueKey('budget-progress-${budget.id}'),
                    value: progress.visualRatio,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: statusColor,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(statusIcon, size: 19, color: statusColor),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      budgetUsageText(progress),
                      key: ValueKey('budget-status-${budget.id}'),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Card(
          key: cardKey ?? ValueKey('budget-card-${budget.id}'),
          clipBehavior: Clip.antiAlias,
          child: onTap == null
              ? content
              : InkWell(
                  key: ValueKey('open-budget-${budget.id}'),
                  onTap: onTap,
                  child: content,
                ),
        ),
      ),
    );
  }
}

class BudgetRangeHeader extends StatelessWidget {
  const BudgetRangeHeader({super.key, required this.group});

  final BudgetRangeGroup group;

  @override
  Widget build(BuildContext context) {
    final exceeded = group.exceededAmount;
    final issueCount =
        group.countForStatus(BudgetUsageStatus.nearLimit) +
        group.countForStatus(BudgetUsageStatus.exhausted) +
        group.countForStatus(BudgetUsageStatus.exceeded);
    final netLabel = exceeded > 0
        ? 'Melebihi ${formatRupiah(exceeded)}'
        : 'Sisa ${formatRupiah(group.remainingAmount)}';

    return Container(
      key: ValueKey('budget-group-${group.startDay}-${group.endDay}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final identity = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                budgetGroupLabel(group.startDay, group.endDay),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${group.items.length} anggaran'
                '${issueCount > 0 ? ' · $issueCount perlu perhatian' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
          final totals = Column(
            crossAxisAlignment: stacked
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text(
                'Terpakai ${formatRupiah(group.totalSpent)} dari '
                '${formatRupiah(group.totalLimit)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(netLabel),
            ],
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 10), totals],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: identity),
              const SizedBox(width: 16),
              Flexible(child: totals),
            ],
          );
        },
      ),
    );
  }
}

class _BudgetKindBadge extends StatelessWidget {
  const _BudgetKindBadge({required this.kind});

  final BudgetPeriodKind kind;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        kind.label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class BudgetLoadState extends StatelessWidget {
  const BudgetLoadState({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.savings_outlined,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('retry-budget-load'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
          ],
        ],
      ),
    ),
  );
}
