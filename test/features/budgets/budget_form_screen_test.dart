import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/providers.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/features/budgets/view_models/budget_view_model.dart';
import 'package:waras_arta/features/budgets/views/budget_form_screen.dart';
import 'package:waras_arta/features/calendar/view_models/calendar_view_model.dart';

import 'fake_budget_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('conflict load error disables picker and retry recovers it', (
    tester,
  ) async {
    final repository = FakeBudgetRepository(failConflictRead: true);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          budgetRepositoryProvider.overrideWithValue(repository),
          budgetExpenseCategoriesProvider.overrideWith(
            (ref) => Stream.value([_expenseCategoryGroup()]),
          ),
          currentDateProvider.overrideWithValue(DateTime(2026, 2, 10)),
        ],
        child: const MaterialApp(home: BudgetFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.conflictWatchCount, 1);
    expect(find.byKey(const Key('budget-conflicts-error')), findsOneWidget);
    expect(find.byKey(const Key('retry-budget-conflicts')), findsOneWidget);
    expect(
      find.text('Konflik kategori belum dapat diperiksa. Data belum diubah.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('budget-category-picker')),
          )
          .onPressed,
      isNull,
    );

    repository.failConflictRead = false;
    await tester.ensureVisible(find.byKey(const Key('retry-budget-conflicts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('retry-budget-conflicts')));
    await tester.pumpAndSettle();

    expect(repository.conflictWatchCount, 2);
    expect(find.byKey(const Key('budget-conflicts-error')), findsNothing);
    expect(find.byKey(const Key('retry-budget-conflicts')), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('budget-category-picker')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.ensureVisible(find.byKey(const Key('budget-category-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('budget-category-picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('budget-category-10')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

CategoryGroup _expenseCategoryGroup() {
  final timestamp = DateTime.utc(2026, 2, 1);
  return CategoryGroup(
    parent: FinanceCategory(
      id: 9,
      parentId: null,
      kind: CategoryKind.expense,
      name: 'Makan & minum',
      iconKey: 'restaurant',
      isArchived: false,
      sortOrder: 0,
      systemKey: null,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    children: [
      FinanceCategory(
        id: 10,
        parentId: 9,
        kind: CategoryKind.expense,
        name: 'Umum',
        iconKey: 'restaurant',
        isArchived: false,
        sortOrder: 0,
        systemKey: null,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    ],
  );
}
