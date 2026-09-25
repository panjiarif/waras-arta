import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';

const _expenseColor = Color(0xFF9D492B);

/// Recent trends shown on the Overview screen.
///
/// These charts intentionally follow [OverviewChartsSnapshot.today], not the
/// month selected by the ledger filter.
class OverviewChartsSection extends StatelessWidget {
  const OverviewChartsSection({super.key, required this.snapshot});

  final OverviewChartsSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('overview-charts-section'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Tren terkini',
        key: Key('overview-charts-heading'),
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        'Mengikuti tanggal hari ini, terpisah dari bulan yang dipilih.',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      ),
      const SizedBox(height: 12),
      _WeeklyExpenseCard(points: snapshot.dailyExpenses),
      const SizedBox(height: 12),
      _PrimaryBalanceTrendCard(points: snapshot.balancePoints),
    ],
  );
}

class _WeeklyExpenseCard extends StatelessWidget {
  const _WeeklyExpenseCard({required this.points});

  final List<DailyExpenseTotal> points;

  @override
  Widget build(BuildContext context) {
    final total = points.fold<int>(0, (sum, point) => sum + point.expense);
    final range = points.isEmpty
        ? 'Rentang tanggal belum tersedia'
        : '${_formatCompactDateRange(points.first.day, points.last.day)} · hari ini di kanan';

    return Semantics(
      key: const Key('weekly-expense-chart-card-semantics'),
      container: true,
      explicitChildNodes: true,
      label: 'Pengeluaran 7 hari terakhir. Total ${formatRupiah(total)}.',
      child: SizedBox(
        width: double.infinity,
        child: Card(
          key: const Key('weekly-expense-chart-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: Text(
                    'Pengeluaran 7 Hari Terakhir',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),
                ExcludeSemantics(
                  child: Text(
                    range,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ExcludeSemantics(
                  child: Text(
                    'Total pengeluaran',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 2),
                ExcludeSemantics(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatRupiah(total),
                        key: const Key('weekly-expense-total'),
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: _expenseColor,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                RepaintBoundary(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      key: const Key('weekly-expense-bars'),
                      painter: _ExpenseBarsPainter(
                        values: points
                            .map((point) => math.max(0, point.expense))
                            .toList(growable: false),
                        barColor: _expenseColor,
                        gridColor: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      child: const SizedBox(height: 132),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _ExpenseLabels(points: points),
                if (points.isEmpty || total == 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    points.isEmpty
                        ? 'Data pengeluaran belum tersedia.'
                        : 'Belum ada pengeluaran dalam 7 hari terakhir.',
                    key: const Key('weekly-expense-empty'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
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

class _ExpenseLabels extends StatelessWidget {
  const _ExpenseLabels({required this.points});

  final List<DailyExpenseTotal> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var index = 0; index < points.length; index++)
          Expanded(
            child: Semantics(
              key: ValueKey('expense-bar-semantics-$index'),
              container: true,
              label:
                  '${formatDate(points[index].day)}, pengeluaran ${formatRupiah(points[index].expense)}',
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    DateFormat('d', 'id_ID').format(points[index].day),
                    key: ValueKey('expense-day-label-$index'),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PrimaryBalanceTrendCard extends StatelessWidget {
  const _PrimaryBalanceTrendCard({required this.points});

  final List<PrimaryBalancePoint> points;

  @override
  Widget build(BuildContext context) {
    final current = _currentPoint(points);

    return Semantics(
      key: const Key('primary-balance-chart-card-semantics'),
      container: true,
      explicitChildNodes: true,
      label:
          'Tren saldo utama. Enam saldo akhir bulan sebelumnya dan saldo saat ini${current == null ? '.' : ', ${formatRupiah(current.balance)}.'}',
      child: SizedBox(
        width: double.infinity,
        child: Card(
          key: const Key('primary-balance-chart-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: Text(
                    'Tren Saldo Utama',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),
                ExcludeSemantics(
                  child: Text(
                    'Enam saldo akhir bulan sebelumnya dan saldo saat ini.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ExcludeSemantics(
                  child: Text(
                    'Saldo saat ini',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 2),
                ExcludeSemantics(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        current == null
                            ? 'Belum tersedia'
                            : formatRupiah(current.balance),
                        key: const Key('primary-balance-current'),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: current != null && current.balance < 0
                              ? _expenseColor
                              : forest,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                RepaintBoundary(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      key: const Key('primary-balance-line'),
                      painter: _BalanceLinePainter(
                        values: points
                            .map((point) => point.balance)
                            .toList(growable: false),
                        lineColor: forest,
                        gridColor: Theme.of(context).colorScheme.outlineVariant,
                        zeroColor: Theme.of(context).colorScheme.outline,
                      ),
                      child: const SizedBox(height: 144),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _BalanceLabels(points: points),
                if (points.isEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Data saldo utama belum tersedia.',
                    key: const Key('primary-balance-empty'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
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

class _BalanceLabels extends StatelessWidget {
  const _BalanceLabels({required this.points});

  final List<PrimaryBalancePoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var index = 0; index < points.length; index++)
          Expanded(
            child: Semantics(
              key: ValueKey('balance-point-semantics-$index'),
              container: true,
              label:
                  '${points[index].isCurrent ? 'Saat ini, ${formatDate(points[index].day)}' : 'Akhir ${formatMonth(points[index].day)}'}, saldo utama ${formatRupiah(points[index].balance)}',
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    points[index].isCurrent
                        ? 'Kini'
                        : DateFormat('MMM', 'id_ID').format(points[index].day),
                    key: ValueKey('balance-point-label-$index'),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: points[index].isCurrent
                          ? forest
                          : Theme.of(context).colorScheme.outline,
                      fontWeight: points[index].isCurrent
                          ? FontWeight.w700
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

PrimaryBalancePoint? _currentPoint(List<PrimaryBalancePoint> points) {
  for (final point in points.reversed) {
    if (point.isCurrent) return point;
  }
  return points.isEmpty ? null : points.last;
}

String _formatCompactDateRange(DateTime start, DateTime end) {
  final startMonth = DateFormat('MMM', 'id_ID').format(start);
  final endMonth = DateFormat('MMM', 'id_ID').format(end);
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}–${end.day} $endMonth ${end.year}';
  }
  if (start.year == end.year) {
    return '${start.day} $startMonth–${end.day} $endMonth ${end.year}';
  }
  return '${start.day} $startMonth ${start.year}–${end.day} $endMonth ${end.year}';
}

class _ExpenseBarsPainter extends CustomPainter {
  const _ExpenseBarsPainter({
    required this.values,
    required this.barColor,
    required this.gridColor,
  });

  final List<int> values;
  final Color barColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    final count = values.length;
    final maxValue = values.fold<int>(0, math.max);
    final slotWidth = size.width / count;
    final barWidth = math.min(24.0, slotWidth * .56);
    final baseline = size.height - 1;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var step = 0; step <= 2; step++) {
      final y = baseline * step / 2;
      canvas.drawLine(
        Offset.zero.translate(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final radius = Radius.circular(math.min(5, barWidth / 2));
    for (var index = 0; index < count; index++) {
      final value = math.max(0, values[index]);
      final normalized = maxValue == 0 ? 0.0 : value / maxValue;
      final height = value == 0 ? 3.0 : math.max(5.0, normalized * baseline);
      final left = slotWidth * index + (slotWidth - barWidth) / 2;
      final rect = Rect.fromLTWH(left, baseline - height, barWidth, height);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius),
        Paint()
          ..color = value == 0 ? barColor.withValues(alpha: .22) : barColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExpenseBarsPainter oldDelegate) =>
      !_sameValues(values, oldDelegate.values) ||
      barColor != oldDelegate.barColor ||
      gridColor != oldDelegate.gridColor;
}

class _BalanceLinePainter extends CustomPainter {
  const _BalanceLinePainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.zeroColor,
  });

  final List<int> values;
  final Color lineColor;
  final Color gridColor;
  final Color zeroColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    const horizontalInset = 7.0;
    const verticalInset = 7.0;
    final plotWidth = math.max(0.0, size.width - horizontalInset * 2);
    final plotHeight = math.max(0.0, size.height - verticalInset * 2);
    var low = math.min(0, values.reduce(math.min)).toDouble();
    var high = math.max(0, values.reduce(math.max)).toDouble();

    if (low == high) {
      low -= 1;
      high += 1;
    } else {
      final padding = (high - low) * .08;
      if (low < 0) low -= padding;
      if (high > 0) high += padding;
    }

    double yFor(num value) =>
        verticalInset + (high - value) / (high - low) * plotHeight;
    double xFor(int index) => values.length == 1
        ? size.width / 2
        : horizontalInset + plotWidth * index / (values.length - 1);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var step = 0; step <= 2; step++) {
      final y = verticalInset + plotHeight * step / 2;
      canvas.drawLine(
        Offset(horizontalInset, y),
        Offset(size.width - horizontalInset, y),
        gridPaint,
      );
    }

    final zeroY = yFor(0).clamp(verticalInset, size.height - verticalInset);
    canvas.drawLine(
      Offset(horizontalInset, zeroY),
      Offset(size.width - horizontalInset, zeroY),
      Paint()
        ..color = zeroColor
        ..strokeWidth = 1.25,
    );

    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final point = Offset(xFor(index), yFor(values[index]));
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var index = 0; index < values.length; index++) {
      final point = Offset(xFor(index), yFor(values[index]));
      canvas
        ..drawCircle(point, 4.25, Paint()..color = Colors.white)
        ..drawCircle(point, 3, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _BalanceLinePainter oldDelegate) =>
      !_sameValues(values, oldDelegate.values) ||
      lineColor != oldDelegate.lineColor ||
      gridColor != oldDelegate.gridColor ||
      zeroColor != oldDelegate.zeroColor;
}

bool _sameValues(List<int> left, List<int> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
