import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/app/providers.dart';
import 'package:waras_arta/app/router.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/domain/finance_repository.dart';
import 'package:waras_arta/features/calendar/view_models/calendar_view_model.dart';

void main() {
  late _CalendarRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _CalendarRepository();
    container = ProviderContainer(
      overrides: [
        currentDateProvider.overrideWithValue(DateTime(2024, 3, 15, 18)),
        financeRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
  });

  test('calendar grid starts on Monday and supports leap February', () {
    expect(calendarLeadingBlankCount(DateTime(2024, 1)), 0);
    expect(calendarLeadingBlankCount(DateTime(2024, 2)), 3);
    expect(daysInCalendarMonth(DateTime(2024, 2)), 29);
    expect(daysInCalendarMonth(DateTime(2023, 2)), 28);
  });

  test('starts today and clamps the selected day while moving months', () {
    expect(
      container.read(calendarStateProvider).displayedMonth,
      DateTime(2024, 3),
    );
    expect(
      container.read(calendarStateProvider).selectedDay,
      DateTime(2024, 3, 15),
    );

    final model = container.read(calendarStateProvider.notifier);
    model.showMonth(DateTime(2024, 1, 31));
    model.moveMonth(1);
    expect(
      container.read(calendarStateProvider).displayedMonth,
      DateTime(2024, 2),
    );
    expect(
      container.read(calendarStateProvider).selectedDay,
      DateTime(2024, 2, 29),
    );
  });

  test('keeps navigation inside January 2000 and the current month', () {
    final model = container.read(calendarStateProvider.notifier);
    model.showMonth(DateTime(1998, 6, 20));
    expect(
      container.read(calendarStateProvider).displayedMonth,
      DateTime(2000),
    );
    expect(
      container.read(calendarStateProvider).selectedDay,
      DateTime(2000, 1, 20),
    );
    model.moveMonth(-1);
    expect(
      container.read(calendarStateProvider).displayedMonth,
      DateTime(2000),
    );

    model.showMonth(DateTime(2030, 7, 30));
    expect(
      container.read(calendarStateProvider).displayedMonth,
      DateTime(2024, 3),
    );
    expect(
      container.read(calendarStateProvider).selectedDay,
      DateTime(2024, 3, 15),
    );
    model.moveMonth(1);
    expect(
      container.read(calendarStateProvider).displayedMonth,
      DateTime(2024, 3),
    );
  });

  test('ignores future and off-month day selections', () {
    final model = container.read(calendarStateProvider.notifier);
    model.selectDay(DateTime(2024, 3, 10));
    expect(
      container.read(calendarStateProvider).selectedDay,
      DateTime(2024, 3, 10),
    );
    model.selectDay(DateTime(2024, 3, 16));
    model.selectDay(DateTime(2024, 2, 10));
    expect(
      container.read(calendarStateProvider).selectedDay,
      DateTime(2024, 3, 10),
    );
  });

  test('refreshes a followed today across a month boundary', () {
    final rollingContainer = ProviderContainer(
      overrides: [
        currentDateProvider.overrideWithValue(DateTime(2024, 1, 31, 23, 55)),
      ],
    );
    addTearDown(rollingContainer.dispose);
    final model = rollingContainer.read(calendarStateProvider.notifier);

    expect(
      rollingContainer.read(calendarStateProvider).selectedDay,
      DateTime(2024, 1, 31),
    );
    model.refreshToday(today: DateTime(2024, 2, 1, 0, 1));

    final refreshed = rollingContainer.read(calendarStateProvider);
    expect(refreshed.displayedMonth, DateTime(2024, 2));
    expect(refreshed.selectedDay, DateTime(2024, 2, 1));
    expect(refreshed.followsToday, isTrue);

    model.showMonth(DateTime(2024, 1, 15));
    model.refreshToday(today: DateTime(2024, 2, 2));
    final browsingPast = rollingContainer.read(calendarStateProvider);
    expect(browsingPast.displayedMonth, DateTime(2024, 1));
    expect(browsingPast.selectedDay, DateTime(2024, 1, 15));
    expect(browsingPast.followsToday, isFalse);
  });

  test('resumes following today when month navigation lands on today', () {
    final model = container.read(calendarStateProvider.notifier);
    model.showMonth(DateTime(2024, 2, 15));
    expect(container.read(calendarStateProvider).followsToday, isFalse);

    model.moveMonth(1);
    final returnedToToday = container.read(calendarStateProvider);
    expect(returnedToToday.selectedDay, DateTime(2024, 3, 15));
    expect(returnedToToday.followsToday, isTrue);

    model.refreshToday(today: DateTime(2024, 3, 16));
    final nextDay = container.read(calendarStateProvider);
    expect(nextDay.displayedMonth, DateTime(2024, 3));
    expect(nextDay.selectedDay, DateTime(2024, 3, 16));
    expect(nextDay.followsToday, isTrue);
  });

  test(
    'calendar providers query the displayed month and selected day',
    () async {
      final model = container.read(calendarStateProvider.notifier);
      model.showMonth(DateTime(2024, 2, 14));
      final monthSubscription = container.listen(
        calendarMonthProvider,
        (_, _) {},
      );
      final daySubscription = container.listen(
        selectedCalendarDayEntriesProvider,
        (_, _) {},
      );
      addTearDown(monthSubscription.close);
      addTearDown(daySubscription.close);

      await container.read(calendarMonthProvider.future);
      await container.read(selectedCalendarDayEntriesProvider.future);
      expect(repository.lastMonth, DateTime(2024, 2));
      expect(repository.lastDay, DateTime(2024, 2, 14));
    },
  );

  test('transaction date query accepts only supported civil dates', () {
    final today = DateTime(2024, 3, 15);
    expect(
      parseTransactionDateQuery('2024-02-29', today: today),
      DateTime(2024, 2, 29),
    );
    expect(parseTransactionDateQuery('2024-2-09', today: today), isNull);
    expect(parseTransactionDateQuery('2023-02-29', today: today), isNull);
    expect(parseTransactionDateQuery('1999-12-31', today: today), isNull);
    expect(parseTransactionDateQuery('2024-03-16', today: today), isNull);
  });
}

class _CalendarRepository implements FinanceRepository {
  DateTime? lastMonth;
  DateTime? lastDay;

  @override
  Stream<CalendarMonthSnapshot> watchCalendarMonth(DateTime month) {
    lastMonth = month;
    return Stream.value(CalendarMonthSnapshot(month: month, days: const []));
  }

  @override
  Stream<List<FinanceEntry>> watchDay(DateTime day) {
    lastDay = day;
    return Stream.value(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
