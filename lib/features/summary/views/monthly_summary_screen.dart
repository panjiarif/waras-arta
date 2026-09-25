import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../../calendar/view_models/calendar_view_model.dart';
import '../view_models/monthly_summary_view_model.dart';

const _firstSummaryYear = 2000;
const _incomeColor = Color(0xFF397A58);
const _expenseColor = Color(0xFFB34F38);

class MonthlySummaryScreen extends ConsumerStatefulWidget {
  const MonthlySummaryScreen({super.key, this.initialMonth});

  /// The month selected on the overview before this page was opened.
  final DateTime? initialMonth;

  @override
  ConsumerState<MonthlySummaryScreen> createState() =>
      _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends ConsumerState<MonthlySummaryScreen> {
  late int _year;
  AccountBalanceGroup? _balanceGroup;

  @override
  void initState() {
    super.initState();
    final currentYear = ref.read(currentDateProvider).year;
    _year = (widget.initialMonth?.year ?? currentYear)
        .clamp(_firstSummaryYear, currentYear)
        .toInt();
  }

  void _moveYear(int delta, int currentYear) {
    final target = _year + delta;
    if (target < _firstSummaryYear || target > currentYear) return;
    setState(() => _year = target);
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(ref.watch(currentDateProvider));
    final query = (year: _year, balanceGroup: _balanceGroup);
    final summary = ref.watch(yearlySummaryProvider(query));
    final highlightedMonth = widget.initialMonth == null
        ? null
        : DateTime(widget.initialMonth!.year, widget.initialMonth!.month);

    return Scaffold(
      appBar: AppBar(title: const Text('Ringkasan')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _YearSelector(
                  year: _year,
                  canMoveBackward: _year > _firstSummaryYear,
                  canMoveForward: _year < today.year,
                  onPrevious: () => _moveYear(-1, today.year),
                  onNext: () => _moveYear(1, today.year),
                ),
                _AccountGroupFilter(
                  value: _balanceGroup,
                  onChanged: (value) => setState(() => _balanceGroup = value),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '${_balanceGroup?.label ?? 'Semua rekening'}. '
                    'Transfer, penyesuaian saldo, dan saldo awal tidak dihitung.',
                    key: const Key('summary-scope-caption'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: summary.when(
                    skipLoadingOnReload: true,
                    data: (data) => MonthlySummaryYearView(
                      snapshot: data,
                      today: today,
                      highlightedMonth: highlightedMonth,
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => _SummaryLoadError(
                      onRetry: () =>
                          ref.invalidate(yearlySummaryProvider(query)),
                    ),
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

class _AccountGroupFilter extends StatelessWidget {
  const _AccountGroupFilter({required this.value, required this.onChanged});

  final AccountBalanceGroup? value;
  final ValueChanged<AccountBalanceGroup?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Wrap(
      key: const Key('summary-account-filter'),
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          key: const Key('summary-filter-all'),
          label: const Text('Semua rekening'),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final group in AccountBalanceGroup.values)
          FilterChip(
            key: ValueKey('summary-filter-${group.name}'),
            label: Text(group.label),
            selected: value == group,
            onSelected: (_) => onChanged(group),
          ),
      ],
    ),
  );
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.year,
    required this.canMoveBackward,
    required this.canMoveForward,
    required this.onPrevious,
    required this.onNext,
  });

  final int year;
  final bool canMoveBackward;
  final bool canMoveForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      key: const Key('summary-year-selector'),
      children: [
        IconButton(
          key: const Key('summary-previous-year'),
          tooltip: 'Tahun sebelumnya',
          onPressed: canMoveBackward ? onPrevious : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              '$year',
              key: const Key('summary-selected-year'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton(
          key: const Key('summary-next-year'),
          tooltip: 'Tahun berikutnya',
          onPressed: canMoveForward ? onNext : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
}

/// Pure presentation widget kept separate from the provider-backed screen so
/// the year list can be tested without a database.
class MonthlySummaryYearView extends StatelessWidget {
  const MonthlySummaryYearView({
    super.key,
    required this.snapshot,
    required this.today,
    this.highlightedMonth,
  });

  final YearlySummarySnapshot snapshot;
  final DateTime today;
  final DateTime? highlightedMonth;

  @override
  Widget build(BuildContext context) {
    final visibleMonths =
        snapshot.months
            .where(
              (item) =>
                  snapshot.year < today.year ||
                  (snapshot.year == today.year &&
                      item.month.month <= today.month),
            )
            .toList(growable: false)
          ..sort((left, right) => right.month.compareTo(left.month));

    if (visibleMonths.isEmpty) {
      return const _SummaryEmptyState();
    }

    return ListView.separated(
      key: const PageStorageKey('monthly-summary-list'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      itemCount: visibleMonths.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = visibleMonths[index];
        return MonthlySummaryCard(
          item: item,
          highlighted: _sameMonth(item.month, highlightedMonth),
        );
      },
    );
  }
}

class MonthlySummaryCard extends StatelessWidget {
  const MonthlySummaryCard({
    super.key,
    required this.item,
    this.highlighted = false,
  });

  final MonthlySummaryItem item;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final monthKey = _monthKey(item.month);
    final empty = item.income == 0 && item.expense == 0;
    final semanticLabel =
        '${formatMonth(item.month)}. '
        'Pemasukan ${formatRupiah(item.income)}. '
        'Pengeluaran ${formatRupiah(item.expense)}. '
        'Selisih ${formatRupiah(item.net)}.';

    return Semantics(
      key: ValueKey('summary-month-semantics-$monthKey'),
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Card(
          key: ValueKey('summary-month-$monthKey'),
          color: highlighted
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: highlighted
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFFE4E7DE),
              width: highlighted ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatMonth(item.month),
                        key: ValueKey('summary-month-title-$monthKey'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (highlighted)
                      Icon(
                        Icons.radio_button_checked,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scaledBodySize = MediaQuery.textScalerOf(context)
                        .scale(14);
                    final stacked =
                        constraints.maxWidth < 360 || scaledBodySize > 20;
                    final donut = _MonthlySummaryDonut(
                      monthKey: monthKey,
                      income: item.income,
                      expense: item.expense,
                    );
                    final metrics = _MonthlySummaryMetrics(
                      monthKey: monthKey,
                      income: item.income,
                      expense: item.expense,
                      net: item.net,
                    );

                    if (stacked) {
                      return Column(
                        children: [
                          Align(child: donut),
                          const SizedBox(height: 16),
                          metrics,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        donut,
                        const SizedBox(width: 20),
                        Expanded(child: metrics),
                      ],
                    );
                  },
                ),
                if (empty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Belum ada pemasukan atau pengeluaran.',
                    key: ValueKey('summary-month-empty-$monthKey'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthlySummaryDonut extends StatelessWidget {
  const _MonthlySummaryDonut({
    required this.monthKey,
    required this.income,
    required this.expense,
  });

  final String monthKey;
  final int income;
  final int expense;

  @override
  Widget build(BuildContext context) {
    final empty = income == 0 && expense == 0;
    return CustomPaint(
      key: ValueKey('summary-month-donut-$monthKey'),
      painter: _SummaryDonutPainter(
        income: income,
        expense: expense,
        incomeColor: _incomeColor,
        expenseColor: _expenseColor,
        emptyColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        holeColor: highlightedCardColor(context),
      ),
      child: SizedBox.square(
        dimension: 92,
        child: empty
            ? Center(
                child: Icon(
                  Icons.horizontal_rule,
                  color: Theme.of(context).colorScheme.outline,
                ),
              )
            : null,
      ),
    );
  }

  Color highlightedCardColor(BuildContext context) {
    final card = context.findAncestorWidgetOfExactType<Card>();
    return card?.color ?? Theme.of(context).cardColor;
  }
}

class _MonthlySummaryMetrics extends StatelessWidget {
  const _MonthlySummaryMetrics({
    required this.monthKey,
    required this.income,
    required this.expense,
    required this.net,
  });

  final String monthKey;
  final int income;
  final int expense;
  final int net;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SummaryMetricRow(
        rowKey: ValueKey('summary-month-income-$monthKey'),
        label: 'Pemasukan',
        amount: income,
        color: _incomeColor,
      ),
      const SizedBox(height: 7),
      _SummaryMetricRow(
        rowKey: ValueKey('summary-month-expense-$monthKey'),
        label: 'Pengeluaran',
        amount: expense,
        color: _expenseColor,
      ),
      const Divider(height: 17),
      _SummaryMetricRow(
        rowKey: ValueKey('summary-month-net-$monthKey'),
        label: 'Selisih',
        amount: net,
        color: net > 0
            ? _incomeColor
            : net < 0
            ? _expenseColor
            : Theme.of(context).colorScheme.onSurfaceVariant,
        emphasized: true,
      ),
    ],
  );
}

class _SummaryMetricRow extends StatelessWidget {
  const _SummaryMetricRow({
    required this.rowKey,
    required this.label,
    required this.amount,
    required this.color,
    this.emphasized = false,
  });

  final Key rowKey;
  final String label;
  final int amount;
  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: color,
      fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
    );
    return Row(
      key: rowKey,
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? const TextStyle(fontWeight: FontWeight.w700)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              formatRupiah(amount),
              key: ValueKey('${(rowKey as ValueKey<String>).value}-value'),
              maxLines: 1,
              style: style,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryDonutPainter extends CustomPainter {
  const _SummaryDonutPainter({
    required this.income,
    required this.expense,
    required this.incomeColor,
    required this.expenseColor,
    required this.emptyColor,
    required this.holeColor,
  });

  final int income;
  final int expense;
  final Color incomeColor;
  final Color expenseColor;
  final Color emptyColor;
  final Color holeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final total = income + expense;
    final paint = Paint();

    if (total == 0) {
      canvas.drawCircle(center, radius, paint..color = emptyColor);
    } else {
      const start = -math.pi / 2;
      final incomeSweep = math.pi * 2 * income / total;
      if (income > 0) {
        canvas.drawArc(
          rect,
          start,
          incomeSweep,
          true,
          paint..color = incomeColor,
        );
      }
      if (expense > 0) {
        canvas.drawArc(
          rect,
          start + incomeSweep,
          math.pi * 2 - incomeSweep,
          true,
          paint..color = expenseColor,
        );
      }
    }

    canvas.drawCircle(center, radius * .55, Paint()..color = holeColor);
  }

  @override
  bool shouldRepaint(covariant _SummaryDonutPainter oldDelegate) =>
      income != oldDelegate.income ||
      expense != oldDelegate.expense ||
      incomeColor != oldDelegate.incomeColor ||
      expenseColor != oldDelegate.expenseColor ||
      emptyColor != oldDelegate.emptyColor ||
      holeColor != oldDelegate.holeColor;
}

class _SummaryEmptyState extends StatelessWidget {
  const _SummaryEmptyState();

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('summary-empty-state'),
    padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
    children: [
      Icon(
        Icons.donut_large_outlined,
        size: 56,
        color: Theme.of(context).colorScheme.outline,
      ),
      const SizedBox(height: 16),
      Text(
        'Belum ada ringkasan untuk tahun ini',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Pemasukan dan pengeluaran yang dicatat akan tampil di sini.',
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _SummaryLoadError extends StatelessWidget {
  const _SummaryLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          const Text(
            'Ringkasan belum dapat dimuat. Data di perangkat tidak diubah.',
            key: Key('summary-load-error'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            key: const Key('summary-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    ),
  );
}

bool _sameMonth(DateTime left, DateTime? right) =>
    right != null && left.year == right.year && left.month == right.month;

String _monthKey(DateTime month) =>
    '${month.year}-${month.month.toString().padLeft(2, '0')}';
