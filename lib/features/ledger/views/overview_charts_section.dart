import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';

const _expenseColor = Color(0xFF9D492B);
const _expenseChartHeight = 156.0;
const _expenseChartTopInset = 28.0;
const _expenseValueLabelHeight = 22.0;
const _balanceChartHeight = 144.0;
const _balanceChartVerticalInset = 12.0;
const _balanceAxisGutter = 58.0;
const _balanceAxisLabelHeight = 20.0;

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
                    child: _ExpenseBarsChart(
                      values: points
                          .map((point) => math.max(0, point.expense))
                          .toList(growable: false),
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
                    child: _BalanceLineChart(
                      values: points
                          .map((point) => point.balance)
                          .toList(growable: false),
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
        const SizedBox(width: _balanceAxisGutter),
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

class _ExpenseBarsChart extends StatelessWidget {
  const _ExpenseBarsChart({required this.values});

  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final gridColor = Theme.of(context).colorScheme.outlineVariant;
    return SizedBox(
      key: const Key('weekly-expense-bars'),
      height: _expenseChartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (values.isEmpty || constraints.maxWidth <= 0) {
            return const SizedBox.shrink();
          }
          final maxValue = values.fold<int>(0, math.max);
          final slotWidth = constraints.maxWidth / values.length;
          final baseline = _expenseChartHeight - 1;
          final plotHeight = baseline - _expenseChartTopInset;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ExpenseBarsPainter(
                    values: values,
                    barColor: _expenseColor,
                    gridColor: gridColor,
                  ),
                ),
              ),
              for (var index = 0; index < values.length; index++)
                Positioned(
                  left: slotWidth * index,
                  top: math.max(
                    0,
                    baseline -
                        _expenseBarHeight(values[index], maxValue, plotHeight) -
                        _expenseValueLabelHeight -
                        3,
                  ),
                  width: slotWidth,
                  height: _expenseValueLabelHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatExactNumber(values[index]),
                        key: ValueKey('expense-value-label-$index'),
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _expenseColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BalanceLineChart extends StatelessWidget {
  const _BalanceLineChart({required this.values});

  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final scale = _BalanceScale.fromValues(values);
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('primary-balance-line'),
      height: _balanceChartHeight,
      child: values.isEmpty
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (context, constraints) => Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BalanceLinePainter(
                        values: values,
                        scale: scale,
                        lineColor: forest,
                        gridColor: colorScheme.outlineVariant,
                        zeroColor: colorScheme.outline,
                      ),
                    ),
                  ),
                  for (var index = 0; index < scale.axisTicks.length; index++)
                    Positioned(
                      right: 0,
                      top:
                          (scale.yFor(
                                    scale.axisTicks[index],
                                    _balanceChartHeight,
                                  ) -
                                  _balanceAxisLabelHeight / 2)
                              .clamp(
                                0,
                                _balanceChartHeight - _balanceAxisLabelHeight,
                              ),
                      width: _balanceAxisGutter - 4,
                      height: _balanceAxisLabelHeight,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatCompactAxisValue(scale.axisTicks[index]),
                            key: ValueKey('balance-axis-label-$index'),
                            maxLines: 1,
                            softWrap: false,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colorScheme.outline),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
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
    final plotHeight = math.max(0.0, baseline - _expenseChartTopInset);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var step = 0; step <= 2; step++) {
      final y = _expenseChartTopInset + plotHeight * step / 2;
      canvas.drawLine(
        Offset.zero.translate(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final radius = Radius.circular(math.min(5, barWidth / 2));
    for (var index = 0; index < count; index++) {
      final value = math.max(0, values[index]);
      final height = _expenseBarHeight(value, maxValue, plotHeight);
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
    required this.scale,
    required this.lineColor,
    required this.gridColor,
    required this.zeroColor,
  });

  final List<int> values;
  final _BalanceScale scale;
  final Color lineColor;
  final Color gridColor;
  final Color zeroColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    final plotWidth = math.max(0.0, size.width - _balanceAxisGutter);
    final slotWidth = plotWidth / values.length;
    double yFor(num value) => scale.yFor(value, size.height);
    double xFor(int index) => slotWidth * (index + .5);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final tick in scale.gridTicks) {
      final y = yFor(tick);
      canvas.drawLine(Offset(0, y), Offset(plotWidth, y), gridPaint);
    }

    final zeroY = yFor(0);
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(plotWidth, zeroY),
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
      scale != oldDelegate.scale ||
      lineColor != oldDelegate.lineColor ||
      gridColor != oldDelegate.gridColor ||
      zeroColor != oldDelegate.zeroColor;
}

class _BalanceScale {
  const _BalanceScale({required this.low, required this.high});

  factory _BalanceScale.fromValues(List<int> values) {
    if (values.isEmpty || values.every((value) => value == 0)) {
      return const _BalanceScale(low: -1, high: 1);
    }

    final minimum = values.reduce(math.min);
    final maximum = values.reduce(math.max);
    if (minimum < 0 && maximum > 0) {
      final magnitude = _niceMagnitude(
        math.max(minimum.abs(), maximum.abs()).toDouble(),
      );
      return _BalanceScale(low: -magnitude, high: magnitude);
    }
    if (maximum <= 0) {
      return _BalanceScale(
        low: -_niceMagnitude(minimum.abs().toDouble()),
        high: 0,
      );
    }
    return _BalanceScale(low: 0, high: _niceMagnitude(maximum.toDouble()));
  }

  final double low;
  final double high;

  bool get isAllZeroScale => low == -1 && high == 1;

  List<double> get gridTicks => [high, (high + low) / 2, low];

  List<double> get axisTicks =>
      isAllZeroScale ? const [0] : [high, (high + low) / 2, low];

  double yFor(num value, double height) {
    final plotHeight = math.max(0.0, height - _balanceChartVerticalInset * 2);
    return _balanceChartVerticalInset +
        (high - value) / (high - low) * plotHeight;
  }

  @override
  bool operator ==(Object other) =>
      other is _BalanceScale && low == other.low && high == other.high;

  @override
  int get hashCode => Object.hash(low, high);
}

double _expenseBarHeight(int value, int maxValue, double plotHeight) {
  if (value <= 0 || maxValue <= 0) return 3;
  return math.max(5.0, value / maxValue * plotHeight);
}

double _niceMagnitude(double value) {
  if (value <= 0 || !value.isFinite) return 1;
  final exponent = (math.log(value) / math.ln10).floor();
  final base = math.pow(10, exponent).toDouble();
  final normalized = value / base;
  const candidates = [1.0, 1.2, 1.5, 2.0, 2.4, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0];
  for (final candidate in candidates) {
    if (normalized <= candidate) return candidate * base;
  }
  return 10 * base;
}

String _formatExactNumber(int value) =>
    NumberFormat.decimalPattern('id_ID').format(value);

String _formatCompactAxisValue(num value) {
  if (value.abs() < .5) return '0';
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs().toDouble();
  if (absolute >= 1000000000) {
    return '$sign${_formatCompactDecimal(absolute / 1000000000)} M';
  }
  if (absolute >= 1000000) {
    return '$sign${_formatCompactDecimal(absolute / 1000000)} jt';
  }
  if (absolute >= 1000) {
    return '$sign${_formatCompactDecimal(absolute / 1000)}k';
  }
  return '$sign${_formatCompactDecimal(absolute)}';
}

String _formatCompactDecimal(double value) =>
    NumberFormat('0.#', 'id_ID').format(value);

bool _sameValues(List<int> left, List<int> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
