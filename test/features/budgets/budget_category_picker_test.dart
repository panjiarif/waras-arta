import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/domain/budget.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/features/budgets/views/budget_category_picker.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  testWidgets('group checkbox selects and clears only available children', (
    tester,
  ) async {
    Set<int>? result;
    await _open(tester, onResult: (value) => result = value);
    final group = find.byKey(const ValueKey('budget-category-group-9'));
    final blocked = find.byKey(const ValueKey('budget-category-12'));
    expect(tester.widget<CheckboxListTile>(blocked).onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('budget-category-10')));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(group).value, isNull);
    await tester.tap(group);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(group).value, isTrue);
    await tester.tap(group);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(group).value, isFalse);
    await tester.tap(group);
    await tester.tap(find.byKey(const Key('budget-categories-done')));
    await tester.pumpAndSettle();
    expect(result, {10, 11});
  });

  testWidgets(
    'search retains other selections and group action uses matches only',
    (tester) async {
      Set<int>? result;
      final initial = {11};
      await _open(
        tester,
        initial: initial,
        onResult: (value) => result = value,
      );
      final search = find.byKey(const Key('budget-category-search'));
      await tester.enterText(search, 'siang');
      await tester.pump();
      expect(find.byKey(const ValueKey('budget-category-11')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('budget-category-group-9')));
      await tester.pump();
      expect(find.text('2 subkategori dipilih'), findsOneWidget);
      await tester.enterText(search, 'tidak ditemukan');
      await tester.pump();
      expect(find.text('Tidak ada subkategori yang cocok.'), findsOneWidget);
      await tester.enterText(search, 'makan');
      await tester.pump();
      expect(find.byKey(const ValueKey('budget-category-11')), findsOneWidget);
      await tester.tap(find.byKey(const Key('budget-categories-done')));
      await tester.pumpAndSettle();
      expect(result, {10, 11});
      expect(initial, {11});
    },
  );

  testWidgets('archived or conflicting old selections can only be removed', (
    tester,
  ) async {
    await _open(tester, initial: {12, 13});
    for (final id in [12, 13]) {
      final field = find.byKey(ValueKey('budget-category-$id'));
      expect(tester.widget<CheckboxListTile>(field).value, isTrue);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(field).onChanged, isNull);
    }
    expect(find.text('0 subkategori dipilih'), findsOneWidget);
  });

  testWidgets('cancel leaves original selections untouched', (tester) async {
    final original = {10};
    Set<int>? result = {};
    await _open(tester, initial: original, onResult: (value) => result = value);
    await tester.tap(find.byKey(const ValueKey('budget-category-11')));
    await tester.tap(find.byKey(const Key('budget-categories-cancel')));
    await tester.pumpAndSettle();
    expect(original, {10});
    expect(result, isNull);
  });

  testWidgets('fits a narrow phone with large text and the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, textScale: 2);
    tester.view.viewInsets = FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(
      find.byKey(const Key('budget-category-search')),
      'siang',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final done = find.byKey(const Key('budget-categories-done'));
    expect(tester.getBottomRight(done).dy, lessThanOrEqualTo(400));
  });
}

Future<void> _open(
  WidgetTester tester, {
  Set<int> initial = const {},
  ValueChanged<Set<int>?>? onResult,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showModalBottomSheet<Set<int>>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => BudgetCategoryPickerSheet(
                  groups: [
                    CategoryGroup(
                      parent: _category(9, 'Makan', parentId: null),
                      children: [
                        _category(10, 'Siang'),
                        _category(11, 'Malam'),
                        _category(12, 'Lama', archived: true),
                        _category(13, 'Terpakai'),
                      ],
                    ),
                  ],
                  conflicts: {
                    13: [
                      BudgetConflict(
                        categoryId: 13,
                        budgetId: 1,
                        budgetName: 'Lain',
                        period: BudgetPeriod.monthly(2026, 10),
                      ),
                    ],
                  },
                  initialIds: initial,
                ),
              );
              onResult?.call(result);
            },
            child: const Text('Buka'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Buka'));
  await tester.pumpAndSettle();
}

FinanceCategory _category(
  int id,
  String name, {
  int? parentId = 9,
  bool archived = false,
}) => FinanceCategory(
  id: id,
  parentId: parentId,
  kind: CategoryKind.expense,
  name: name,
  iconKey: 'restaurant',
  isArchived: archived,
  sortOrder: id,
  systemKey: null,
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10),
);
