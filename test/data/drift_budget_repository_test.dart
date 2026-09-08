import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/database/app_database.dart';
import 'package:waras_arta/data/repositories/drift_budget_repository.dart';
import 'package:waras_arta/data/repositories/drift_finance_repository.dart';
import 'package:waras_arta/domain/budget.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 9, 8, 3, 30);
  final validationError = isA<BudgetValidationException>();
  late AppDatabase db;
  late DriftBudgetRepository budgets;
  late DriftFinanceRepository finance;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    budgets = DriftBudgetRepository(db, clock: () => fixedNow);
    finance = DriftFinanceRepository(db);
  });

  tearDown(() => db.close());

  Future<List<CategoryGroup>> categoryGroups(CategoryKind kind) =>
      finance.watchCategoryTree(kind).first;

  Future<int> createAccount([String name = 'Bank']) => finance.createAccount(
    AccountDraft(
      name: name,
      type: AccountType.bank,
      openingBalance: 0,
      openedAt: DateTime(2024, 1, 1),
    ),
  );

  BudgetDraft draft({
    required BudgetPeriod period,
    required String name,
    required Iterable<int> categoryIds,
    int limitAmount = 100000,
  }) => BudgetDraft(
    period: period,
    name: name,
    limitAmount: limitAmount,
    categoryIds: categoryIds,
  );

  BudgetListFilter filter(
    BudgetTemporalStatus status, {
    int referenceDay = 20240115,
    BudgetPeriodKind? kind,
  }) => BudgetListFilter(
    temporalStatus: status,
    referenceDay: referenceDay,
    periodKind: kind,
  );

  Map<String, BudgetProgress> byName(BudgetListSnapshot snapshot) => {
    for (final item in snapshot.items) item.budget.name: item,
  };

  test(
    'creates every period kind and filters them in deterministic order',
    () async {
      final expenseGroups = await categoryGroups(CategoryKind.expense);
      final reusableCategoryId = expenseGroups[0].children.single.id;
      final yearlyCategoryIds = {
        expenseGroups[1].children.single.id,
        expenseGroups[2].children.single.id,
      };

      final olderHistoryId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.custom(20221101, 20221130),
          name: 'November lama',
          categoryIds: {reusableCategoryId},
        ),
      );
      final crossYearId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.custom(20221230, 20230102),
          name: 'Lintas tahun',
          categoryIds: {reusableCategoryId},
        ),
      );
      final monthlyId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.monthly(2024, 1),
          name: '  Kebutuhan   Januari  ',
          categoryIds: {reusableCategoryId},
        ),
      );
      final februaryId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.custom(20240201, 20240220),
          name: 'Awal Februari',
          categoryIds: {reusableCategoryId},
        ),
      );
      final marchId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.custom(20240301, 20240310),
          name: 'Awal Maret',
          categoryIds: {reusableCategoryId},
        ),
      );
      final oneDayId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.custom(20240401, 20240401),
          name: 'Satu hari',
          categoryIds: {reusableCategoryId},
        ),
      );
      final yearlyId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.yearly(2025),
          name: 'Tahunan 2025',
          categoryIds: yearlyCategoryIds,
        ),
      );

      final monthly = await budgets.getBudget(monthlyId);
      expect(monthly, isNotNull);
      expect(monthly!.budget.name, 'Kebutuhan Januari');
      expect(monthly.budget.normalizedName, 'kebutuhan januari');
      expect(monthly.budget.period, BudgetPeriod.monthly(2024, 1));
      expect(monthly.categories.single.id, reusableCategoryId);
      expect(monthly.budget.createdAt, fixedNow);
      expect(monthly.budget.updatedAt, fixedNow);

      final yearly = await budgets.getBudget(yearlyId);
      expect(yearly, isNotNull);
      expect(
        yearly!.categories.map((category) => category.id),
        unorderedEquals(yearlyCategoryIds),
      );
      expect(yearly.budget.period, BudgetPeriod.yearly(2025));

      final active = await budgets.loadBudgets(
        filter(BudgetTemporalStatus.active),
      );
      expect(active.items.map((item) => item.budget.id), [monthlyId]);

      final upcoming = await budgets.loadBudgets(
        filter(BudgetTemporalStatus.upcoming),
      );
      expect(upcoming.items.map((item) => item.budget.id), [
        februaryId,
        marchId,
        oneDayId,
        yearlyId,
      ]);
      final yearlyOnly = await budgets.loadBudgets(
        filter(BudgetTemporalStatus.upcoming, kind: BudgetPeriodKind.yearly),
      );
      expect(yearlyOnly.items.map((item) => item.budget.id), [yearlyId]);

      final history = await budgets.loadBudgets(
        filter(BudgetTemporalStatus.history),
      );
      expect(history.items.map((item) => item.budget.id), [
        crossYearId,
        olderHistoryId,
      ]);
    },
  );

  test(
    'rejects invalid fields and unusable categories without partial rows',
    () async {
      final expenseGroups = await categoryGroups(CategoryKind.expense);
      final incomeGroups = await categoryGroups(CategoryKind.income);
      final activeLeaf = expenseGroups[1].children.single;
      final archivedLeaf = expenseGroups[0].children.single;
      await finance.setCategoryArchived(archivedLeaf.id, true);
      final period = BudgetPeriod.monthly(2024, 1);

      final invalidDrafts = [
        draft(period: period, name: '', categoryIds: {activeLeaf.id}),
        draft(
          period: period,
          name: 'Nol',
          categoryIds: {activeLeaf.id},
          limitAmount: 0,
        ),
        draft(
          period: period,
          name: 'Terlalu besar',
          categoryIds: {activeLeaf.id},
          limitAmount: maxAmount + 1,
        ),
        draft(period: period, name: 'Kosong', categoryIds: const {}),
        draft(
          period: period,
          name: 'Kelompok induk',
          categoryIds: {expenseGroups[1].parent.id},
        ),
        draft(
          period: period,
          name: 'Pemasukan',
          categoryIds: {incomeGroups.first.children.single.id},
        ),
        draft(period: period, name: 'Arsip', categoryIds: {archivedLeaf.id}),
      ];

      for (final invalid in invalidDrafts) {
        await expectLater(
          budgets.createBudget(invalid),
          throwsA(validationError),
        );
      }
      expect(await db.select(db.budgets).get(), isEmpty);
      expect(await db.select(db.budgetCategories).get(), isEmpty);

      await budgets.createBudget(
        draft(period: period, name: 'Makan', categoryIds: {activeLeaf.id}),
      );
      await expectLater(
        budgets.createBudget(
          draft(
            period: BudgetPeriod.custom(20240101, 20240131),
            name: '  MAKAN ',
            categoryIds: {expenseGroups[2].children.single.id},
          ),
        ),
        throwsA(validationError),
      );
      expect(await db.select(db.budgets).get(), hasLength(1));
      expect(await db.select(db.budgetCategories).get(), hasLength(1));

      await expectLater(
        budgets.loadBudgets(
          filter(BudgetTemporalStatus.active, referenceDay: 20240230),
        ),
        throwsA(validationError),
      );
    },
  );

  test(
    'detects inclusive cross-kind overlap and rolls back a failed edit',
    () async {
      final expenseGroups = await categoryGroups(CategoryKind.expense);
      final first = expenseGroups[0].children.single.id;
      final second = expenseGroups[1].children.single.id;
      final third = expenseGroups[2].children.single.id;
      final fourth = expenseGroups[3].children.single.id;

      final januaryId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.monthly(2024, 1),
          name: 'Januari',
          categoryIds: {first},
        ),
      );
      final februaryId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.custom(20240201, 20240229),
          name: 'Februari kustom',
          categoryIds: {first},
        ),
      );
      await budgets.createBudget(
        draft(
          period: BudgetPeriod.monthly(2024, 1),
          name: 'Kategori berbeda',
          categoryIds: {second},
        ),
      );

      await expectLater(
        budgets.createBudget(
          draft(
            period: BudgetPeriod.yearly(2024),
            name: 'Tahunan bentrok',
            categoryIds: {first},
          ),
        ),
        throwsA(validationError),
      );

      await budgets.createBudget(
        draft(
          period: BudgetPeriod.yearly(2025),
          name: 'Tahunan 2025',
          categoryIds: {fourth},
        ),
      );
      await expectLater(
        budgets.createBudget(
          draft(
            period: BudgetPeriod.custom(20250601, 20250630),
            name: 'Kustom tengah tahun',
            categoryIds: {fourth},
          ),
        ),
        throwsA(validationError),
      );

      final spanningPeriod = BudgetPeriod.custom(20240131, 20240201);
      final spanningId = await budgets.createBudget(
        draft(
          period: spanningPeriod,
          name: 'Lintas batas',
          categoryIds: {third},
          limitAmount: 300,
        ),
      );
      final conflicts = await budgets
          .watchCategoryConflicts(spanningPeriod, excludingBudgetId: spanningId)
          .first;
      expect(conflicts[first]!.map((item) => item.budgetId), [
        januaryId,
        februaryId,
      ]);

      await expectLater(
        budgets.updateBudget(
          spanningId,
          BudgetUpdateDraft(
            name: 'Nama yang tidak boleh tersimpan',
            limitAmount: 999,
            categoryIds: {third, first},
          ),
        ),
        throwsA(validationError),
      );
      final unchanged = await budgets.getBudget(spanningId);
      expect(unchanged!.budget.name, 'Lintas batas');
      expect(unchanged.budget.limitAmount, 300);
      expect(unchanged.categories.map((item) => item.id), [third]);
    },
  );

  test(
    'archived child and parent retain progress but cannot be re-added',
    () async {
      final expenseGroups = await categoryGroups(CategoryKind.expense);
      final archivedChild = expenseGroups[0].children.single;
      final parentArchivedChild = expenseGroups[1].children.single;
      final activeChild = expenseGroups[2].children.single;
      final accountId = await createAccount();
      final budgetId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.monthly(2024, 1),
          name: 'Arsip historis',
          categoryIds: {
            archivedChild.id,
            parentArchivedChild.id,
            activeChild.id,
          },
          limitAmount: 1000,
        ),
      );
      await finance.addEntry(
        EntryDraft.withAllocations(
          kind: EntryKind.expense,
          accountId: accountId,
          allocations: [
            EntryAllocationDraft(categoryId: archivedChild.id, amount: 100),
            EntryAllocationDraft(
              categoryId: parentArchivedChild.id,
              amount: 200,
            ),
            EntryAllocationDraft(categoryId: activeChild.id, amount: 300),
          ],
          occurredAt: DateTime(2024, 1, 15),
        ),
      );

      await finance.setCategoryArchived(archivedChild.id, true);
      await finance.setCategoryArchived(expenseGroups[1].parent.id, true);
      var snapshot = await budgets.loadBudgets(
        filter(BudgetTemporalStatus.active),
      );
      expect(snapshot.items.single.spentAmount, 600);
      final categoryState = {
        for (final item in snapshot.items.single.categories)
          item.id: item.effectiveIsArchived,
      };
      expect(categoryState[archivedChild.id], isTrue);
      expect(categoryState[parentArchivedChild.id], isTrue);
      expect(categoryState[activeChild.id], isFalse);

      await budgets.updateBudget(
        budgetId,
        BudgetUpdateDraft(
          name: 'Arsip historis',
          limitAmount: 1000,
          categoryIds: {parentArchivedChild.id, activeChild.id},
        ),
      );
      await expectLater(
        budgets.updateBudget(
          budgetId,
          BudgetUpdateDraft(
            name: 'Arsip historis',
            limitAmount: 1000,
            categoryIds: {
              archivedChild.id,
              parentArchivedChild.id,
              activeChild.id,
            },
          ),
        ),
        throwsA(validationError),
      );

      await budgets.updateBudget(
        budgetId,
        BudgetUpdateDraft(
          name: 'Arsip historis',
          limitAmount: 1000,
          categoryIds: {activeChild.id},
        ),
      );
      await expectLater(
        budgets.updateBudget(
          budgetId,
          BudgetUpdateDraft(
            name: 'Arsip historis',
            limitAmount: 1000,
            categoryIds: {parentArchivedChild.id, activeChild.id},
          ),
        ),
        throwsA(validationError),
      );
      snapshot = await budgets.loadBudgets(filter(BudgetTemporalStatus.active));
      expect(snapshot.items.single.spentAmount, 300);
      expect(snapshot.items.single.categories.map((item) => item.id), [
        activeChild.id,
      ]);
    },
  );

  test(
    'progress watches split allocations without counting the header twice',
    () async {
      final expenseGroups = await categoryGroups(CategoryKind.expense);
      final mealId = expenseGroups[0].children.single.id;
      final parkingId = expenseGroups[1].children.single.id;
      final accountId = await createAccount();
      await budgets.createBudget(
        draft(
          period: BudgetPeriod.monthly(2024, 1),
          name: 'Makan',
          categoryIds: {mealId},
          limitAmount: 20000,
        ),
      );
      await budgets.createBudget(
        draft(
          period: BudgetPeriod.monthly(2024, 1),
          name: 'Parkir',
          categoryIds: {parkingId},
          limitAmount: 10000,
        ),
      );

      final iterator = StreamIterator(
        budgets.watchBudgets(filter(BudgetTemporalStatus.active)),
      );
      addTearDown(iterator.cancel);
      expect(await iterator.moveNext(), isTrue);
      expect(
        iterator.current.items.every((item) => item.spentAmount == 0),
        isTrue,
      );

      final entryId = await finance.addEntry(
        EntryDraft.withAllocations(
          kind: EntryKind.expense,
          accountId: accountId,
          allocations: [
            EntryAllocationDraft(categoryId: mealId, amount: 15000),
            EntryAllocationDraft(categoryId: parkingId, amount: 2000),
          ],
          occurredAt: DateTime(2024, 1, 15),
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      var values = byName(iterator.current);
      expect(values['Makan']!.spentAmount, 15000);
      expect(values['Parkir']!.spentAmount, 2000);
      expect(iterator.current.groups.single.totalSpent, 17000);

      await finance.updateEntry(
        entryId,
        EntryDraft.withAllocations(
          kind: EntryKind.expense,
          accountId: accountId,
          allocations: [
            EntryAllocationDraft(categoryId: mealId, amount: 12000),
            EntryAllocationDraft(categoryId: parkingId, amount: 3000),
          ],
          occurredAt: DateTime(2024, 1, 1),
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      values = byName(iterator.current);
      expect(values['Makan']!.spentAmount, 12000);
      expect(values['Parkir']!.spentAmount, 3000);

      await finance.updateEntry(
        entryId,
        EntryDraft.withAllocations(
          kind: EntryKind.expense,
          accountId: accountId,
          allocations: [
            EntryAllocationDraft(categoryId: mealId, amount: 12000),
            EntryAllocationDraft(categoryId: parkingId, amount: 3000),
          ],
          occurredAt: DateTime(2024, 1, 31),
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      values = byName(iterator.current);
      expect(values['Makan']!.spentAmount, 12000);
      expect(values['Parkir']!.spentAmount, 3000);

      await finance.updateEntry(
        entryId,
        EntryDraft.withAllocations(
          kind: EntryKind.expense,
          accountId: accountId,
          allocations: [
            EntryAllocationDraft(categoryId: mealId, amount: 12000),
            EntryAllocationDraft(categoryId: parkingId, amount: 3000),
          ],
          occurredAt: DateTime(2024, 2, 1),
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      expect(
        iterator.current.items.every((item) => item.spentAmount == 0),
        isTrue,
      );
    },
  );

  test('detail and conflict streams react to update and delete', () async {
    final expenseGroups = await categoryGroups(CategoryKind.expense);
    final categoryId = expenseGroups.first.children.single.id;
    final period = BudgetPeriod.monthly(2024, 1);
    final budgetId = await budgets.createBudget(
      draft(
        period: period,
        name: 'Awal',
        categoryIds: {categoryId},
        limitAmount: 100,
      ),
    );
    final detailIterator = StreamIterator(budgets.watchBudget(budgetId));
    final conflictIterator = StreamIterator(
      budgets.watchCategoryConflicts(period),
    );
    addTearDown(detailIterator.cancel);
    addTearDown(conflictIterator.cancel);

    expect(await detailIterator.moveNext(), isTrue);
    expect(detailIterator.current!.budget.name, 'Awal');
    expect(await conflictIterator.moveNext(), isTrue);
    expect(conflictIterator.current[categoryId]!.single.budgetName, 'Awal');

    await budgets.updateBudget(
      budgetId,
      BudgetUpdateDraft(
        name: 'Berubah',
        limitAmount: 200,
        categoryIds: {categoryId},
      ),
    );
    expect(await detailIterator.moveNext(), isTrue);
    expect(detailIterator.current!.budget.name, 'Berubah');
    expect(detailIterator.current!.budget.limitAmount, 200);
    expect(await conflictIterator.moveNext(), isTrue);
    expect(conflictIterator.current[categoryId]!.single.budgetName, 'Berubah');

    await budgets.deleteBudget(budgetId);
    expect(await detailIterator.moveNext(), isTrue);
    expect(detailIterator.current, isNull);
    expect(await conflictIterator.moveNext(), isTrue);
    expect(conflictIterator.current, isEmpty);
  });

  test('groups active budgets by range and ranks worst usage first', () async {
    final expenseGroups = await categoryGroups(CategoryKind.expense);
    final categoryIds = [
      for (final group in expenseGroups.take(4)) group.children.single.id,
    ];
    final accountId = await createAccount();

    await budgets.createBudget(
      draft(
        period: BudgetPeriod.monthly(2024, 1),
        name: 'Alpha',
        categoryIds: {categoryIds[0]},
        limitAmount: 100,
      ),
    );
    await budgets.createBudget(
      draft(
        period: BudgetPeriod.monthly(2024, 1),
        name: 'Zulu',
        categoryIds: {categoryIds[1]},
        limitAmount: 100,
      ),
    );
    await budgets.createBudget(
      draft(
        period: BudgetPeriod.custom(20240105, 20240125),
        name: 'Middle',
        categoryIds: {categoryIds[2]},
        limitAmount: 100,
      ),
    );
    await budgets.createBudget(
      draft(
        period: BudgetPeriod.custom(20240110, 20240120),
        name: 'Normal',
        categoryIds: {categoryIds[3]},
        limitAmount: 100,
      ),
    );
    await finance.addEntry(
      EntryDraft.singleAllocation(
        kind: EntryKind.expense,
        accountId: accountId,
        amount: 150,
        categoryId: categoryIds[1],
        occurredAt: DateTime(2024, 1, 15),
      ),
    );
    await finance.addEntry(
      EntryDraft.singleAllocation(
        kind: EntryKind.expense,
        accountId: accountId,
        amount: 100,
        categoryId: categoryIds[2],
        occurredAt: DateTime(2024, 1, 15),
      ),
    );

    final snapshot = await budgets.loadBudgets(
      filter(BudgetTemporalStatus.active),
    );
    expect(snapshot.items.map((item) => item.budget.name), [
      'Zulu',
      'Alpha',
      'Middle',
      'Normal',
    ]);
    expect(snapshot.groups.map((group) => (group.startDay, group.endDay)), [
      (20240101, 20240131),
      (20240105, 20240125),
      (20240110, 20240120),
    ]);
    expect(snapshot.groups.first.totalLimit, 200);
    expect(snapshot.groups.first.totalSpent, 150);
    expect(snapshot.groups.first.countForStatus(BudgetUsageStatus.exceeded), 1);
    expect(snapshot.groups.first.countForStatus(BudgetUsageStatus.normal), 1);
  });

  test(
    'delete cascades mappings but preserves categories and ledger',
    () async {
      final expenseGroups = await categoryGroups(CategoryKind.expense);
      final categoryId = expenseGroups.first.children.single.id;
      final accountId = await createAccount();
      final budgetId = await budgets.createBudget(
        draft(
          period: BudgetPeriod.monthly(2024, 1),
          name: 'Sementara',
          categoryIds: {categoryId},
        ),
      );
      await finance.addEntry(
        EntryDraft.singleAllocation(
          kind: EntryKind.expense,
          accountId: accountId,
          amount: 500,
          categoryId: categoryId,
          occurredAt: DateTime(2024, 1, 15),
        ),
      );
      final categoryCount = (await db.select(db.categories).get()).length;

      await budgets.deleteBudget(budgetId);

      expect(await budgets.getBudget(budgetId), isNull);
      expect(await db.select(db.budgetCategories).get(), isEmpty);
      expect((await db.select(db.categories).get()).length, categoryCount);
      expect(await db.select(db.ledgerEntries).get(), hasLength(1));
      expect(await db.select(db.ledgerAllocations).get(), hasLength(1));
    },
  );
}
