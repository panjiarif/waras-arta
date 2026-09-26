import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/theme.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/features/ledger/views/overview_charts_section.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('shows seven recent expenses and seven balance points', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpCharts(tester, _snapshot());

    expect(find.byKey(const Key('overview-charts-section')), findsOneWidget);
    expect(find.text('Tren terkini'), findsOneWidget);
    expect(find.byKey(const Key('weekly-expense-chart-card')), findsOneWidget);
    expect(find.byKey(const Key('primary-balance-chart-card')), findsOneWidget);
    expect(
      find.text('Saldo utama enam bulan terakhir dan saldo saat ini.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('weekly-expense-bars')), findsOneWidget);
    expect(find.byKey(const Key('primary-balance-line')), findsOneWidget);
    for (var index = 0; index < 7; index++) {
      expect(
        find.byKey(ValueKey('expense-bar-semantics-$index')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('balance-point-semantics-$index')),
        findsOneWidget,
      );
    }
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expense-value-label-0')))
          .data,
      '10.000',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expense-value-label-1')))
          .data,
      '0',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expense-value-label-6')))
          .data,
      '60.000',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('balance-axis-label-0')))
          .data,
      '2 jt',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('balance-axis-label-1')))
          .data,
      '1 jt',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('balance-axis-label-2')))
          .data,
      '0',
    );

    final expenseSummary = tester.getSemantics(
      find.byKey(const Key('weekly-expense-chart-card-semantics')),
    );
    expect(
      expenseSummary.label,
      'Pengeluaran 7 hari terakhir. Total Rp 210.000.',
    );
    expect(expenseSummary.label, isNot(contains('25 Sep 2026')));
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('expense-bar-semantics-6')))
          .label,
      '25 Sep 2026, pengeluaran Rp 60.000',
    );
    final balanceSummary = tester.getSemantics(
      find.byKey(const Key('primary-balance-chart-card-semantics')),
    );
    expect(
      balanceSummary.label,
      contains('Tren saldo utama enam bulan terakhir'),
    );
    expect(balanceSummary.label, contains('Rp 1.800.000'));
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('balance-point-semantics-6')))
          .label,
      'Saat ini, 25 Sep 2026, saldo utama Rp 1.800.000',
    );
    semantics.dispose();
  });

  testWidgets('keeps seven zero bars and explains the empty week', (
    tester,
  ) async {
    final base = _snapshot();
    await _pumpCharts(
      tester,
      OverviewChartsSnapshot(
        today: base.today,
        dailyExpenses: [
          for (final point in base.dailyExpenses)
            DailyExpenseTotal(day: point.day, expense: 0),
        ],
        balancePoints: base.balancePoints,
      ),
    );

    expect(find.byKey(const Key('weekly-expense-empty')), findsOneWidget);
    expect(
      find.text('Belum ada pengeluaran dalam 7 hari terakhir.'),
      findsOneWidget,
    );
    for (var index = 0; index < 7; index++) {
      expect(find.byKey(ValueKey('expense-day-label-$index')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports negative, zero-crossing, and constant balances', (
    tester,
  ) async {
    final base = _snapshot();
    await _pumpCharts(
      tester,
      OverviewChartsSnapshot(
        today: base.today,
        dailyExpenses: base.dailyExpenses,
        balancePoints: [
          PrimaryBalancePoint(
            day: DateTime(2026, 3, 31),
            balance: -300000,
            isCurrent: false,
          ),
          PrimaryBalancePoint(
            day: DateTime(2026, 4, 30),
            balance: -300000,
            isCurrent: false,
          ),
          PrimaryBalancePoint(
            day: DateTime(2026, 5, 31),
            balance: 0,
            isCurrent: false,
          ),
          PrimaryBalancePoint(
            day: DateTime(2026, 6, 30),
            balance: 300000,
            isCurrent: false,
          ),
          PrimaryBalancePoint(
            day: DateTime(2026, 7, 31),
            balance: 300000,
            isCurrent: false,
          ),
          PrimaryBalancePoint(
            day: DateTime(2026, 8, 31),
            balance: 300000,
            isCurrent: false,
          ),
          PrimaryBalancePoint(
            day: DateTime(2026, 9, 25),
            balance: -100000,
            isCurrent: true,
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('primary-balance-line')), findsOneWidget);
    expect(find.text('Kini'), findsOneWidget);
    expect(find.text('300k'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('-300k'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adapts right axis labels for thousands and millions', (
    tester,
  ) async {
    final base = _snapshot();
    await _pumpCharts(
      tester,
      _withBalances(base, const [
        0,
        100000,
        220000,
        300000,
        410000,
        500000,
        580000,
      ]),
    );

    expect(find.text('600k'), findsOneWidget);
    expect(find.text('300k'), findsOneWidget);

    await _pumpCharts(
      tester,
      _withBalances(base, const [
        0,
        400000,
        800000,
        1200000,
        1600000,
        2000000,
        2300000,
      ]),
    );

    expect(find.text('2,4 jt'), findsOneWidget);
    expect(find.text('1,2 jt'), findsOneWidget);

    await _pumpCharts(
      tester,
      _withBalances(base, const [
        0,
        400000000,
        800000000,
        1200000000,
        1600000000,
        2000000000,
        2300000000,
      ]),
    );

    expect(find.text('2,4 M'), findsOneWidget);
    expect(find.text('1,2 M'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows sensible axis labels for negative and all-zero data', (
    tester,
  ) async {
    final base = _snapshot();
    await _pumpCharts(
      tester,
      _withBalances(base, const [
        -300000,
        -260000,
        -200000,
        -180000,
        -100000,
        -50000,
        0,
      ]),
    );

    expect(find.text('0'), findsWidgets);
    expect(find.text('-150k'), findsOneWidget);
    expect(find.text('-300k'), findsOneWidget);

    await _pumpCharts(tester, _withBalances(base, const [0, 0, 0, 0, 0, 0, 0]));

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('balance-axis-label-0')))
          .data,
      '0',
    );
    expect(find.byKey(const ValueKey('balance-axis-label-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles partial data without assuming seven available points', (
    tester,
  ) async {
    await _pumpCharts(
      tester,
      OverviewChartsSnapshot(
        today: DateTime(2026, 9, 25),
        dailyExpenses: const [],
        balancePoints: [
          PrimaryBalancePoint(
            day: DateTime(2026, 9, 25),
            balance: 250000,
            isCurrent: true,
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('weekly-expense-empty')), findsOneWidget);
    expect(find.byKey(const Key('primary-balance-empty')), findsNothing);
    expect(
      find.byKey(const ValueKey('balance-point-semantics-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at 320 pixels and 200 percent text', (
    tester,
  ) async {
    final base = _snapshot();
    await _pumpCharts(
      tester,
      OverviewChartsSnapshot(
        today: base.today,
        dailyExpenses: [
          DailyExpenseTotal(
            day: base.dailyExpenses.first.day,
            expense: 987654321,
          ),
          ...base.dailyExpenses.skip(1),
        ],
        balancePoints: base.balancePoints,
      ),
      width: 320,
      textScaler: const TextScaler.linear(2),
    );

    expect(
      tester.getSize(find.byKey(const Key('weekly-expense-chart-card'))).width,
      lessThanOrEqualTo(288),
    );
    expect(
      tester.getSize(find.byKey(const Key('primary-balance-chart-card'))).width,
      lessThanOrEqualTo(288),
    );
    expect(find.text('987.654.321'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpCharts(
  WidgetTester tester,
  OverviewChartsSnapshot snapshot, {
  double width = 420,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 1600), textScaler: textScaler),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OverviewChartsSection(snapshot: snapshot),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

OverviewChartsSnapshot _snapshot() => OverviewChartsSnapshot(
  today: DateTime(2026, 9, 25),
  dailyExpenses: [
    DailyExpenseTotal(day: DateTime(2026, 9, 19), expense: 10000),
    DailyExpenseTotal(day: DateTime(2026, 9, 20), expense: 0),
    DailyExpenseTotal(day: DateTime(2026, 9, 21), expense: 20000),
    DailyExpenseTotal(day: DateTime(2026, 9, 22), expense: 40000),
    DailyExpenseTotal(day: DateTime(2026, 9, 23), expense: 30000),
    DailyExpenseTotal(day: DateTime(2026, 9, 24), expense: 50000),
    DailyExpenseTotal(day: DateTime(2026, 9, 25), expense: 60000),
  ],
  balancePoints: [
    PrimaryBalancePoint(
      day: DateTime(2026, 3, 31),
      balance: 1000000,
      isCurrent: false,
    ),
    PrimaryBalancePoint(
      day: DateTime(2026, 4, 30),
      balance: 1250000,
      isCurrent: false,
    ),
    PrimaryBalancePoint(
      day: DateTime(2026, 5, 31),
      balance: 1100000,
      isCurrent: false,
    ),
    PrimaryBalancePoint(
      day: DateTime(2026, 6, 30),
      balance: 1500000,
      isCurrent: false,
    ),
    PrimaryBalancePoint(
      day: DateTime(2026, 7, 31),
      balance: 1450000,
      isCurrent: false,
    ),
    PrimaryBalancePoint(
      day: DateTime(2026, 8, 31),
      balance: 1700000,
      isCurrent: false,
    ),
    PrimaryBalancePoint(
      day: DateTime(2026, 9, 25),
      balance: 1800000,
      isCurrent: true,
    ),
  ],
);

OverviewChartsSnapshot _withBalances(
  OverviewChartsSnapshot base,
  List<int> balances,
) => OverviewChartsSnapshot(
  today: base.today,
  dailyExpenses: base.dailyExpenses,
  balancePoints: [
    for (var index = 0; index < balances.length; index++)
      PrimaryBalancePoint(
        day: index == balances.length - 1
            ? base.today
            : DateTime(2026, 3 + index, 28),
        balance: balances[index],
        isCurrent: index == balances.length - 1,
      ),
  ],
);
