import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/database/app_database.dart';
import 'package:waras_arta/data/repositories/drift_finance_repository.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
  const incomeCategoryId = 2;
  const expenseCategoryId = 10;
  late AppDatabase db;
  late DriftFinanceRepository repository;

  Future<int> createAccount(
    String name, {
    int openingBalance = 0,
    AccountBalanceGroup balanceGroup = AccountBalanceGroup.primary,
    DateTime? openedAt,
  }) => repository.createAccount(
    AccountDraft(
      name: name,
      type: AccountType.bank,
      openingBalance: openingBalance,
      openedAt: openedAt ?? DateTime(2024, 1, 1),
      balanceGroup: balanceGroup,
    ),
  );

  Future<int> addCashflow(
    int accountId, {
    required EntryKind kind,
    required int amount,
    required DateTime day,
  }) => repository.addEntry(
    EntryDraft.singleAllocation(
      kind: kind,
      accountId: accountId,
      amount: amount,
      categoryId: kind == EntryKind.income
          ? incomeCategoryId
          : expenseCategoryId,
      occurredAt: day,
    ),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftFinanceRepository(db);
  });

  tearDown(() => db.close());

  test('empty year returns twelve zero-valued civil months', () async {
    await createAccount(
      'Kosong',
      openingBalance: 500,
      openedAt: DateTime(2023, 12, 31),
    );

    final snapshot = await repository.watchYearlySummary(2024).first;

    expect(snapshot.year, 2024);
    expect(snapshot.months, hasLength(12));
    expect(snapshot.months.map((item) => item.month), [
      for (var month = 1; month <= 12; month++) DateTime(2024, month),
    ]);
    expect(snapshot.months.map((item) => item.income), everyElement(0));
    expect(snapshot.months.map((item) => item.expense), everyElement(0));
    expect(snapshot.totalIncome, 0);
    expect(snapshot.totalExpense, 0);
    expect(snapshot.net, 0);
  });

  test(
    'counts income and expense from every account group and archived history',
    () async {
      final primary = await createAccount(
        'Utama',
        openingBalance: 1000,
        openedAt: DateTime(2023, 12, 1),
      );
      final savings = await createAccount(
        'Investasi',
        openingBalance: 200,
        balanceGroup: AccountBalanceGroup.savingsInvestment,
        openedAt: DateTime(2023, 12, 1),
      );
      final archived = await createAccount(
        'Rekening lama',
        openingBalance: 25,
        openedAt: DateTime(2023, 12, 1),
      );

      await addCashflow(
        primary,
        kind: EntryKind.income,
        amount: 100,
        day: DateTime(2024, 1, 31),
      );
      await addCashflow(
        primary,
        kind: EntryKind.expense,
        amount: 40,
        day: DateTime(2024, 2, 1),
      );
      await addCashflow(
        savings,
        kind: EntryKind.income,
        amount: 300,
        day: DateTime(2024, 2, 2),
      );
      await addCashflow(
        archived,
        kind: EntryKind.expense,
        amount: 25,
        day: DateTime(2024, 2, 3),
      );
      await repository.setAccountArchived(archived, true);

      // Internal movements and balance corrections are deliberately excluded.
      await repository.addEntry(
        EntryDraft.transfer(
          accountId: primary,
          destinationAccountId: savings,
          amount: 60,
          occurredAt: DateTime(2024, 2, 4),
        ),
      );
      await repository.adjustAccountBalance(
        savings,
        AccountBalanceAdjustmentDraft(
          targetBalance: 700,
          occurredAt: DateTime(2024, 2, 5),
        ),
      );
      // Split allocations must contribute their header total exactly once.
      await repository.addEntry(
        EntryDraft.withAllocations(
          kind: EntryKind.expense,
          accountId: primary,
          allocations: const [
            EntryAllocationDraft(categoryId: 10, amount: 15000),
            EntryAllocationDraft(categoryId: 12, amount: 2000),
          ],
          occurredAt: DateTime(2024, 12, 31),
        ),
      );
      await addCashflow(
        primary,
        kind: EntryKind.expense,
        amount: 888,
        day: DateTime(2023, 12, 31),
      );
      await addCashflow(
        primary,
        kind: EntryKind.income,
        amount: 999,
        day: DateTime(2025, 1, 1),
      );

      final snapshot = await repository.watchYearlySummary(2024).first;

      expect(snapshot.months[0].income, 100);
      expect(snapshot.months[0].expense, 0);
      expect(snapshot.months[0].net, 100);
      expect(snapshot.months[1].income, 300);
      expect(snapshot.months[1].expense, 65);
      expect(snapshot.months[1].net, 235);
      expect(
        snapshot.months
            .skip(2)
            .take(9)
            .expand((item) => [item.income, item.expense]),
        everyElement(0),
      );
      expect(snapshot.months[11].expense, 17000);
      expect(snapshot.totalIncome, 400);
      expect(snapshot.totalExpense, 17065);
      expect(snapshot.net, -16665);
    },
  );

  test('watcher refreshes after a cash-flow entry changes the year', () async {
    final account = await createAccount('Reaktif');
    final iterator = StreamIterator(repository.watchYearlySummary(2024));

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.months[2].income, 0);

    await addCashflow(
      account,
      kind: EntryKind.income,
      amount: 125,
      day: DateTime(2024, 3, 15),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.months[2].income, 125);
    expect(iterator.current.totalIncome, 125);
    await iterator.cancel();
  });

  test('rejects a year outside the supported civil range', () {
    expect(
      () => repository.watchYearlySummary(1999),
      throwsA(isA<FinanceValidationException>()),
    );
    expect(
      () => repository.watchYearlySummary(DateTime.now().year + 1),
      throwsA(isA<FinanceValidationException>()),
    );
  });
}
