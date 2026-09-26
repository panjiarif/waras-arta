import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/providers.dart';
import 'package:waras_arta/domain/budget.dart';
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

  testWidgets('uses the selected period as the create form seed', (
    tester,
  ) async {
    final repository = FakeBudgetRepository();
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
        child: MaterialApp(
          home: BudgetFormScreen(
            initialKind: BudgetPeriodKind.yearly,
            initialMonth: DateTime(2024, 9),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selector = tester.widget<SegmentedButton<BudgetPeriodKind>>(
      find.byKey(const Key('budget-period-kind')),
    );
    expect(selector.selected, {BudgetPeriodKind.yearly});
    expect(find.text('Tahun 2024'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('caps the monthly picker and rejects a future month seed', (
    tester,
  ) async {
    final repository = FakeBudgetRepository();
    addTearDown(repository.dispose);
    await _pumpBudgetForm(tester, repository, initialMonth: DateTime(2026, 3));

    await tester.tap(find.byKey(const Key('budget-month')));
    await tester.pumpAndSettle();

    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, DateTime(2026, 2, 10));
    expect(picker.lastDate, DateTime(2026, 2, 10));

    Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
    await tester.pumpAndSettle();
    await _submitRequiredFields(tester);

    expect(repository.createdDraft, isNull);
    expect(
      find.text('Periode anggaran tidak boleh dimulai setelah hari ini.'),
      findsOneWidget,
    );
    expect(
      find.text('Pilih minimal satu subkategori pengeluaran.'),
      findsNothing,
    );
  });

  testWidgets('caps the yearly picker to the current year', (tester) async {
    final repository = FakeBudgetRepository();
    addTearDown(repository.dispose);
    await _pumpBudgetForm(
      tester,
      repository,
      initialKind: BudgetPeriodKind.yearly,
      initialMonth: DateTime(2030, 1),
    );

    await tester.tap(find.byKey(const Key('budget-year')));
    await tester.pumpAndSettle();

    final picker = tester.widget<YearPicker>(find.byType(YearPicker));
    expect(picker.lastDate.year, 2026);
    expect(picker.selectedDate, DateTime(2026));

    Navigator.of(tester.element(find.byType(YearPicker))).pop();
    await tester.pumpAndSettle();
    await _submitRequiredFields(tester);

    expect(repository.createdDraft, isNull);
    expect(
      find.text('Periode anggaran tidak boleh dimulai setelah hari ini.'),
      findsOneWidget,
    );
  });

  testWidgets('rejects a custom range that starts after today', (tester) async {
    final repository = FakeBudgetRepository();
    addTearDown(repository.dispose);
    await _pumpBudgetForm(tester, repository);

    await _selectCustomRange(tester, startDay: 11, endDay: 20);
    await _submitRequiredFields(tester);

    expect(repository.createdDraft, isNull);
    expect(
      find.text('Periode anggaran tidak boleh dimulai setelah hari ini.'),
      findsOneWidget,
    );
    expect(
      find.text('Pilih minimal satu subkategori pengeluaran.'),
      findsNothing,
    );
  });

  testWidgets('allows a custom range starting today to end in the future', (
    tester,
  ) async {
    final repository = FakeBudgetRepository();
    addTearDown(repository.dispose);
    await _pumpBudgetForm(tester, repository);

    await _selectCustomRange(tester, startDay: 10, endDay: 20);
    await _submitRequiredFields(tester);

    expect(
      find.text('Periode anggaran tidak boleh dimulai setelah hari ini.'),
      findsNothing,
    );
    expect(
      find.text('Pilih minimal satu subkategori pengeluaran.'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpBudgetForm(
  WidgetTester tester,
  FakeBudgetRepository repository, {
  BudgetPeriodKind? initialKind,
  DateTime? initialMonth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        budgetRepositoryProvider.overrideWithValue(repository),
        budgetExpenseCategoriesProvider.overrideWith(
          (ref) => Stream.value([_expenseCategoryGroup()]),
        ),
        currentDateProvider.overrideWithValue(DateTime(2026, 2, 10)),
      ],
      child: MaterialApp(
        home: BudgetFormScreen(
          initialKind: initialKind,
          initialMonth: initialMonth,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectCustomRange(
  WidgetTester tester, {
  required int startDay,
  required int endDay,
}) async {
  await tester.tap(find.byKey(const ValueKey('budget-period-custom')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('budget-custom-range')));
  await tester.pumpAndSettle();

  final dialog = find.byType(DateRangePickerDialog);
  expect(dialog, findsOneWidget);
  final start = find.descendant(of: dialog, matching: find.text('$startDay'));
  final end = find.descendant(of: dialog, matching: find.text('$endDay'));
  expect(start, findsWidgets);
  expect(end, findsWidgets);

  await tester.tap(start.first);
  await tester.pump();
  await tester.tap(end.first);
  await tester.pump();

  final actions = find.descendant(
    of: dialog,
    matching: find.byType(TextButton),
  );
  expect(actions, findsAtLeastNWidgets(1));
  await tester.tap(actions.last);
  await tester.pumpAndSettle();
}

Future<void> _submitRequiredFields(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('budget-name')),
    'Anggaran pengujian',
  );
  await tester.enterText(find.byKey(const Key('budget-limit')), '100000');
  await tester.ensureVisible(find.byKey(const Key('save-budget')));
  await tester.tap(find.byKey(const Key('save-budget')));
  await tester.pumpAndSettle();
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
