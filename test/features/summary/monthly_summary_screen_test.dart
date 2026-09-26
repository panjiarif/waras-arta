import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/theme.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/features/calendar/view_models/calendar_view_model.dart';
import 'package:waras_arta/features/summary/view_models/monthly_summary_view_model.dart';
import 'package:waras_arta/features/summary/views/monthly_summary_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'current year starts at current month and excludes future months',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpView(
        tester,
        snapshot: _snapshot(
          2026,
          overrides: {
            9: const _Totals(income: 3000000, expense: 2800000),
            8: const _Totals(income: 1200000, expense: 1500000),
          },
        ),
        today: DateTime(2026, 9, 25),
        highlightedMonth: DateTime(2026, 9),
        height: 1200,
      );

      expect(
        find.byKey(const ValueKey('summary-month-2026-09')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('summary-month-2026-10')), findsNothing);
      expect(find.text('September 2026'), findsOneWidget);
      expect(
        _keyedText(tester, 'summary-month-income-2026-09-value'),
        'Rp 3.000.000',
      );
      expect(
        _keyedText(tester, 'summary-month-expense-2026-09-value'),
        'Rp 2.800.000',
      );
      expect(
        _keyedText(tester, 'summary-month-net-2026-09-value'),
        'Rp 200.000',
      );
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('summary-month-semantics-2026-09')),
            )
            .label,
        allOf(
          contains('September 2026'),
          contains('Pemasukan Rp 3.000.000'),
          contains('Pengeluaran Rp 2.800.000'),
          contains('Selisih Rp 200.000'),
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets('past year exposes all twelve months in descending order', (
    tester,
  ) async {
    await _pumpView(
      tester,
      snapshot: _snapshot(2025),
      today: DateTime(2026, 9, 25),
      height: 700,
    );

    expect(find.text('Desember 2025'), findsOneWidget);
    expect(find.text('November 2025'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Desember 2025')).dy,
      lessThan(tester.getTopLeft(find.text('November 2025')).dy),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('summary-month-2025-01')),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Januari 2025'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero month uses a neutral donut and a clear empty message', (
    tester,
  ) async {
    await _pumpView(
      tester,
      snapshot: _snapshot(2026),
      today: DateTime(2026, 1, 10),
    );

    expect(
      find.byKey(const ValueKey('summary-month-donut-2026-01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('summary-month-empty-2026-01')),
      findsOneWidget,
    );
    expect(find.text('Belum ada pemasukan atau pengeluaran.'), findsOneWidget);
    expect(_keyedText(tester, 'summary-month-net-2026-01-value'), 'Rp 0');
  });

  testWidgets('empty snapshot has a dedicated state', (tester) async {
    await _pumpView(
      tester,
      snapshot: YearlySummarySnapshot(year: 2026, months: const []),
      today: DateTime(2026, 9, 25),
    );

    expect(find.byKey(const Key('summary-empty-state')), findsOneWidget);
    expect(find.text('Belum ada ringkasan untuk tahun ini'), findsOneWidget);
  });

  testWidgets('screen changes year and prevents navigation into the future', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentDateProvider.overrideWithValue(DateTime(2026, 9, 25)),
          yearlySummaryProvider.overrideWith(
            (ref, query) => Stream.value(_snapshot(query.year)),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MonthlySummaryScreen(initialMonth: DateTime(2026, 8)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('summary-next-year')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('summary-previous-year')));
    await tester.pumpAndSettle();

    expect(find.text('2025'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('summary-next-year')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'account filter drives the query, persists across years, and fits narrow text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requestedQueries = <YearlySummaryQuery>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentDateProvider.overrideWithValue(DateTime(2026, 9, 25)),
            yearlySummaryProvider.overrideWith((ref, query) {
              requestedQueries.add(query);
              final income = switch (query.balanceGroup) {
                null => 100000,
                AccountBalanceGroup.primary => 200000,
                AccountBalanceGroup.savingsInvestment => 300000,
              };
              return Stream.value(
                _snapshot(
                  query.year,
                  overrides: {9: _Totals(income: income, expense: 50000)},
                ),
              );
            }),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 900),
                textScaler: TextScaler.linear(2),
              ),
              child: MonthlySummaryScreen(initialMonth: DateTime(2026, 9)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rekening: Semua'), findsOneWidget);
      expect(find.byKey(const Key('summary-scope-caption')), findsNothing);
      expect(requestedQueries.last.balanceGroup, isNull);
      expect(find.text('Rp 100.000'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summary-account-filter')));
      await tester.pumpAndSettle();

      expect(find.text('Filter rekening'), findsOneWidget);
      expect(find.text('Semua rekening'), findsOneWidget);
      await tester.tap(find.byKey(const Key('summary-account-option-primary')));
      await tester.pumpAndSettle();

      expect(requestedQueries.last.balanceGroup, AccountBalanceGroup.primary);
      expect(find.text('Rp 200.000'), findsOneWidget);
      expect(find.text('Rekening: Saldo utama'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summary-account-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('summary-account-option-savingsInvestment')),
      );
      await tester.pumpAndSettle();

      expect(
        requestedQueries.last.balanceGroup,
        AccountBalanceGroup.savingsInvestment,
      );
      expect(find.text('Rp 300.000'), findsOneWidget);
      expect(find.text('Rekening: Simpanan & investasi'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summary-previous-year')));
      await tester.pumpAndSettle();

      expect(requestedQueries.last.year, 2025);
      expect(
        requestedQueries.last.balanceGroup,
        AccountBalanceGroup.savingsInvestment,
      );

      await tester.tap(find.byKey(const Key('summary-account-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('summary-account-option-all')));
      await tester.pumpAndSettle();

      expect(requestedQueries.last.balanceGroup, isNull);
      expect(find.text('Rekening: Semua'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fits 320 pixels at 200 percent text with large values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpView(
      tester,
      snapshot: _snapshot(
        2026,
        overrides: {
          1: const _Totals(income: 999999999999, expense: 999999999998),
        },
      ),
      today: DateTime(2026, 1, 10),
      width: 320,
      height: 900,
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text('Rp 999.999.999.999'), findsOneWidget);
    expect(find.text('Rp 999.999.999.998'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpView(
  WidgetTester tester, {
  required YearlySummarySnapshot snapshot,
  required DateTime today,
  DateTime? highlightedMonth,
  double width = 420,
  double height = 900,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height), textScaler: textScaler),
        child: Scaffold(
          body: MonthlySummaryYearView(
            snapshot: snapshot,
            today: today,
            highlightedMonth: highlightedMonth,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

YearlySummarySnapshot _snapshot(
  int year, {
  Map<int, _Totals> overrides = const {},
}) => YearlySummarySnapshot(
  year: year,
  months: [
    for (var month = 1; month <= 12; month++)
      MonthlySummaryItem(
        month: DateTime(year, month),
        income: overrides[month]?.income ?? 0,
        expense: overrides[month]?.expense ?? 0,
      ),
  ],
);

String _keyedText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

class _Totals {
  const _Totals({required this.income, required this.expense});

  final int income;
  final int expense;
}
