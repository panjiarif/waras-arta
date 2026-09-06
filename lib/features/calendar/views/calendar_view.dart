import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/category_icons.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../../ledger/view_models/ledger_view_model.dart';
import '../../ledger/views/form_widgets.dart';
import '../view_models/calendar_view_model.dart';

const _calendarOtherColor = Color(0xFF526F9E);

class CalendarView extends ConsumerWidget {
  const CalendarView({super.key, required this.accountNames});

  final Map<int, String> accountNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarStateProvider);
    final month = ref.watch(calendarMonthProvider);
    final entries = ref.watch(selectedCalendarDayEntriesProvider);

    return ListView(
      key: const PageStorageKey('calendar-tab'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
      children: [
        const Text(
          'Kalender keuangan',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Pilih tanggal untuk melihat seluruh catatan pada hari itu.',
        ),
        const SizedBox(height: 20),
        _CalendarMonthSelector(state: state),
        const SizedBox(height: 12),
        month.when(
          skipLoadingOnReload: false,
          data: (snapshot) => _MonthGrid(
            snapshot: snapshot,
            state: state,
            today: dateOnly(ref.watch(currentDateProvider)),
            onSelected: ref.read(calendarStateProvider.notifier).selectDay,
          ),
          loading: () => const Card(
            child: SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, _) => Column(
            children: [
              const FormMessage(
                'Aktivitas kalender belum dapat dimuat.',
                isError: true,
              ),
              TextButton.icon(
                onPressed: () => ref.invalidate(calendarMonthProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          formatDate(state.selectedDay),
          key: const Key('calendar-selected-date'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        month.when(
          data: (snapshot) =>
              _DayTotals(summary: snapshot.summaryForDay(state.selectedDay)),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 20),
        entries.when(
          skipLoadingOnReload: false,
          data: (items) =>
              _DayEntries(entries: items, accountNames: accountNames),
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Column(
            children: [
              const FormMessage(
                'Catatan pada tanggal ini belum dapat dimuat.',
                isError: true,
              ),
              TextButton.icon(
                onPressed: () =>
                    ref.invalidate(selectedCalendarDayEntriesProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalendarMonthSelector extends ConsumerWidget {
  const _CalendarMonthSelector({required this.state});

  final CalendarState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateOnly(ref.watch(currentDateProvider));
    final currentMonth = DateTime(today.year, today.month);
    return Row(
      children: [
        IconButton(
          key: const Key('calendar-previous-month'),
          tooltip: 'Bulan sebelumnya',
          onPressed: state.displayedMonth.isAfter(calendarFirstMonth)
              ? () => ref.read(calendarStateProvider.notifier).moveMonth(-1)
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            formatMonth(state.displayedMonth),
            key: const Key('calendar-month-label'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          key: const Key('calendar-next-month'),
          tooltip: 'Bulan berikutnya',
          onPressed: state.displayedMonth.isBefore(currentMonth)
              ? () => ref.read(calendarStateProvider.notifier).moveMonth(1)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.snapshot,
    required this.state,
    required this.today,
    required this.onSelected,
  });

  final CalendarMonthSnapshot snapshot;
  final CalendarState state;
  final DateTime today;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final leading = calendarLeadingBlankCount(state.displayedMonth);
    final dayCount = daysInCalendarMonth(state.displayedMonth);
    final itemCount = ((leading + dayCount + 6) ~/ 7) * 7;
    const weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
        child: Column(
          children: [
            Row(
              children: [
                for (final weekday in weekdays)
                  Expanded(
                    child: Text(
                      weekday,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final geometryScale = MediaQuery.textScalerOf(context)
                    .scale(1)
                    .clamp(1.0, 1.4);
                final baseAspect = constraints.maxWidth < 420 ? .72 : 1.05;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  childAspectRatio: baseAspect / geometryScale,
                  children: List.generate(itemCount, (index) {
                    final number = index - leading + 1;
                    if (number < 1 || number > dayCount) {
                      return const SizedBox.shrink();
                    }
                    final day = DateTime(
                      state.displayedMonth.year,
                      state.displayedMonth.month,
                      number,
                    );
                    return _DayCell(
                      day: day,
                      summary: snapshot.summaryForDay(day),
                      selected: _sameDay(day, state.selectedDay),
                      today: _sameDay(day, today),
                      enabled: !day.isAfter(today),
                      onTap: () => onSelected(day),
                    );
                  }),
                );
              },
            ),
            const SizedBox(height: 10),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                _ActivityLegend(color: forest, label: 'Masuk'),
                _ActivityLegend(color: Color(0xFF9D492B), label: 'Keluar'),
                _ActivityLegend(color: _calendarOtherColor, label: 'Lainnya'),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Lainnya: transfer atau penyesuaian saldo',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.summary,
    required this.selected,
    required this.today,
    required this.enabled,
    required this.onTap,
  });

  final DateTime day;
  final CalendarDaySummary? summary;
  final bool selected;
  final bool today;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activity = <String>[
      if ((summary?.income ?? 0) > 0) 'pemasukan',
      if ((summary?.expense ?? 0) > 0) 'pengeluaran',
      if ((summary?.transferCount ?? 0) > 0 ||
          (summary?.adjustmentCount ?? 0) > 0)
        'transfer atau penyesuaian',
    ];
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: [
          formatDate(day),
          if (today) 'hari ini',
          if (activity.isNotEmpty) activity.join(', '),
        ].join(', '),
        child: Material(
          color: selected
              ? colors.primaryContainer
              : today
              ? colors.surfaceContainerHighest
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: today && !selected
                ? BorderSide(color: colors.primary)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('calendar-day-${civilDate(day)}'),
            onTap: enabled ? onTap : null,
            child: Opacity(
              opacity: enabled ? 1 : .38,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${day.day}',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontWeight: selected || today
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 6,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if ((summary?.income ?? 0) > 0)
                            const _ActivityDot(color: forest),
                          if ((summary?.expense ?? 0) > 0)
                            const _ActivityDot(color: Color(0xFF9D492B)),
                          if ((summary?.transferCount ?? 0) > 0 ||
                              (summary?.adjustmentCount ?? 0) > 0)
                            const _ActivityDot(color: _calendarOtherColor),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityDot extends StatelessWidget {
  const _ActivityDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 5,
    height: 5,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _ActivityLegend extends StatelessWidget {
  const _ActivityLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _ActivityDot(color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class _DayTotals extends StatelessWidget {
  const _DayTotals({required this.summary});

  final CalendarDaySummary? summary;

  @override
  Widget build(BuildContext context) {
    final value = summary;
    final income = value?.income ?? 0;
    final expense = value?.expense ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final incomeCard = _DayMetric(
              label: 'Pemasukan',
              value: income,
              color: forest,
            );
            final expenseCard = _DayMetric(
              label: 'Pengeluaran',
              value: expense,
              color: const Color(0xFF9D492B),
            );
            if (constraints.maxWidth < 350) {
              return Column(
                children: [incomeCard, const SizedBox(height: 10), expenseCard],
              );
            }
            return Row(
              children: [
                Expanded(child: incomeCard),
                const SizedBox(width: 10),
                Expanded(child: expenseCard),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          [
            '${value?.entryCount ?? 0} catatan',
            '${value?.transferCount ?? 0} transfer',
            '${value?.adjustmentCount ?? 0} penyesuaian',
          ].join(' • '),
          key: const Key('calendar-day-counts'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DayMetric extends StatelessWidget {
  const _DayMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            formatRupiah(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _DayEntries extends StatelessWidget {
  const _DayEntries({required this.entries, required this.accountNames});

  final List<FinanceEntry> entries;
  final Map<int, String> accountNames;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const FormMessage(
        'Belum ada catatan pada tanggal ini. Gunakan tombol tambah untuk mencatatnya.',
      );
    }
    return Column(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          _CalendarEntryCard(entry: entries[index], accountNames: accountNames),
          if (index != entries.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CalendarEntryCard extends ConsumerWidget {
  const _CalendarEntryCard({required this.entry, required this.accountNames});

  final FinanceEntry entry;
  final Map<int, String> accountNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final negative =
        entry.kind == EntryKind.expense ||
        (entry.kind == EntryKind.adjustment && entry.amount < 0);
    final color = negative ? const Color(0xFF9D492B) : forest;
    final prefix = switch (entry.kind) {
      EntryKind.income => '+ ',
      EntryKind.expense => '− ',
      EntryKind.adjustment when entry.amount > 0 => '+ ',
      _ => '',
    };
    final accountRoute = entry.kind == EntryKind.transfer
        ? '${accountNames[entry.accountId] ?? 'Rekening'} → '
              '${accountNames[entry.destinationAccountId] ?? 'Rekening'}'
        : accountNames[entry.accountId] ?? 'Rekening';
    final icon = entry.categoryIconKey != null
        ? categoryIconFor(entry.categoryIconKey!)
        : switch (entry.kind) {
            EntryKind.income => Icons.south_west,
            EntryKind.expense => Icons.north_east,
            EntryKind.transfer => Icons.swap_horiz,
            EntryKind.adjustment => Icons.tune,
          };
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.categoryName ?? entry.kind.label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        Text(accountRoute, style: const TextStyle(fontSize: 13)),
        if (entry.parentCategoryName != null)
          Text(entry.parentCategoryName!, style: const TextStyle(fontSize: 12)),
        if (entry.note.isNotEmpty && entry.note != 'Saldo awal') ...[
          const SizedBox(height: 4),
          Text(entry.note),
        ],
      ],
    );
    final amountLabel = '$prefix${formatRupiah(entry.amount)}';
    final amountStyle = TextStyle(color: color, fontWeight: FontWeight.w700);
    return Card(
      child: InkWell(
        key: ValueKey('calendar-entry-${entry.id}'),
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          ref.read(financeActionsProvider.notifier).clearError();
          context.push('/transactions/${entry.id}');
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 360 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.4;
              final identity = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 14),
                  Expanded(child: details),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          amountLabel,
                          maxLines: 1,
                          softWrap: false,
                          style: amountStyle,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      amountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: amountStyle,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

bool _sameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
