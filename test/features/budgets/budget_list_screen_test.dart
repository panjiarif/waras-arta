import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/providers.dart';
import 'package:waras_arta/domain/budget.dart';
import 'package:waras_arta/features/budgets/views/budget_list_screen.dart';
import 'package:waras_arta/features/calendar/view_models/calendar_view_model.dart';

import 'fake_budget_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  Future<void> pumpList(
    WidgetTester tester,
    FakeBudgetRepository repository, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          budgetRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(DateTime(2026, 2, 10)),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: const Scaffold(body: BudgetListScreen(embedded: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String groupKey(int startDay, int endDay, [String? field]) => [
    'budget-group',
    ?field,
    '$startDay',
    '$endDay',
  ].join('-');

  String keyedText(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  String groupSemanticsLabel(WidgetTester tester, int startDay, int endDay) =>
      tester
          .getSemantics(
            find.byKey(ValueKey(groupKey(startDay, endDay, 'semantics'))),
          )
          .label;

  testWidgets('monthly and yearly active totals stay independent', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          limitAmount: 1000000,
          spentAmount: 250000,
          period: BudgetPeriod.monthly(2026, 2),
          categories: [fakeBudgetCategory(id: 11)],
        ),
        fakeBudgetProgress(
          id: 2,
          limitAmount: 3000000,
          spentAmount: 750000,
          period: BudgetPeriod.yearly(2026),
          categories: [fakeBudgetCategory(id: 12)],
        ),
      ],
    );

    await pumpList(tester, repository);

    expect(find.byKey(const Key('budget-list-summary')), findsNothing);
    expect(find.byKey(ValueKey(groupKey(20260201, 20260228))), findsOneWidget);
    expect(
      keyedText(tester, groupKey(20260201, 20260228, 'spent')),
      'Rp 250.000',
    );
    expect(
      keyedText(tester, groupKey(20260201, 20260228, 'limit')),
      'Rp 1.000.000',
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(ValueKey(groupKey(20260201, 20260228, 'progress'))),
          )
          .value,
      .25,
    );
    expect(
      groupSemanticsLabel(tester, 20260201, 20260228),
      allOf(
        contains('Februari 2026'),
        contains('Bulanan'),
        contains('Rp 250.000'),
        contains('Rp 1.000.000'),
        contains('25 persen'),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(ValueKey(groupKey(20260101, 20261231))),
      300,
    );

    expect(
      keyedText(tester, groupKey(20260101, 20261231, 'spent')),
      'Rp 750.000',
    );
    expect(
      keyedText(tester, groupKey(20260101, 20261231, 'limit')),
      'Rp 3.000.000',
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(ValueKey(groupKey(20260101, 20261231, 'progress'))),
          )
          .value,
      .25,
    );
    expect(
      groupSemanticsLabel(tester, 20260101, 20261231),
      allOf(
        contains('2026'),
        contains('Tahunan'),
        contains('Rp 750.000'),
        contains('Rp 3.000.000'),
        contains('25 persen'),
      ),
    );
    semanticsHandle.dispose();
  });

  testWidgets('different kinds sharing an exact range are summed together', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          limitAmount: 1000000,
          spentAmount: 250000,
          period: BudgetPeriod.custom(20260201, 20260228),
          categories: [fakeBudgetCategory(id: 11)],
        ),
        fakeBudgetProgress(
          id: 2,
          limitAmount: 3000000,
          spentAmount: 750000,
          period: BudgetPeriod.monthly(2026, 2),
          categories: [fakeBudgetCategory(id: 12)],
        ),
      ],
    );

    await pumpList(tester, repository);

    expect(find.byKey(ValueKey(groupKey(20260201, 20260228))), findsOneWidget);
    expect(
      keyedText(tester, groupKey(20260201, 20260228, 'spent')),
      'Rp 1.000.000',
    );
    expect(
      keyedText(tester, groupKey(20260201, 20260228, 'limit')),
      'Rp 4.000.000',
    );
    expect(find.text('Bulanan + Kustom • 2 anggaran'), findsOneWidget);
    expect(
      groupSemanticsLabel(tester, 20260201, 20260228),
      allOf(
        contains('Bulanan + Kustom'),
        contains('2 anggaran'),
        contains('25 persen'),
      ),
    );
    semanticsHandle.dispose();
  });

  testWidgets('kind filter removes totals from the other period kind', (
    tester,
  ) async {
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          period: BudgetPeriod.monthly(2026, 2),
          categories: [fakeBudgetCategory(id: 11)],
        ),
        fakeBudgetProgress(
          id: 2,
          period: BudgetPeriod.yearly(2026),
          categories: [fakeBudgetCategory(id: 12)],
        ),
      ],
    );

    await pumpList(tester, repository);

    await tester.tap(find.byKey(const Key('budget-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('budget-kind-monthly')));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey(groupKey(20260201, 20260228))), findsOneWidget);
    expect(find.byKey(ValueKey(groupKey(20260101, 20261231))), findsNothing);

    await tester.tap(find.byKey(const Key('budget-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('budget-kind-yearly')));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey(groupKey(20260201, 20260228))), findsNothing);
    expect(find.byKey(ValueKey(groupKey(20260101, 20261231))), findsOneWidget);
  });

  testWidgets('history and future ranges never combine their totals', (
    tester,
  ) async {
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          limitAmount: 100000,
          spentAmount: 10000,
          period: BudgetPeriod.monthly(2026, 1),
        ),
        fakeBudgetProgress(
          id: 2,
          limitAmount: 200000,
          spentAmount: 40000,
          period: BudgetPeriod.yearly(2025),
        ),
        fakeBudgetProgress(
          id: 3,
          limitAmount: 300000,
          spentAmount: 90000,
          period: BudgetPeriod.monthly(2026, 3),
        ),
        fakeBudgetProgress(
          id: 4,
          limitAmount: 400000,
          spentAmount: 160000,
          period: BudgetPeriod.yearly(2027),
        ),
      ],
    );

    await pumpList(tester, repository);

    await tester.tap(find.byKey(const ValueKey('budget-status-history')));
    await tester.pumpAndSettle();

    expect(
      keyedText(tester, groupKey(20260101, 20260131, 'spent')),
      'Rp 10.000',
    );

    await tester.scrollUntilVisible(
      find.byKey(ValueKey(groupKey(20250101, 20251231))),
      300,
    );

    expect(
      keyedText(tester, groupKey(20250101, 20251231, 'spent')),
      'Rp 40.000',
    );
    expect(find.byKey(ValueKey(groupKey(20260301, 20260331))), findsNothing);

    await tester.tap(find.byKey(const ValueKey('budget-status-upcoming')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const PageStorageKey('budget-list')),
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();

    expect(
      keyedText(tester, groupKey(20260301, 20260331, 'spent')),
      'Rp 90.000',
    );

    await tester.scrollUntilVisible(
      find.byKey(ValueKey(groupKey(20270101, 20271231))),
      300,
    );

    expect(
      keyedText(tester, groupKey(20270101, 20271231, 'spent')),
      'Rp 160.000',
    );
    expect(find.byKey(ValueKey(groupKey(20260101, 20260131))), findsNothing);
  });

  testWidgets('empty result has no range summary', (tester) async {
    await pumpList(tester, FakeBudgetRepository());

    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('budget-group-');
      }),
      findsNothing,
    );
    expect(find.byKey(const Key('budget-empty-title')), findsOneWidget);
  });

  testWidgets(
    'exceeded range exposes actual usage but clamps visual progress',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      final repository = FakeBudgetRepository(
        items: [
          fakeBudgetProgress(
            limitAmount: 1000000,
            spentAmount: 1250000,
            categories: [fakeBudgetCategory(id: 11)],
          ),
        ],
      );

      await pumpList(tester, repository);

      expect(
        keyedText(tester, groupKey(20260201, 20260228, 'spent')),
        'Rp 1.250.000',
      );
      expect(
        keyedText(tester, groupKey(20260201, 20260228, 'limit')),
        'Rp 1.000.000',
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(ValueKey(groupKey(20260201, 20260228, 'progress'))),
            )
            .value,
        1,
      );
      expect(
        groupSemanticsLabel(tester, 20260201, 20260228),
        allOf(
          contains('Rp 1.250.000'),
          contains('Rp 1.000.000'),
          contains('125 persen'),
          contains('Rp 250.000'),
        ),
      );
      semanticsHandle.dispose();
    },
  );

  testWidgets('range summary fits 320 pixels at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          limitAmount: 999999999999,
          spentAmount: 999999999999,
          categories: [fakeBudgetCategory(id: 11)],
        ),
        fakeBudgetProgress(
          id: 2,
          limitAmount: 999999999999,
          spentAmount: 999999999999,
          categories: [fakeBudgetCategory(id: 12)],
        ),
      ],
    );

    await pumpList(tester, repository, textScaler: const TextScaler.linear(2));

    expect(
      keyedText(tester, groupKey(20260201, 20260228, 'spent')),
      'Rp 1.999.999.999.998',
    );
    expect(
      keyedText(tester, groupKey(20260201, 20260228, 'limit')),
      'Rp 1.999.999.999.998',
    );
    expect(
      groupSemanticsLabel(tester, 20260201, 20260228),
      allOf(
        contains('Februari 2026'),
        contains('2 anggaran'),
        contains('Rp 1.999.999.999.998'),
        contains('100 persen'),
      ),
    );
    expect(tester.takeException(), isNull);
    semanticsHandle.dispose();
  });
}
