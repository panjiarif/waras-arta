import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/database/app_database.dart';
import 'package:waras_arta/data/repositories/drift_finance_repository.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
  const incomeCategoryId = 2;
  const expenseCategoryId = 10;
  late AppDatabase db;
  var sharedDatabaseClosed = false;
  late DriftFinanceRepository repository;
  final january = DateTime(2024, 1);
  final february = DateTime(2024, 2);
  final validationError = isA<FinanceValidationException>();

  Future<int> account(String name, {int opening = 0}) =>
      repository.createAccount(
        AccountDraft(
          name: name,
          type: AccountType.bank,
          openingBalance: opening,
          openedAt: january,
        ),
      );

  EntryDraft entry(
    int accountId, {
    EntryKind kind = EntryKind.income,
    int amount = 100,
    int? destination,
    DateTime? date,
    int? categoryId,
  }) => EntryDraft(
    kind: kind,
    accountId: accountId,
    destinationAccountId: destination,
    amount: amount,
    categoryId:
        categoryId ??
        (kind == EntryKind.income
            ? incomeCategoryId
            : kind == EntryKind.expense
            ? expenseCategoryId
            : null),
    occurredAt: date ?? january,
  );

  setUp(() {
    sharedDatabaseClosed = false;
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftFinanceRepository(db);
  });

  tearDown(() async {
    if (!sharedDatabaseClosed) await db.close();
  });

  test('empty database has a zero, immutable snapshot', () async {
    final snapshot = await repository.loadMonth(january);
    expect(snapshot.accounts, isEmpty);
    expect(snapshot.entries, isEmpty);
    expect(snapshot.income, 0);
    expect(snapshot.expense, 0);
    expect(snapshot.totalBalance, 0);
    expect(snapshot.totalEntries, 0);
    expect(snapshot.hasMore, isFalse);
    expect(() => snapshot.entries.clear(), throwsUnsupportedError);
  });

  test('empty calendar month and day are immutable', () async {
    final month = await repository.watchCalendarMonth(january).first;
    final day = await repository.watchDay(DateTime(2024, 1, 15, 18, 30)).first;

    expect(month.month, DateTime(2024, 1));
    expect(month.days, isEmpty);
    expect(month.totalIncome, 0);
    expect(month.totalExpense, 0);
    expect(month.totalTransferCount, 0);
    expect(month.totalAdjustmentCount, 0);
    expect(month.totalEntryCount, 0);
    expect(month.activeDayCount, 0);
    expect(month.net, 0);
    expect(month.summaryForDay(DateTime(2024, 1, 15)), isNull);
    expect(() => month.days.clear(), throwsUnsupportedError);
    expect(day, isEmpty);
    expect(() => day.clear(), throwsUnsupportedError);
  });

  test('calendar aggregates all entry kinds without treating transfers or '
      'signed adjustments as cashflow', () async {
    final source = await account('Sumber');
    final destination = await account('Tujuan');
    final firstDay = DateTime(2024, 1, 10);
    final secondDay = DateTime(2024, 1, 11);

    await repository.adjustAccountBalance(
      source,
      AccountBalanceAdjustmentDraft(targetBalance: 50, occurredAt: firstDay),
    );
    await repository.adjustAccountBalance(
      source,
      AccountBalanceAdjustmentDraft(targetBalance: -10, occurredAt: firstDay),
    );
    await repository.addEntry(entry(source, amount: 500, date: firstDay));
    await repository.addEntry(
      entry(source, kind: EntryKind.expense, amount: 125, date: firstDay),
    );
    await repository.addEntry(
      entry(
        source,
        kind: EntryKind.transfer,
        amount: 40,
        destination: destination,
        date: firstDay,
      ),
    );
    await repository.addEntry(entry(source, amount: 200, date: secondDay));

    final snapshot = await repository.watchCalendarMonth(january).first;
    expect(snapshot.days.map((summary) => summary.day), [firstDay, secondDay]);
    final first = snapshot.summaryForDay(DateTime.utc(2024, 1, 10, 23, 59));
    expect(first?.income, 500);
    expect(first?.expense, 125);
    expect(first?.net, 375);
    expect(first?.transferCount, 1);
    expect(first?.adjustmentCount, 2);
    expect(first?.entryCount, 5);
    expect(snapshot.totalIncome, 700);
    expect(snapshot.totalExpense, 125);
    expect(snapshot.totalTransferCount, 1);
    expect(snapshot.totalAdjustmentCount, 2);
    expect(snapshot.totalEntryCount, 6);
    expect(snapshot.activeDayCount, 2);
    expect(snapshot.net, 575);

    final adjustments = (await repository.watchDay(firstDay).first)
        .where((item) => item.kind == EntryKind.adjustment)
        .map((item) => item.amount);
    expect(adjustments, containsAll(<int>[50, -60]));
  });

  test(
    'calendar aggregation is complete beyond the 50-entry history page',
    () async {
      final id = await account('Bank');
      for (var index = 0; index < 60; index++) {
        await repository.addEntry(
          entry(id, amount: 100, date: DateTime(2024, 1, 10)),
        );
      }

      final history = await repository.loadMonth(january);
      final calendar = await repository.watchCalendarMonth(january).first;
      final selectedDay = await repository
          .watchDay(DateTime(2024, 1, 10))
          .first;

      expect(history.entries, hasLength(50));
      expect(history.totalEntries, 60);
      expect(history.hasMore, isTrue);
      expect(calendar.totalEntryCount, 60);
      expect(calendar.totalIncome, 6000);
      expect(calendar.activeDayCount, 1);
      expect(calendar.summaryForDay(DateTime(2024, 1, 10))?.entryCount, 60);
      expect(selectedDay, hasLength(60));
      expect(
        selectedDay.map((item) => item.id),
        orderedEquals(
          selectedDay.map((item) => item.id).toList()
            ..sort((a, b) => b.compareTo(a)),
        ),
      );
    },
  );

  test('watchDay filters one civil day, includes category metadata, and sorts '
      'newest first', () async {
    final source = await account('Sumber');
    final destination = await account('Tujuan');
    final selectedDay = DateTime(2024, 1, 15);
    final incomeId = await repository.addEntry(
      entry(source, amount: 300, date: selectedDay),
    );
    await repository.addEntry(
      entry(source, amount: 999, date: DateTime(2024, 1, 16)),
    );
    final expenseId = await repository.addEntry(
      entry(source, kind: EntryKind.expense, amount: 75, date: selectedDay),
    );
    final transferId = await repository.addEntry(
      entry(
        source,
        kind: EntryKind.transfer,
        amount: 25,
        destination: destination,
        date: selectedDay,
      ),
    );

    final entries = await repository
        .watchDay(DateTime.utc(2024, 1, 15, 23, 59, 59))
        .first;
    expect(entries.map((item) => item.id), [transferId, expenseId, incomeId]);
    expect(entries.every((item) => item.occurredAt == selectedDay), isTrue);

    final income = entries.singleWhere((item) => item.id == incomeId);
    expect(income.categoryName, 'Umum');
    expect(income.parentCategoryName, 'Gaji');
    expect(income.categoryIconKey, 'work');
    final expense = entries.singleWhere((item) => item.id == expenseId);
    expect(expense.categoryName, 'Umum');
    expect(expense.parentCategoryName, 'Makan & minum');
    expect(expense.categoryIconKey, 'restaurant');
    final transfer = entries.singleWhere((item) => item.id == transferId);
    expect(transfer.categoryId, isNull);
    expect(transfer.categoryName, isNull);
  });

  test('calendar read dates are normalized and bounded', () async {
    final normalizedMonth = await repository
        .watchCalendarMonth(DateTime.utc(2024, 1, 31, 23, 59))
        .first;
    expect(normalizedMonth.month, DateTime(2024, 1));
    expect(
      (await repository.watchCalendarMonth(DateTime.now()).first).month,
      DateTime(DateTime.now().year, DateTime.now().month),
    );

    expect(
      () => repository.watchCalendarMonth(DateTime(1999, 12)),
      throwsA(validationError),
    );
    expect(
      () => repository.watchCalendarMonth(
        DateTime(DateTime.now().year, DateTime.now().month + 1),
      ),
      throwsA(validationError),
    );
    expect(
      () => repository.watchDay(DateTime(1999, 12, 31)),
      throwsA(validationError),
    );
    expect(
      () => repository.watchDay(
        DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day + 1,
        ),
      ),
      throwsA(validationError),
    );
    expect(
      () => repository.loadMonth(DateTime(1999, 12)),
      throwsA(validationError),
    );
  });

  test('calendar month and selected day react to ledger writes', () async {
    final id = await account('Bank');
    final selectedDay = DateTime(2024, 1, 20);
    final monthAdded = repository
        .watchCalendarMonth(january)
        .firstWhere((snapshot) => snapshot.totalEntryCount == 1);
    final dayAdded = repository
        .watchDay(selectedDay)
        .firstWhere((entries) => entries.length == 1);

    final entryId = await repository.addEntry(
      entry(id, amount: 450, date: selectedDay),
    );
    final added = await Future.wait([
      monthAdded.timeout(const Duration(seconds: 5)),
      dayAdded.timeout(const Duration(seconds: 5)),
    ]);
    expect((added[0] as CalendarMonthSnapshot).totalIncome, 450);
    expect((added[1] as List<FinanceEntry>).single.id, entryId);

    final monthDeleted = repository
        .watchCalendarMonth(january)
        .firstWhere((snapshot) => snapshot.totalEntryCount == 0);
    final dayDeleted = repository
        .watchDay(selectedDay)
        .firstWhere((entries) => entries.isEmpty);
    await repository.deleteEntry(entryId);
    final deleted = await Future.wait([
      monthDeleted.timeout(const Duration(seconds: 5)),
      dayDeleted.timeout(const Duration(seconds: 5)),
    ]);
    expect((deleted[0] as CalendarMonthSnapshot).days, isEmpty);
    expect(deleted[1], isEmpty);
  });

  test(
    'calendar reacts when an edit moves an entry to another month',
    () async {
      final id = await account('Bank');
      final oldDay = DateTime(2024, 1, 20);
      final newDay = DateTime(2024, 2, 2);
      final entryId = await repository.addEntry(
        entry(id, amount: 450, date: oldDay),
      );

      final oldMonthUpdated = repository
          .watchCalendarMonth(january)
          .firstWhere((snapshot) => snapshot.totalEntryCount == 0);
      final oldDayUpdated = repository
          .watchDay(oldDay)
          .firstWhere((entries) => entries.isEmpty);
      final newMonthUpdated = repository
          .watchCalendarMonth(february)
          .firstWhere((snapshot) => snapshot.totalEntryCount == 1);
      final newDayUpdated = repository
          .watchDay(newDay)
          .firstWhere((entries) => entries.length == 1);

      await repository.updateEntry(
        entryId,
        entry(id, amount: 900, date: newDay),
      );
      final updated = await Future.wait([
        oldMonthUpdated.timeout(const Duration(seconds: 5)),
        oldDayUpdated.timeout(const Duration(seconds: 5)),
        newMonthUpdated.timeout(const Duration(seconds: 5)),
        newDayUpdated.timeout(const Duration(seconds: 5)),
      ]);

      expect((updated[0] as CalendarMonthSnapshot).days, isEmpty);
      expect(updated[1], isEmpty);
      expect((updated[2] as CalendarMonthSnapshot).totalIncome, 900);
      expect((updated[3] as List<FinanceEntry>).single.id, entryId);
    },
  );

  test(
    'opening balance is traceable and excluded from monthly income',
    () async {
      final id = await account('  Bank   utama  ', opening: 1000000);
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.accounts.single.id, id);
      expect(snapshot.accounts.single.name, 'Bank utama');
      expect(snapshot.accounts.single.balance, 1000000);
      expect(snapshot.entries.single.kind, EntryKind.adjustment);
      expect(snapshot.entries.single.amount, 1000000);
      expect(snapshot.income, 0);
      expect(snapshot.expense, 0);
      expect(snapshot.totalEntries, 1);
    },
  );

  test(
    'zero opening creates an account without a zero-value transaction',
    () async {
      await account('Dompet');
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.accounts.single.balance, 0);
      expect(snapshot.entries, isEmpty);
    },
  );

  test(
    'income and expense use integer amounts and allow negative balances',
    () async {
      final id = await account('Dompet');
      await repository.addEntry(entry(id, amount: 1000));
      await repository.addEntry(
        entry(id, kind: EntryKind.expense, amount: 1501),
      );
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.income, 1000);
      expect(snapshot.expense, 1501);
      expect(snapshot.net, -501);
      expect(snapshot.accounts.single.balance, -501);
      expect(snapshot.totalBalance, -501);
    },
  );

  test(
    'transfer is one row and neutral to total balance and cashflow',
    () async {
      final source = await account('Bank', opening: 1000);
      final destination = await account('Tunai');
      await repository.addEntry(
        entry(
          source,
          kind: EntryKind.transfer,
          amount: 300,
          destination: destination,
        ),
      );
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.accounts.firstWhere((a) => a.id == source).balance, 700);
      expect(
        snapshot.accounts.firstWhere((a) => a.id == destination).balance,
        300,
      );
      expect(snapshot.totalBalance, 1000);
      expect(snapshot.income, 0);
      expect(snapshot.expense, 0);
      expect(
        snapshot.entries.where((e) => e.kind == EntryKind.transfer).length,
        1,
      );
      expect(snapshot.totalEntries, 2);
    },
  );

  test(
    'backdated transfer may overdraw source without altering total funds',
    () async {
      final source = await account('Source');
      final destination = await account('Destination');
      await repository.addEntry(
        entry(
          source,
          kind: EntryKind.transfer,
          amount: 10,
          destination: destination,
        ),
      );
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.accounts.firstWhere((a) => a.id == source).balance, -10);
      expect(
        snapshot.accounts.firstWhere((a) => a.id == destination).balance,
        10,
      );
      expect(snapshot.totalBalance, 0);
    },
  );

  test(
    'monthly civil dates respect boundaries and balances remain all-time',
    () async {
      final id = await account('Bank');
      await repository.addEntry(
        entry(id, amount: 500, date: DateTime(2024, 2, 1)),
      );
      await repository.addEntry(
        entry(id, amount: 200, date: DateTime.utc(2024, 1, 31, 23, 59)),
      );
      await repository.addEntry(
        entry(
          id,
          kind: EntryKind.expense,
          amount: 30,
          date: DateTime(2024, 2, 29),
        ),
      );
      final jan = await repository.loadMonth(january);
      final feb = await repository.loadMonth(february);
      expect(jan.income, 200);
      expect(jan.entries.single.occurredAt, DateTime(2024, 1, 31));
      expect(
        jan.entries.single.createdAt.isAfter(DateTime(2024, 1, 31)),
        isTrue,
      );
      expect(feb.income, 500);
      expect(feb.expense, 30);
      expect(feb.entries.first.occurredAt, DateTime(2024, 2, 29));
      expect(jan.totalBalance, 670);
      expect(feb.totalBalance, 670);
    },
  );

  test(
    'list limit does not truncate totals and ordering is date then id',
    () async {
      final id = await account('Bank');
      final first = await repository.addEntry(
        entry(id, date: DateTime(2024, 1, 20)),
      );
      final second = await repository.addEntry(
        entry(id, date: DateTime(2024, 1, 20)),
      );
      await repository.addEntry(entry(id, date: DateTime(2024, 1, 2)));
      final limited = await repository.loadMonth(january, limit: 2);
      expect(limited.entries.map((e) => e.id), [second, first]);
      expect(limited.income, 300);
      expect(limited.totalEntries, 3);
      expect(limited.hasMore, isTrue);
      final expanded = await repository.loadMonth(january, limit: 3);
      expect(expanded.entries.length, 3);
      expect(expanded.hasMore, isFalse);
      expect(
        () => repository.loadMonth(january, limit: 0),
        throwsA(validationError),
      );
      expect(
        (await repository.loadMonth(january, limit: 1001)).entries.length,
        3,
      );
    },
  );

  test('fresh schema seeds two-level built-in category trees', () async {
    final id = await account('Bank');
    final income = await repository
        .watchCategoryTree(CategoryKind.income)
        .first;
    final expense = await repository
        .watchCategoryTree(CategoryKind.expense)
        .first;
    expect(income, hasLength(4));
    expect(expense, hasLength(7));
    expect(income.every((group) => group.children.length == 1), isTrue);
    expect(expense.every((group) => group.children.length == 1), isTrue);
    expect(
      income
          .expand((group) => group.children)
          .every((child) => child.name == 'Umum'),
      isTrue,
    );
    expect(
      expense
          .expand((group) => group.children)
          .every((child) => child.name == 'Umum'),
      isTrue,
    );
    for (final child in income.expand((group) => group.children)) {
      await repository.addEntry(entry(id, categoryId: child.id));
    }
    for (final child in expense.expand((group) => group.children)) {
      await repository.addEntry(
        entry(id, kind: EntryKind.expense, categoryId: child.id),
      );
    }
    final snapshot = await repository.loadMonth(january);
    expect(snapshot.income, 100 * income.length);
    expect(snapshot.expense, 100 * expense.length);
    expect(
      snapshot.entries.every((item) => item.categoryName == 'Umum'),
      isTrue,
    );
    expect(
      snapshot.entries.every((item) => item.parentCategoryName != null),
      isTrue,
    );
  });

  test('category group creation is atomic and normalizes names', () async {
    final changed = repository
        .watchCategoryTree(CategoryKind.expense)
        .firstWhere(
          (groups) => groups.any((group) => group.parent.name == 'Rumah'),
        );
    final parentId = await repository.createCategoryGroup(
      const CategoryGroupDraft(
        kind: CategoryKind.expense,
        parentName: '  Rumah  ',
        parentIconKey: 'home',
        firstChildName: '  Umum   rumah ',
        firstChildIconKey: 'receipt_long',
      ),
    );
    final tree = await changed.timeout(const Duration(seconds: 5));
    final group = tree.singleWhere((item) => item.parent.id == parentId);
    expect(group.parent.name, 'Rumah');
    expect(group.parent.kind, CategoryKind.expense);
    expect(group.children.single.name, 'Umum rumah');
    expect(group.children.single.parentId, parentId);

    await expectLater(
      repository.createCategoryGroup(
        const CategoryGroupDraft(
          kind: CategoryKind.expense,
          parentName: ' rumah ',
          parentIconKey: 'category',
          firstChildName: 'Umum',
          firstChildIconKey: 'category',
        ),
      ),
      throwsA(validationError),
    );
    await expectLater(
      repository.createCategoryGroup(
        const CategoryGroupDraft(
          kind: CategoryKind.income,
          parentName: 'Tidak jadi',
          parentIconKey: 'work',
          firstChildName: 'Umum',
          firstChildIconKey: 'not-an-icon',
        ),
      ),
      throwsA(validationError),
    );
    final income = await repository
        .watchCategoryTree(CategoryKind.income)
        .first;
    expect(income.any((item) => item.parent.name == 'Tidak jadi'), isFalse);

    await db.customStatement('''
      CREATE TRIGGER reject_test_child BEFORE INSERT ON categories
      WHEN NEW.parent_id IS NOT NULL AND NEW.name = 'Gagal'
      BEGIN SELECT RAISE(ABORT, 'test child failed'); END
    ''');
    await expectLater(
      repository.createCategoryGroup(
        const CategoryGroupDraft(
          kind: CategoryKind.income,
          parentName: 'Harus rollback',
          parentIconKey: 'payments',
          firstChildName: 'Gagal',
          firstChildIconKey: 'payments',
        ),
      ),
      throwsA(anything),
    );
    final afterRollback = await repository
        .watchCategoryTree(CategoryKind.income)
        .first;
    expect(
      afterRollback.any((item) => item.parent.name == 'Harus rollback'),
      isFalse,
    );
  });

  test(
    'subcategory CRUD keeps structure and transaction labels reactive',
    () async {
      final accountId = await account('Bank');
      final parentId = await repository.createCategoryGroup(
        const CategoryGroupDraft(
          kind: CategoryKind.expense,
          parentName: 'Rumah',
          parentIconKey: 'home',
          firstChildName: 'Umum',
          firstChildIconKey: 'home',
        ),
      );
      final childId = await repository.createSubcategory(
        CategoryDraft(
          parentId: parentId,
          name: 'Listrik',
          iconKey: 'receipt_long',
          sortOrder: 2,
        ),
      );
      final entryId = await repository.addEntry(
        entry(accountId, kind: EntryKind.expense, categoryId: childId),
      );
      final renamed = repository
          .watchEntry(entryId)
          .firstWhere(
            (item) =>
                item?.categoryName == 'Listrik PLN' &&
                item?.parentCategoryName == 'Kebutuhan rumah' &&
                item?.categoryIconKey == 'payments',
          );

      await repository.updateCategory(
        parentId,
        const CategoryDraft(
          parentId: null,
          name: 'Kebutuhan rumah',
          iconKey: 'home',
          sortOrder: 3,
        ),
      );
      await repository.updateCategory(
        childId,
        CategoryDraft(
          parentId: parentId,
          name: '  Listrik   PLN ',
          iconKey: 'payments',
          sortOrder: 4,
        ),
      );

      final detail = await renamed.timeout(const Duration(seconds: 5));
      expect(detail?.categoryId, childId);
      expect(detail?.categoryArchived, isFalse);
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.entries.single.categoryName, 'Listrik PLN');
      expect(snapshot.entries.single.parentCategoryName, 'Kebutuhan rumah');

      await expectLater(
        repository.createSubcategory(
          CategoryDraft(
            parentId: parentId,
            name: ' listrik   pln ',
            iconKey: 'category',
          ),
        ),
        throwsA(validationError),
      );
      await expectLater(
        repository.createSubcategory(
          CategoryDraft(
            parentId: childId,
            name: 'Level tiga',
            iconKey: 'category',
          ),
        ),
        throwsA(validationError),
      );
      await expectLater(
        repository.updateCategory(
          childId,
          const CategoryDraft(
            parentId: 9,
            name: 'Dipindah',
            iconKey: 'category',
          ),
        ),
        throwsA(validationError),
      );
    },
  );

  test(
    'archiving preserves labels and blocks new use of inactive leaves',
    () async {
      final accountId = await account('Bank');
      final entryId = await repository.addEntry(entry(accountId));
      final archivedDetail = repository
          .watchEntry(entryId)
          .firstWhere((item) => item?.categoryArchived == true);
      final archivedMonth = repository
          .watchMonth(january)
          .firstWhere((snapshot) => snapshot.entries.single.categoryArchived);

      await repository.setCategoryArchived(incomeCategoryId, true);

      expect(
        (await archivedDetail.timeout(const Duration(seconds: 5)))
            ?.categoryName,
        'Umum',
      );
      expect(
        (await archivedMonth.timeout(const Duration(seconds: 5)))
            .entries
            .single
            .parentCategoryName,
        'Gaji',
      );
      await expectLater(
        repository.addEntry(entry(accountId)),
        throwsA(validationError),
      );
      await repository.updateEntry(
        entryId,
        entry(accountId, amount: 125, categoryId: incomeCategoryId),
      );
      expect((await repository.watchEntry(entryId).first)?.amount, 125);

      final activeTree = await repository
          .watchCategoryTree(CategoryKind.income)
          .first;
      expect(
        activeTree.singleWhere((group) => group.parent.name == 'Gaji').children,
        isEmpty,
      );
      final fullTree = await repository
          .watchCategoryTree(CategoryKind.income, includeArchived: true)
          .first;
      expect(
        fullTree
            .singleWhere((group) => group.parent.name == 'Gaji')
            .children
            .single
            .isArchived,
        isTrue,
      );
    },
  );

  test('archive guard retains one effective leaf for each kind', () async {
    final income = await repository
        .watchCategoryTree(CategoryKind.income)
        .first;
    for (final group in income.take(income.length - 1)) {
      await repository.setCategoryArchived(group.parent.id, true);
    }
    final last = income.last;
    await expectLater(
      repository.setCategoryArchived(last.parent.id, true),
      throwsA(validationError),
    );
    await expectLater(
      repository.setCategoryArchived(last.children.single.id, true),
      throwsA(validationError),
    );

    await repository.setCategoryArchived(income.first.children.single.id, true);
    await expectLater(
      repository.setCategoryArchived(income.first.parent.id, false),
      throwsA(validationError),
    );
    await repository.setCategoryArchived(
      income.first.children.single.id,
      false,
    );
    await repository.setCategoryArchived(income.first.parent.id, false);
    final active = await repository
        .watchCategoryTree(CategoryKind.income)
        .first;
    expect(active.expand((group) => group.children), isNotEmpty);
  });

  test('database enforces category depth, kind, and sibling uniqueness', () async {
    Future<void> insertCategory({
      required int? parentId,
      required int kind,
      required String name,
    }) => db.customStatement(
      'INSERT INTO categories '
      '(parent_id, kind, name, normalized_name, icon_key, is_archived, '
      'sort_order, system_key, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, 0, 0, NULL, 0, 0)',
      [parentId, kind, name, name.toLowerCase(), 'category'],
    );

    await expectLater(
      insertCategory(parentId: incomeCategoryId, kind: 0, name: 'Level 3'),
      throwsA(anything),
    );
    await expectLater(
      insertCategory(parentId: 1, kind: 1, name: 'Wrong kind'),
      throwsA(anything),
    );
    await expectLater(
      insertCategory(parentId: null, kind: 0, name: 'gaji'),
      throwsA(anything),
    );
    await expectLater(
      insertCategory(parentId: 1, kind: 0, name: 'umum'),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement('UPDATE categories SET parent_id = 3 WHERE id = ?', [
        incomeCategoryId,
      ]),
      throwsA(anything),
    );

    final accountId = await account('Bank');
    await expectLater(
      db.customStatement(
        'INSERT INTO ledger_entries '
        '(kind, account_id, destination_account_id, amount, category_id, note, '
        'occurred_day, created_at) VALUES (0, ?, NULL, 10, 1, ?, 20240101, 0)',
        [accountId, 'root is not a leaf'],
      ),
      throwsA(anything),
    );
  });

  test('amount bounds reject zero, negative, and overflow entries', () async {
    final id = await account('Bank');
    for (final amount in [0, -1, maxAmount + 1]) {
      await expectLater(
        repository.addEntry(entry(id, amount: amount)),
        throwsA(validationError),
      );
    }
    await repository.addEntry(entry(id, amount: maxAmount));
    expect((await repository.loadMonth(january)).totalBalance, maxAmount);
    for (final amount in [-1, maxAmount + 1]) {
      await expectLater(
        account('Invalid $amount', opening: amount),
        throwsA(validationError),
      );
    }
  });

  test(
    'account names are trimmed, bounded, and unique ignoring case and spaces',
    () async {
      await account(' Bank  utama ');
      for (final name in ['bank UTAMA', '  ', 'x' * 81]) {
        await expectLater(account(name), throwsA(validationError));
      }
      expect((await repository.loadMonth(january)).accounts.length, 1);
    },
  );

  test(
    'invalid accounts and transfer shapes leave no partial balance changes',
    () async {
      final id = await account('Bank', opening: 1000);
      final destination = await account('Tunai');
      final invalid = [
        entry(id, kind: EntryKind.transfer),
        entry(id, kind: EntryKind.transfer, destination: id),
        entry(id, kind: EntryKind.transfer, destination: 999),
        entry(999, kind: EntryKind.transfer, destination: destination),
        entry(
          id,
          kind: EntryKind.transfer,
          destination: destination,
          categoryId: incomeCategoryId,
        ),
        entry(999),
        entry(id, destination: destination),
        entry(id, kind: EntryKind.adjustment),
        entry(id, categoryId: expenseCategoryId),
        entry(id, kind: EntryKind.expense, categoryId: incomeCategoryId),
      ];
      for (final draft in invalid) {
        await expectLater(repository.addEntry(draft), throwsA(validationError));
      }
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.totalBalance, 1000);
      expect(snapshot.totalEntries, 1);
      expect(
        snapshot.accounts.firstWhere((a) => a.id == destination).balance,
        0,
      );
    },
  );

  test(
    'dates before 2000 and future dates are rejected for accounts and entries',
    () async {
      final id = await account('Bank');
      for (final date in [
        DateTime(1999, 12, 31),
        DateTime.now().add(const Duration(days: 2)),
      ]) {
        await expectLater(
          repository.addEntry(entry(id, date: date)),
          throwsA(validationError),
        );
        await expectLater(
          repository.createAccount(
            AccountDraft(
              name: 'Invalid',
              type: AccountType.cash,
              openingBalance: 0,
              openedAt: date,
            ),
          ),
          throwsA(validationError),
        );
      }
      await repository.addEntry(entry(id, date: DateTime(2000, 1, 1)));
      expect((await repository.loadMonth(DateTime(2000, 1))).income, 100);
    },
  );

  test(
    'database independently rejects bad foreign keys, shapes, and amounts',
    () async {
      final id = await account('Bank');
      Future<void> insert({
        int kind = 2,
        int? destination,
        int amount = 10,
        int? categoryId,
      }) => db.customStatement(
        'INSERT INTO ledger_entries '
        '(kind, account_id, destination_account_id, amount, category_id, note, occurred_day, created_at) '
        "VALUES (?, ?, ?, ?, ?, '', 20240101, 0)",
        [kind, id, destination, amount, categoryId],
      );
      await expectLater(insert(destination: 999), throwsA(anything));
      await expectLater(insert(destination: id), throwsA(anything));
      await expectLater(insert(), throwsA(anything));
      await expectLater(
        insert(kind: 0, categoryId: incomeCategoryId, amount: 0),
        throwsA(anything),
      );
      await expectLater(
        insert(kind: 0, categoryId: incomeCategoryId, amount: maxAmount + 1),
        throwsA(anything),
      );
      await expectLater(
        insert(kind: 0, categoryId: expenseCategoryId),
        throwsA(anything),
      );
      await expectLater(insert(kind: 0), throwsA(anything));
      expect((await repository.loadMonth(january)).totalEntries, 0);
    },
  );

  test('opening balance failure rolls back newly inserted account', () async {
    await db.customStatement('''
      CREATE TRIGGER reject_opening BEFORE INSERT ON ledger_entries
      BEGIN SELECT RAISE(ABORT, 'test opening failed'); END
    ''');
    await expectLater(account('Bank', opening: 100), throwsA(anything));
    final snapshot = await repository.loadMonth(january);
    expect(snapshot.accounts, isEmpty);
    expect(snapshot.entries, isEmpty);
  });

  test(
    'edit preserves identity, moves month, and recalculates both accounts',
    () async {
      final source = await account('Bank', opening: 1000);
      final destination = await account('Tunai');
      final id = await repository.addEntry(
        entry(source, amount: 200, date: DateTime(2024, 1, 20)),
      );
      final before = await repository.watchEntry(id).first;
      expect(before, isNotNull);

      final januaryChanged = repository
          .watchMonth(january)
          .firstWhere(
            (snapshot) => snapshot.income == 0 && snapshot.totalEntries == 1,
          );
      final februaryChanged = repository
          .watchMonth(february)
          .firstWhere((snapshot) => snapshot.totalEntries == 1);
      final detailChanged = repository
          .watchEntry(id)
          .firstWhere((current) => current?.kind == EntryKind.transfer);

      await repository.updateEntry(
        id,
        EntryDraft(
          kind: EntryKind.transfer,
          accountId: source,
          destinationAccountId: destination,
          amount: 300,
          note: '  pindah tunai  ',
          occurredAt: DateTime(2024, 2, 2),
        ),
      );

      final jan = await januaryChanged.timeout(const Duration(seconds: 5));
      final feb = await februaryChanged.timeout(const Duration(seconds: 5));
      final changed = await detailChanged.timeout(const Duration(seconds: 5));
      expect(changed, isNotNull);
      expect(changed!.id, id);
      expect(changed.createdAt, before!.createdAt);
      expect(changed.destinationAccountId, destination);
      expect(changed.categoryId, isNull);
      expect(changed.note, 'pindah tunai');
      expect(changed.occurredAt, DateTime(2024, 2, 2));
      expect(jan.totalBalance, 1000);
      expect(jan.expense, 0);
      expect(feb.income, 0);
      expect(feb.expense, 0);
      expect(feb.accounts.firstWhere((a) => a.id == source).balance, 700);
      expect(feb.accounts.firstWhere((a) => a.id == destination).balance, 300);
    },
  );

  test(
    'delete reverses transfer atomically and detail emits missing',
    () async {
      final source = await account('Bank', opening: 1000);
      final destination = await account('Tunai');
      final id = await repository.addEntry(
        entry(
          source,
          kind: EntryKind.transfer,
          amount: 300,
          destination: destination,
        ),
      );
      final detailDeleted = repository
          .watchEntry(id)
          .firstWhere((current) => current == null);

      await repository.deleteEntry(id);

      expect(await detailDeleted.timeout(const Duration(seconds: 5)), isNull);
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.accounts.firstWhere((a) => a.id == source).balance, 1000);
      expect(
        snapshot.accounts.firstWhere((a) => a.id == destination).balance,
        0,
      );
      expect(snapshot.totalBalance, 1000);
      expect(snapshot.income, 0);
      expect(snapshot.expense, 0);
      expect(snapshot.totalEntries, 1);
    },
  );

  test(
    'failed edits and missing ids do not mutate the original entry',
    () async {
      final source = await account('Bank');
      final id = await repository.addEntry(
        entry(source, kind: EntryKind.expense, amount: 100),
      );
      final invalidDrafts = [
        entry(source, kind: EntryKind.transfer, amount: 250, destination: 999),
        entry(source, kind: EntryKind.expense, amount: 0),
        entry(source, kind: EntryKind.expense, categoryId: incomeCategoryId),
        entry(
          source,
          kind: EntryKind.expense,
          date: DateTime.now().add(const Duration(days: 2)),
        ),
      ];
      for (final draft in invalidDrafts) {
        await expectLater(
          repository.updateEntry(id, draft),
          throwsA(validationError),
        );
      }
      await expectLater(
        repository.updateEntry(999, entry(source)),
        throwsA(validationError),
      );
      await expectLater(repository.deleteEntry(999), throwsA(validationError));
      expect(await repository.watchEntry(0).first, isNull);
      expect(await repository.watchEntry(999).first, isNull);

      final unchanged = await repository.watchEntry(id).first;
      expect(unchanged?.kind, EntryKind.expense);
      expect(unchanged?.amount, 100);
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.expense, 100);
      expect(snapshot.totalBalance, -100);
      expect(snapshot.totalEntries, 1);
    },
  );

  test('opening adjustment cannot be edited or deleted', () async {
    final accountId = await account('Bank', opening: 500);
    final opening = (await repository.loadMonth(january)).entries.single;
    expect(opening.kind, EntryKind.adjustment);

    await expectLater(
      repository.updateEntry(opening.id, entry(accountId)),
      throwsA(validationError),
    );
    await expectLater(
      repository.deleteEntry(opening.id),
      throwsA(validationError),
    );

    final snapshot = await repository.loadMonth(january);
    expect(snapshot.entries.single.kind, EntryKind.adjustment);
    expect(snapshot.accounts.single.balance, 500);
  });

  test('account detail and active list react to account updates', () async {
    final id = await account('Bank utama', opening: 250);
    final otherId = await account('Tunai');
    final initial = await repository.getAccountDetails(id);
    expect(initial, isNotNull);
    expect(initial!.account.balance, 250);
    expect(initial.account.isArchived, isFalse);
    expect(initial.ledgerEntryCount, 1);
    expect(initial.canDelete, isFalse);

    final detailChanged = repository
        .watchAccountDetails(id)
        .firstWhere(
          (details) =>
              details?.account.name == 'Bank harian' &&
              details?.account.type == AccountType.eWallet,
        );
    await repository.updateAccount(
      id,
      const AccountUpdateDraft(
        name: '  Bank   harian ',
        type: AccountType.eWallet,
      ),
    );
    final changed = await detailChanged.timeout(const Duration(seconds: 5));
    expect(changed?.account.id, id);
    expect(changed?.account.balance, 250);
    expect(changed?.createdAt, initial.createdAt);

    final accounts = await repository.watchAccounts().first;
    expect(accounts.map((item) => item.id), containsAll([id, otherId]));
    expect(accounts.firstWhere((item) => item.id == id).name, 'Bank harian');
    await expectLater(
      repository.updateAccount(
        otherId,
        const AccountUpdateDraft(
          name: ' BANK  HARIAN ',
          type: AccountType.cash,
        ),
      ),
      throwsA(validationError),
    );
    await expectLater(
      repository.updateAccount(
        id,
        AccountUpdateDraft(name: 'x' * 81, type: AccountType.bank),
      ),
      throwsA(validationError),
    );
    expect(await repository.getAccountDetails(999), isNull);
    expect(await repository.watchAccountDetails(0).first, isNull);
  });

  test(
    'balance adjustment is a signed immutable ledger row and refreshes detail',
    () async {
      final id = await account('Bank', opening: 100);
      await account('Tunai');
      final detailChanged = repository
          .watchAccountDetails(id)
          .firstWhere(
            (details) =>
                details?.account.balance == 40 &&
                details?.ledgerEntryCount == 2,
          );

      final adjustmentId = await repository.adjustAccountBalance(
        id,
        AccountBalanceAdjustmentDraft(
          targetBalance: 40,
          occurredAt: DateTime(2024, 1, 15),
          note: '  koreksi   rekening  ',
        ),
      );
      final changed = await detailChanged.timeout(const Duration(seconds: 5));
      expect(changed?.account.balance, 40);
      final adjustment = await repository.watchEntry(adjustmentId).first;
      expect(adjustment?.kind, EntryKind.adjustment);
      expect(adjustment?.amount, -60);
      expect(adjustment?.note, 'koreksi   rekening');
      expect(adjustment?.occurredAt, DateTime(2024, 1, 15));
      final snapshot = await repository.loadMonth(january);
      expect(snapshot.income, 0);
      expect(snapshot.expense, 0);
      expect(snapshot.accounts.firstWhere((item) => item.id == id).balance, 40);

      await expectLater(
        repository.adjustAccountBalance(
          id,
          AccountBalanceAdjustmentDraft(targetBalance: 40, occurredAt: january),
        ),
        throwsA(validationError),
      );
      for (final target in [maxAmount + 1, -maxAmount - 1]) {
        await expectLater(
          repository.adjustAccountBalance(
            id,
            AccountBalanceAdjustmentDraft(
              targetBalance: target,
              occurredAt: january,
            ),
          ),
          throwsA(validationError),
        );
      }
      await expectLater(
        repository.adjustAccountBalance(
          id,
          AccountBalanceAdjustmentDraft(
            targetBalance: 50,
            occurredAt: DateTime.now().add(const Duration(days: 2)),
          ),
        ),
        throwsA(validationError),
      );
      await expectLater(
        repository.adjustAccountBalance(
          id,
          AccountBalanceAdjustmentDraft(
            targetBalance: 50,
            occurredAt: january,
            note: 'x' * 501,
          ),
        ),
        throwsA(validationError),
      );

      final maxId = await account('Batas', opening: maxAmount);
      await expectLater(
        repository.adjustAccountBalance(
          maxId,
          AccountBalanceAdjustmentDraft(
            targetBalance: -maxAmount,
            occurredAt: january,
          ),
        ),
        throwsA(validationError),
      );
      expect((await repository.getAccountDetails(maxId))?.ledgerEntryCount, 1);
      await expectLater(
        db.customStatement(
          '''
          INSERT INTO ledger_entries
            (kind, account_id, amount, category_id, note, occurred_day, created_at)
          VALUES (3, ?, 0, NULL, '', 20240101, 0)
        ''',
          [id],
        ),
        throwsA(anything),
      );
    },
  );

  test('archive requires zero balance and another active account, but keeps history', () async {
    final id = await account('Arsip', opening: 100);
    final activeId = await account('Aktif');
    await expectLater(
      repository.setAccountArchived(id, true),
      throwsA(validationError),
    );
    await repository.adjustAccountBalance(
      id,
      AccountBalanceAdjustmentDraft(targetBalance: 0, occurredAt: january),
    );
    await repository.setAccountArchived(id, true);

    final active = await repository.watchAccounts().first;
    expect(active.map((item) => item.id), [activeId]);
    final all = await repository.watchAccounts(includeArchived: true).first;
    expect(all, hasLength(2));
    expect(all.firstWhere((item) => item.id == id).isArchived, isTrue);
    final snapshot = await repository.loadMonth(january);
    expect(snapshot.accounts, hasLength(2));
    expect(
      snapshot.accounts.firstWhere((item) => item.id == id).isArchived,
      isTrue,
    );
    final details = await repository.getAccountDetails(id);
    expect(details?.account.balance, 0);
    expect(details?.account.isArchived, isTrue);
    expect(details?.ledgerEntryCount, 2);

    await expectLater(account(' ARSIP '), throwsA(validationError));
    await expectLater(
      repository.updateAccount(
        activeId,
        const AccountUpdateDraft(name: 'arsip', type: AccountType.cash),
      ),
      throwsA(validationError),
    );
    await expectLater(
      repository.setAccountArchived(activeId, true),
      throwsA(validationError),
    );
    await repository.updateAccount(
      id,
      const AccountUpdateDraft(name: 'Arsip lama', type: AccountType.cash),
    );
    expect(
      (await repository.getAccountDetails(id))?.account.name,
      'Arsip lama',
    );
    await repository.setAccountArchived(id, false);
    expect((await repository.watchAccounts().first), hasLength(2));
  });

  test(
    'archived source or destination blocks every ledger mutation until restore',
    () async {
      final archivedId = await account('Akan arsip');
      final sourceId = await account('Sumber');
      final otherId = await account('Lain');
      final transferId = await repository.addEntry(
        entry(
          sourceId,
          kind: EntryKind.transfer,
          amount: 50,
          destination: archivedId,
        ),
      );
      final expenseId = await repository.addEntry(
        entry(archivedId, kind: EntryKind.expense, amount: 50),
      );
      expect(
        (await repository.getAccountDetails(archivedId))?.account.balance,
        0,
      );
      await repository.setAccountArchived(archivedId, true);

      final invalidAdds = [
        entry(archivedId),
        entry(archivedId, kind: EntryKind.transfer, destination: otherId),
        entry(sourceId, kind: EntryKind.transfer, destination: archivedId),
      ];
      for (final draft in invalidAdds) {
        await expectLater(repository.addEntry(draft), throwsA(validationError));
      }
      await expectLater(
        repository.adjustAccountBalance(
          archivedId,
          AccountBalanceAdjustmentDraft(targetBalance: 10, occurredAt: january),
        ),
        throwsA(validationError),
      );
      for (final entryId in [expenseId, transferId]) {
        await expectLater(
          repository.updateEntry(entryId, entry(sourceId, amount: 25)),
          throwsA(validationError),
        );
        await expectLater(
          repository.deleteEntry(entryId),
          throwsA(validationError),
        );
      }

      await expectLater(
        db.customStatement(
          '''
          INSERT INTO ledger_entries
            (kind, account_id, amount, category_id, note, occurred_day, created_at)
          VALUES (0, ?, 10, ?, '', 20240101, 0)
        ''',
          [archivedId, incomeCategoryId],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'UPDATE ledger_entries SET amount = 51 WHERE id = ?',
          [transferId],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('DELETE FROM ledger_entries WHERE id = ?', [
          expenseId,
        ]),
        throwsA(anything),
      );
      expect((await repository.loadMonth(january)).totalEntries, 2);

      await repository.setAccountArchived(archivedId, false);
      await repository.deleteEntry(expenseId);
      await repository.deleteEntry(transferId);
      expect((await repository.loadMonth(january)).totalEntries, 0);
    },
  );

  test(
    'permanent account deletion requires zero source and destination refs',
    () async {
      final emptyId = await account('Kosong');
      final sourceId = await account('Sumber');
      final destinationId = await account('Tujuan');
      final deleted = repository
          .watchAccountDetails(emptyId)
          .firstWhere((details) => details == null);
      expect((await repository.getAccountDetails(emptyId))?.canDelete, isTrue);
      await repository.deleteAccount(emptyId);
      expect(await deleted.timeout(const Duration(seconds: 5)), isNull);

      await repository.addEntry(entry(sourceId));
      await repository.addEntry(
        entry(sourceId, kind: EntryKind.transfer, destination: destinationId),
      );
      final source = await repository.getAccountDetails(sourceId);
      final destination = await repository.getAccountDetails(destinationId);
      expect(source?.ledgerEntryCount, 2);
      expect(destination?.ledgerEntryCount, 1);
      expect(source?.canDelete, isFalse);
      expect(destination?.canDelete, isFalse);
      await expectLater(
        repository.deleteAccount(sourceId),
        throwsA(validationError),
      );
      await expectLater(
        repository.deleteAccount(destinationId),
        throwsA(validationError),
      );
      await expectLater(
        db.customStatement('DELETE FROM accounts WHERE id = ?', [
          destinationId,
        ]),
        throwsA(anything),
      );
      await expectLater(
        repository.deleteAccount(999),
        throwsA(validationError),
      );
      await expectLater(
        repository.updateAccount(
          999,
          const AccountUpdateDraft(name: 'Hilang', type: AccountType.other),
        ),
        throwsA(validationError),
      );
    },
  );

  test(
    'watchMonth refreshes for zero-balance accounts and transaction writes',
    () async {
      final initial = Completer<void>();
      final addedAccount = Completer<void>();
      final addedEntry = Completer<void>();
      final subscription = repository.watchMonth(january).listen((snapshot) {
        if (!initial.isCompleted) initial.complete();
        if (snapshot.accounts.length == 1 && !addedAccount.isCompleted) {
          addedAccount.complete();
        }
        if (snapshot.totalBalance == 300 && !addedEntry.isCompleted) {
          addedEntry.complete();
        }
      });
      addTearDown(subscription.cancel);
      await initial.future.timeout(const Duration(seconds: 5));
      final id = await account('Bank');
      await addedAccount.future.timeout(const Duration(seconds: 5));
      await repository.addEntry(entry(id, amount: 300));
      await addedEntry.future.timeout(const Duration(seconds: 5));
    },
  );

  test('SQLite file retains ledger and balances after reopening', () async {
    // Only one AppDatabase instance should be alive at a time in this test.
    await db.close();
    sharedDatabaseClosed = true;
    final directory = await Directory.systemTemp.createTemp(
      'waras_arta_db_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/finance.sqlite');
    final firstDb = AppDatabase(NativeDatabase(file));
    final firstRepository = DriftFinanceRepository(firstDb);
    late int deletedId;
    try {
      final id = await firstRepository.createAccount(
        AccountDraft(
          name: 'Bank',
          type: AccountType.bank,
          openingBalance: 200,
          openedAt: january,
        ),
      );
      final changedId = await firstRepository.addEntry(entry(id, amount: 123));
      await firstRepository.updateEntry(
        changedId,
        entry(id, kind: EntryKind.expense, amount: 50),
      );
      deletedId = await firstRepository.addEntry(entry(id, amount: 7));
      await firstRepository.deleteEntry(deletedId);
    } finally {
      await firstDb.close();
    }
    final secondDb = AppDatabase(NativeDatabase(file));
    try {
      final restored = await DriftFinanceRepository(secondDb)
          .loadMonth(january);
      expect(restored.accounts.single.name, 'Bank');
      expect(restored.totalBalance, 150);
      expect(restored.income, 0);
      expect(restored.expense, 50);
      expect(restored.totalEntries, 2);
      expect(
        await DriftFinanceRepository(secondDb).watchEntry(deletedId).first,
        isNull,
      );
    } finally {
      await secondDb.close();
    }
  });
}
