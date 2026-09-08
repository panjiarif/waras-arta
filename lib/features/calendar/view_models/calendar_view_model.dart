import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';

final currentDateProvider = Provider<DateTime>((ref) {
  return dateOnly(DateTime.now());
});

class CalendarState {
  const CalendarState({
    required this.displayedMonth,
    required this.selectedDay,
    required this.followsToday,
  });

  final DateTime displayedMonth;
  final DateTime selectedDay;
  final bool followsToday;
}

final calendarStateProvider =
    NotifierProvider<CalendarViewModel, CalendarState>(CalendarViewModel.new);

class CalendarViewModel extends Notifier<CalendarState> {
  DateTime get _today => dateOnly(ref.read(currentDateProvider));

  @override
  CalendarState build() {
    final today = dateOnly(ref.read(currentDateProvider));
    return CalendarState(
      displayedMonth: DateTime(today.year, today.month),
      selectedDay: today,
      followsToday: true,
    );
  }

  void moveMonth(int delta) {
    final target = DateTime(
      state.displayedMonth.year,
      state.displayedMonth.month + delta,
    );
    final lastMonth = DateTime(_today.year, _today.month);
    if (target.isBefore(calendarFirstMonth) || target.isAfter(lastMonth)) {
      return;
    }

    final requestedDay = state.selectedDay.day;
    final lastDay = daysInCalendarMonth(target);
    var selected = DateTime(
      target.year,
      target.month,
      requestedDay.clamp(1, lastDay),
    );
    if (selected.isAfter(_today)) selected = _today;
    state = CalendarState(
      displayedMonth: target,
      selectedDay: selected,
      followsToday: _sameCalendarDay(selected, _today),
    );
  }

  void showMonth(DateTime value) {
    final requested = DateTime(value.year, value.month);
    final lastMonth = DateTime(_today.year, _today.month);
    final target = requested.isBefore(calendarFirstMonth)
        ? calendarFirstMonth
        : requested.isAfter(lastMonth)
        ? lastMonth
        : requested;
    final lastDay = daysInCalendarMonth(target);
    var selected = DateTime(
      target.year,
      target.month,
      value.day.clamp(1, lastDay),
    );
    if (selected.isAfter(_today)) selected = _today;
    state = CalendarState(
      displayedMonth: target,
      selectedDay: selected,
      followsToday: _sameCalendarDay(selected, _today),
    );
  }

  void selectDay(DateTime value) {
    final day = dateOnly(value);
    if (day.isBefore(calendarFirstDay) || day.isAfter(_today)) return;
    if (day.year != state.displayedMonth.year ||
        day.month != state.displayedMonth.month) {
      return;
    }
    state = CalendarState(
      displayedMonth: state.displayedMonth,
      selectedDay: day,
      followsToday: _sameCalendarDay(day, _today),
    );
  }

  void refreshToday({DateTime? today}) {
    final currentDay = dateOnly(today ?? _today);
    final currentMonth = DateTime(currentDay.year, currentDay.month);
    if (state.followsToday) {
      if (_sameCalendarDay(state.selectedDay, currentDay)) return;
      state = CalendarState(
        displayedMonth: currentMonth,
        selectedDay: currentDay,
        followsToday: true,
      );
      return;
    }

    if (state.displayedMonth.isAfter(currentMonth) ||
        state.selectedDay.isAfter(currentDay)) {
      state = CalendarState(
        displayedMonth: currentMonth,
        selectedDay: currentDay,
        followsToday: true,
      );
    }
  }
}

final calendarMonthProvider = StreamProvider.autoDispose<CalendarMonthSnapshot>(
  (ref) {
    final month = ref.watch(
      calendarStateProvider.select((value) => value.displayedMonth),
    );
    return ref.watch(financeRepositoryProvider).watchCalendarMonth(month);
  },
);

final selectedCalendarDayEntriesProvider =
    StreamProvider.autoDispose<List<FinanceEntry>>((ref) {
      final day = ref.watch(
        calendarStateProvider.select((value) => value.selectedDay),
      );
      return ref.watch(financeRepositoryProvider).watchDay(day);
    });

final calendarFirstMonth = DateTime(2000);
final calendarFirstDay = DateTime(2000);

int daysInCalendarMonth(DateTime month) {
  return DateTime(month.year, month.month + 1, 0).day;
}

int calendarLeadingBlankCount(DateTime month) {
  return (DateTime(month.year, month.month).weekday - DateTime.monday) % 7;
}

String civilDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

bool _sameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
