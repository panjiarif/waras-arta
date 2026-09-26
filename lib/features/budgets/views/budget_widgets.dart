import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/category_icons.dart';
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
    final periodLabel = budgetGroupLabel(group.startDay, group.endDay);
    final kindLabel = group.periodKinds.map((kind) => kind.label).join(' + ');
    final exceeded = group.exceededAmount;
    final issueCount = group.attentionCount;
    final netLabel = exceeded > 0
        ? 'Melebihi ${formatRupiah(exceeded)}'
        : 'Sisa ${formatRupiah(group.remainingAmount)}';
    final statusColor = exceeded > 0
        ? Theme.of(context).colorScheme.error
        : issueCount > 0
        ? const Color(0xFF9D5A00)
        : forest;
    final semanticsLabel = [
      periodLabel,
      kindLabel,
      '${group.items.length} anggaran',
      'Terpakai ${formatRupiah(group.totalSpent)} dari batas '
          '${formatRupiah(group.totalLimit)}',
      '${group.percentage} persen',
      netLabel,
      if (issueCount > 0) '$issueCount perlu perhatian',
    ].join(', ');

    final keySuffix =
        '${group.periodKind.name}-${group.startDay}-${group.endDay}';
    return Semantics(
      key: ValueKey('budget-group-semantics-$keySuffix'),
      container: true,
      header: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('budget-group-$keySuffix'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$kindLabel · $periodLabel'.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    formatRupiah(group.totalSpent),
                    key: ValueKey('budget-group-spent-$keySuffix'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Text('dari'),
                  Text(
                    formatRupiah(group.totalLimit),
                    key: ValueKey('budget-group-limit-$keySuffix'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      key: ValueKey('budget-group-progress-$keySuffix'),
                      value: group.visualRatio,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(6),
                      color: statusColor,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${group.percentage}%',
                    key: ValueKey('budget-group-percentage-$keySuffix'),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                issueCount > 0
                    ? '$netLabel · $issueCount perlu perhatian'
                    : netLabel,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BudgetPeriodSection extends StatelessWidget {
  const BudgetPeriodSection({
    super.key,
    required this.group,
    required this.onOpenBudget,
    this.usageThroughLabel,
  });

  final BudgetRangeGroup group;
  final ValueChanged<int> onOpenBudget;
  final String? usageThroughLabel;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey(
      'budget-section-${group.periodKinds.first.name}-'
      '${group.startDay}-${group.endDay}',
    ),
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BudgetRangeHeader(group: group),
        if (usageThroughLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(
              usageThroughLabel!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (var index = 0; index < group.items.length; index++) ...[
          const Divider(height: 1),
          BudgetCompactRow(
            progress: group.items[index],
            onTap: () => onOpenBudget(group.items[index].budget.id),
          ),
        ],
      ],
    ),
  );
}

class BudgetCompactRow extends StatelessWidget {
  const BudgetCompactRow({
    super.key,
    required this.progress,
    required this.onTap,
  });

  final BudgetProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final budget = progress.budget;
    final percentage = budgetPercentage(progress);
    final statusColor = switch (progress.usageStatus) {
      BudgetUsageStatus.exceeded ||
      BudgetUsageStatus.exhausted => Theme.of(context).colorScheme.error,
      BudgetUsageStatus.nearLimit => const Color(0xFF9D5A00),
      BudgetUsageStatus.normal => forest,
    };
    final icon = progress.categories.length == 1
        ? categoryIconFor(progress.categories.single.iconKey)
        : Icons.category_outlined;
    final iconLabel = progress.categories.length == 1
        ? progress.categories.single.displayName
        : '${progress.categories.length} kategori';
    final semanticsLabel = [
      budget.name,
      budget.period.kind.label,
      budgetPeriodLabel(budget.period),
      iconLabel,
      'Terpakai ${formatRupiah(progress.spentAmount)} dari '
          '${formatRupiah(budget.limitAmount)}',
      '$percentage persen',
      budgetUsageText(progress),
    ].join(', ');
    final enlarged = MediaQuery.textScalerOf(context).scale(14) > 20;

    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          key: ValueKey('open-budget-${budget.id}'),
          onTap: onTap,
          child: Container(
            key: ValueKey('budget-card-${budget.id}'),
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (enlarged) ...[
                        Text(
                          budget.name,
                          key: ValueKey('budget-name-${budget.id}'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$percentage%',
                          key: ValueKey('budget-percent-${budget.id}'),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                budget.name,
                                key: ValueKey('budget-name-${budget.id}'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '$percentage%',
                              key: ValueKey('budget-percent-${budget.id}'),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatRupiah(progress.spentAmount)} dari '
                        '${formatRupiah(budget.limitAmount)}',
                        key: ValueKey('budget-spent-${budget.id}'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        key: ValueKey('budget-progress-${budget.id}'),
                        value: progress.visualRatio,
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(5),
                        color: statusColor,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        budgetUsageText(progress),
                        key: ValueKey('budget-status-${budget.id}'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
