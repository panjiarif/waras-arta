import 'dart:ui' as ui;

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

  String groupKey(
    BudgetPeriodKind kind,
    int startDay,
    int endDay, [
    String? field,
  ]) => ['budget-group', ?field, kind.name, '$startDay', '$endDay'].join('-');

  String keyedText(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  Finder budgetList() => find.byWidgetPredicate((widget) {
    final key = widget.key;
    return widget is ListView &&
        key is PageStorageKey &&
        key.value.toString().startsWith('budget-list-');
  });

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      220,
      scrollable: find.descendant(
        of: budgetList(),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'all view keeps monthly yearly and custom periods in separate surfaces',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = FakeBudgetRepository(
        items: [
          fakeBudgetProgress(
            id: 1,
            limitAmount: 100000,
            spentAmount: 25000,
            period: BudgetPeriod.monthly(2026, 2),
          ),
          fakeBudgetProgress(
            id: 2,
            limitAmount: 300000,
            spentAmount: 60000,
            period: BudgetPeriod.yearly(2026),
          ),
          fakeBudgetProgress(
            id: 3,
            limitAmount: 200000,
            spentAmount: 40000,
            period: BudgetPeriod.custom(20260201, 20260228),
          ),
        ],
      );

      await pumpList(tester, repository);

      expect(find.text('Februari 2026'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(groupKey(BudgetPeriodKind.monthly, 20260201, 20260228)),
        ),
        findsOneWidget,
      );
      expect(
        keyedText(
          tester,
          groupKey(BudgetPeriodKind.monthly, 20260201, 20260228, 'spent'),
        ),
        'Rp 25.000',
      );

      final yearlyGroup = find.byKey(
        ValueKey(groupKey(BudgetPeriodKind.yearly, 20260101, 20261231)),
      );
      await reveal(tester, yearlyGroup);
      expect(yearlyGroup, findsOneWidget);
      expect(find.text('Pemakaian s.d. 10 Feb 2026'), findsNWidgets(2));

      final customGroup = find.byKey(
        ValueKey(groupKey(BudgetPeriodKind.custom, 20260201, 20260228)),
      );
      await reveal(tester, customGroup);
      expect(customGroup, findsOneWidget);
      expect(find.byKey(const ValueKey('budget-card-3')), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.byKey(
                ValueKey(
                  groupKey(
                    BudgetPeriodKind.custom,
                    20260201,
                    20260228,
                    'semantics',
                  ),
                ),
              ),
            )
            .label,
        allOf(
          contains('Kustom'),
          contains('Rp 40.000'),
          contains('Rp 200.000'),
          contains('20 persen'),
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets('month navigator browses history and stops at current month', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(id: 1),
        fakeBudgetProgress(
          id: 2,
          name: 'Anggaran Januari',
          period: BudgetPeriod.monthly(2026, 1),
        ),
      ],
    );
    await pumpList(tester, repository);

    final previousSemantics = tester.getSemantics(
      find.byKey(const Key('previous-budget-period-semantics')),
    );
    final nextSemantics = tester.getSemantics(
      find.byKey(const Key('next-budget-period-semantics')),
    );
    expect(previousSemantics.label, 'bulan sebelumnya');
    expect(
      previousSemantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    expect(nextSemantics.label, 'bulan berikutnya');
    expect(
      nextSemantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'bulan (sebelumnya|berikutnya)')),
      findsNWidgets(2),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('next-budget-period')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('previous-budget-period')));
    await tester.pumpAndSettle();
    expect(find.text('Januari 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-card-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-card-1')), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('next-budget-period')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('next-budget-period-semantics')))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('next-budget-period')));
    await tester.pumpAndSettle();
    expect(find.text('Februari 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-card-1')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('next-budget-period')))
          .onPressed,
      isNull,
    );
    semantics.dispose();
  });

  testWidgets('yearly filter switches navigator to whole years', (
    tester,
  ) async {
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(id: 1, period: BudgetPeriod.yearly(2026)),
        fakeBudgetProgress(id: 2, period: BudgetPeriod.yearly(2025)),
        fakeBudgetProgress(id: 3),
      ],
    );
    await pumpList(tester, repository);

    await tester.tap(find.byKey(const Key('budget-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('budget-kind-yearly')));
    await tester.pumpAndSettle();

    expect(find.text('2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-card-3')), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('next-budget-period')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('previous-budget-period')));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-card-2')), findsOneWidget);
  });

  testWidgets('manual copy is confirmed and creates independent month items', (
    tester,
  ) async {
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          name: 'Belanja bulanan',
          period: BudgetPeriod.monthly(2026, 1),
        ),
        fakeBudgetProgress(
          id: 2,
          name: 'Pajak tahunan',
          period: BudgetPeriod.yearly(2026),
        ),
      ],
    );
    await pumpList(tester, repository);

    expect(
      find.byKey(const Key('copy-previous-month-budgets')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('budget-card-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy-previous-month-budgets')));
    await tester.pumpAndSettle();
    expect(find.text('Salin anggaran bulanan?'), findsOneWidget);
    expect(find.textContaining('berdiri sendiri'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-copy-monthly-budgets')));
    await tester.pumpAndSettle();

    expect(repository.copiedSource, BudgetPeriod.monthly(2026, 1));
    expect(repository.copiedTarget, BudgetPeriod.monthly(2026, 2));
    expect(find.byKey(const Key('copy-previous-month-budgets')), findsNothing);
    expect(find.text('1 anggaran berhasil disalin.'), findsOneWidget);
    expect(
      repository.items
          .where((item) => item.budget.period == BudgetPeriod.monthly(2026, 2))
          .single
          .spentAmount,
      0,
    );
  });

  testWidgets('copy CTA is hidden for yearly and custom filters', (
    tester,
  ) async {
    final repository = FakeBudgetRepository(
      items: [fakeBudgetProgress(id: 1, period: BudgetPeriod.monthly(2026, 1))],
    );
    await pumpList(tester, repository);
    expect(
      find.byKey(const Key('copy-previous-month-budgets')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('budget-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('budget-kind-custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy-previous-month-budgets')), findsNothing);

    await tester.tap(find.byKey(const Key('budget-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('budget-kind-yearly')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy-previous-month-budgets')), findsNothing);
  });

  testWidgets('compact budget rows expose icon and concise semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          categories: [fakeBudgetCategory(id: 10), fakeBudgetCategory(id: 11)],
        ),
      ],
    );
    await pumpList(tester, repository);

    final row = find.byKey(const ValueKey('budget-card-1'));
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.category_outlined)),
      findsOneWidget,
    );
    final semanticsLabel = tester
        .getSemantics(find.byKey(const ValueKey('open-budget-1')))
        .label;
    expect(
      semanticsLabel,
      allOf(<Matcher>[
        contains('Makan di luar'),
        contains('Bulanan'),
        contains('1 Feb 2026'),
        contains('28 Feb 2026'),
        contains('2 kategori'),
        contains('Terpakai Rp 250.000'),
        contains('25 persen'),
        contains('Sisa Rp 750.000'),
      ]),
    );
    semantics.dispose();
  });

  testWidgets('budget period layout fits 320 pixels at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          name: 'Kebutuhan keluarga bulanan dengan nama sangat panjang',
          limitAmount: 999999999999,
          spentAmount: 999999999999,
        ),
        fakeBudgetProgress(
          id: 2,
          name: 'Anggaran tahunan dengan nama sangat panjang',
          limitAmount: 999999999999,
          spentAmount: 999999999999,
          period: BudgetPeriod.yearly(2026),
        ),
      ],
    );

    await pumpList(tester, repository, textScaler: const TextScaler.linear(2));

    expect(find.byKey(const Key('budget-period-navigator')), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-card-1')), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('budget-card-2')));
    expect(find.byKey(const ValueKey('budget-card-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty period offers create or reset kind filter', (
    tester,
  ) async {
    await pumpList(tester, FakeBudgetRepository());
    expect(find.byKey(const Key('budget-empty-title')), findsOneWidget);
    expect(find.byKey(const Key('create-first-budget')), findsOneWidget);

    await tester.tap(find.byKey(const Key('budget-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('budget-kind-custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('budget-reset-filters')), findsOneWidget);
  });
}
