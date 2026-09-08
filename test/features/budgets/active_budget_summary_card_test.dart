import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/providers.dart';
import 'package:waras_arta/domain/budget.dart';
import 'package:waras_arta/features/budgets/views/active_budget_summary_card.dart';
import 'package:waras_arta/features/calendar/view_models/calendar_view_model.dart';

import 'fake_budget_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  Future<void> pumpSummary(
    WidgetTester tester,
    FakeBudgetRepository repository,
  ) async {
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          budgetRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(DateTime(2026, 2, 10)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ActiveBudgetSummaryCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'globally ranks exhausted ahead of normal budgets in another range',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      final repository = FakeBudgetRepository(
        items: [
          fakeBudgetProgress(
            id: 1,
            name: 'Normal bulanan',
            period: BudgetPeriod.monthly(2026, 2),
            categories: [fakeBudgetCategory(id: 11)],
          ),
          fakeBudgetProgress(
            id: 2,
            name: 'Normal rentang pendek',
            period: BudgetPeriod.custom(20260201, 20260220),
            categories: [fakeBudgetCategory(id: 12)],
          ),
          fakeBudgetProgress(
            id: 3,
            name: 'Habis tahunan',
            limitAmount: 100000,
            spentAmount: 100000,
            period: BudgetPeriod.yearly(2026),
            categories: [fakeBudgetCategory(id: 13)],
          ),
        ],
      );

      await pumpSummary(tester, repository);

      final exhausted = find.byKey(const ValueKey('budget-summary-item-3'));
      final selectedNormal = find.byKey(
        const ValueKey('budget-summary-item-2'),
      );
      expect(exhausted, findsOneWidget);
      expect(selectedNormal, findsOneWidget);
      expect(find.byKey(const ValueKey('budget-summary-item-1')), findsNothing);
      expect(
        tester.getTopLeft(exhausted).dy,
        lessThan(tester.getTopLeft(selectedNormal).dy),
      );
      expect(find.text('Aktif hari ini · 10 Feb 2026'), findsOneWidget);

      const semanticsLabel =
          'Habis tahunan, Rp 100.000 dari Rp 100.000, 100 persen, '
          'Anggaran habis';
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('budget-summary-semantics-3')),
        ),
        isSemantics(
          label: semanticsLabel,
          isButton: true,
          hasTapAction: true,
          children: <Matcher>[],
        ),
      );
      semanticsHandle.dispose();
    },
  );

  testWidgets('uses end, start, name, and id as deterministic tie-breaks', (
    tester,
  ) async {
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          name: 'Akhir lebih lama',
          period: BudgetPeriod.monthly(2026, 2),
          categories: [fakeBudgetCategory(id: 11)],
        ),
        fakeBudgetProgress(
          id: 2,
          name: 'Aaa mulai belakangan',
          period: BudgetPeriod.custom(20260202, 20260220),
          categories: [fakeBudgetCategory(id: 12)],
        ),
        fakeBudgetProgress(
          id: 5,
          name: 'Zulu',
          period: BudgetPeriod.custom(20260201, 20260220),
          categories: [fakeBudgetCategory(id: 13)],
        ),
        fakeBudgetProgress(
          id: 4,
          name: 'Alpha',
          period: BudgetPeriod.custom(20260201, 20260220),
          categories: [fakeBudgetCategory(id: 14)],
        ),
        fakeBudgetProgress(
          id: 3,
          name: 'Alpha',
          period: BudgetPeriod.custom(20260201, 20260220),
          categories: [fakeBudgetCategory(id: 15)],
        ),
      ],
    );

    await pumpSummary(tester, repository);

    final first = find.byKey(const ValueKey('budget-summary-item-3'));
    final second = find.byKey(const ValueKey('budget-summary-item-4'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    for (final hiddenId in [1, 2, 5]) {
      expect(
        find.byKey(ValueKey('budget-summary-item-$hiddenId')),
        findsNothing,
      );
    }
  });
}
