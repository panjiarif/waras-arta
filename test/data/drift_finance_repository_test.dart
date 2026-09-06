import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/database/app_database.dart';
import 'package:waras_arta/data/repositories/drift_finance_repository.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
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
    String? category,
  }) => EntryDraft(
    kind: kind,
    accountId: accountId,
    destinationAccountId: destination,
    amount: amount,
    category:
        category ??
        (kind == EntryKind.income
            ? 'Gaji'
            : kind == EntryKind.expense
            ? 'Belanja'
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

  test('all domain categories are accepted by schema version one', () async {
    final id = await account('Bank');
    for (final category in incomeCategories) {
      await repository.addEntry(entry(id, category: category));
    }
    for (final category in expenseCategories) {
      await repository.addEntry(
        entry(id, kind: EntryKind.expense, category: category),
      );
    }
    final snapshot = await repository.loadMonth(january);
    expect(snapshot.income, 100 * incomeCategories.length);
    expect(snapshot.expense, 100 * expenseCategories.length);
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
          category: 'Gaji',
        ),
        entry(999),
        entry(id, destination: destination),
        entry(id, kind: EntryKind.adjustment),
        entry(id, category: 'Belanja'),
        entry(id, kind: EntryKind.expense, category: 'Gaji'),
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
        String? category,
      }) => db.customStatement(
        'INSERT INTO ledger_entries '
        '(kind, account_id, destination_account_id, amount, category, note, occurred_day, created_at) '
        "VALUES (?, ?, ?, ?, ?, '', 20240101, 0)",
        [kind, id, destination, amount, category],
      );
      await expectLater(insert(destination: 999), throwsA(anything));
      await expectLater(insert(destination: id), throwsA(anything));
      await expectLater(insert(), throwsA(anything));
      await expectLater(
        insert(kind: 0, category: 'Gaji', amount: 0),
        throwsA(anything),
      );
      await expectLater(
        insert(kind: 0, category: 'Gaji', amount: maxAmount + 1),
        throwsA(anything),
      );
      await expectLater(
        insert(kind: 0, category: 'Belanja'),
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
      expect(changed.category, isNull);
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
        entry(source, kind: EntryKind.expense, category: 'Gaji'),
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
