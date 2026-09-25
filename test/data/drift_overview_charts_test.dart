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

  test(
    'seven-day expenses cross years, fill gaps, and count split totals once',
    () async {
      final source = await createAccount(
        'Harian',
        openingBalance: 1000,
        openedAt: DateTime(2024, 12, 1),
      );
      final destination = await createAccount(
        'Tujuan',
        openedAt: DateTime(2024, 12, 1),
      );
      await addCashflow(
        source,
        kind: EntryKind.expense,
        amount: 999,
        day: DateTime(2024, 12, 27),
      );
      await addCashflow(
        source,
        kind: EntryKind.expense,
        amount: 75,
        day: DateTime(2024, 12, 28),
      );
      await addCashflow(
        source,
        kind: EntryKind.income,
        amount: 300,
        day: DateTime(2024, 12, 29),
      );
      await repository.addEntry(
        EntryDraft.transfer(
          accountId: source,
          destinationAccountId: destination,
          amount: 50,
          occurredAt: DateTime(2024, 12, 31),
        ),
      );
      await repository.addEntry(
        EntryDraft.withAllocations(
          kind: EntryKind.expense,
          accountId: source,
          allocations: const [
            EntryAllocationDraft(categoryId: 10, amount: 30),
            EntryAllocationDraft(categoryId: 12, amount: 20),
          ],
          occurredAt: DateTime(2025, 1, 1),
        ),
      );
      await addCashflow(
        source,
        kind: EntryKind.expense,
        amount: 125,
        day: DateTime(2025, 1, 2),
      );
      await addCashflow(
        source,
        kind: EntryKind.expense,
        amount: 888,
        day: DateTime(2025, 1, 4),
      );

      final snapshot = await repository
          .watchOverviewCharts(DateTime(2025, 1, 3, 23, 59))
          .first;

      expect(snapshot.today, DateTime(2025, 1, 3));
      expect(snapshot.dailyExpenses.map((point) => point.day), [
        DateTime(2024, 12, 28),
        DateTime(2024, 12, 29),
        DateTime(2024, 12, 30),
        DateTime(2024, 12, 31),
        DateTime(2025, 1, 1),
        DateTime(2025, 1, 2),
        DateTime(2025, 1, 3),
      ]);
      expect(snapshot.dailyExpenses.map((point) => point.expense), [
        75,
        0,
        0,
        0,
        50,
        125,
        0,
      ]);
      expect(snapshot.totalExpense, 250);
    },
  );

  test(
    'balance trend applies every ledger delta and ends at current balance',
    () async {
      final primary = await createAccount('Utama', openingBalance: 1000);
      final secondPrimary = await createAccount('Tunai', openingBalance: 100);
      final savings = await createAccount(
        'Simpanan',
        openingBalance: 500,
        balanceGroup: AccountBalanceGroup.savingsInvestment,
      );
      await addCashflow(
        primary,
        kind: EntryKind.expense,
        amount: 100,
        day: DateTime(2024, 1, 10),
      );
      await addCashflow(
        primary,
        kind: EntryKind.income,
        amount: 200,
        day: DateTime(2024, 2, 10),
      );
      await repository.addEntry(
        EntryDraft.transfer(
          accountId: primary,
          destinationAccountId: secondPrimary,
          amount: 50,
          occurredAt: DateTime(2024, 3, 10),
        ),
      );
      await repository.addEntry(
        EntryDraft.transfer(
          accountId: primary,
          destinationAccountId: savings,
          amount: 300,
          occurredAt: DateTime(2024, 4, 10),
        ),
      );
      await repository.addEntry(
        EntryDraft.transfer(
          accountId: savings,
          destinationAccountId: primary,
          amount: 40,
          occurredAt: DateTime(2024, 5, 10),
        ),
      );
      await repository.adjustAccountBalance(
        primary,
        AccountBalanceAdjustmentDraft(
          targetBalance: 700,
          occurredAt: DateTime(2024, 6, 10),
        ),
      );
      await addCashflow(
        secondPrimary,
        kind: EntryKind.expense,
        amount: 50,
        day: DateTime(2024, 7, 10),
      );

      final snapshot = await repository
          .watchOverviewCharts(DateTime(2024, 7, 15))
          .first;
      final current = await repository.loadMonth(DateTime(2024, 7));

      expect(snapshot.balancePoints.map((point) => point.day), [
        DateTime(2024, 1, 31),
        DateTime(2024, 2, 29),
        DateTime(2024, 3, 31),
        DateTime(2024, 4, 30),
        DateTime(2024, 5, 31),
        DateTime(2024, 6, 30),
        DateTime(2024, 7, 15),
      ]);
      expect(snapshot.balancePoints.map((point) => point.balance), [
        1000,
        1200,
        1200,
        900,
        940,
        850,
        800,
      ]);
      expect(snapshot.balancePoints.map((point) => point.isCurrent), [
        false,
        false,
        false,
        false,
        false,
        false,
        true,
      ]);
      expect(snapshot.balancePoints.last.balance, current.primaryBalance);
    },
  );

  test('archived primary account remains in historical balances', () async {
    await createAccount('Aktif', openingBalance: 50);
    final archived = await createAccount('Arsip', openingBalance: 300);
    await addCashflow(
      archived,
      kind: EntryKind.expense,
      amount: 300,
      day: DateTime(2024, 2, 5),
    );
    await repository.setAccountArchived(archived, true);

    final charts = await repository
        .watchOverviewCharts(DateTime(2024, 7, 15))
        .first;
    final current = await repository.loadMonth(DateTime(2024, 7));

    expect(charts.balancePoints.map((point) => point.balance), [
      350,
      50,
      50,
      50,
      50,
      50,
      50,
    ]);
    expect(charts.balancePoints.last.balance, current.primaryBalance);
  });

  test(
    'current balance group deliberately reclassifies account history',
    () async {
      await createAccount('Utama', openingBalance: 50);
      final moved = await createAccount(
        'Dana',
        openingBalance: 100,
        balanceGroup: AccountBalanceGroup.savingsInvestment,
      );

      await repository.updateAccount(
        moved,
        const AccountUpdateDraft(
          name: 'Dana',
          type: AccountType.bank,
          balanceGroup: AccountBalanceGroup.primary,
        ),
      );
      final included = await repository
          .watchOverviewCharts(DateTime(2024, 7, 15))
          .first;
      expect(
        included.balancePoints.map((point) => point.balance),
        everyElement(150),
      );

      await repository.updateAccount(
        moved,
        const AccountUpdateDraft(
          name: 'Dana',
          type: AccountType.bank,
          balanceGroup: AccountBalanceGroup.savingsInvestment,
        ),
      );
      final excluded = await repository
          .watchOverviewCharts(DateTime(2024, 7, 15))
          .first;
      expect(
        excluded.balancePoints.map((point) => point.balance),
        everyElement(50),
      );
    },
  );

  test(
    'negative adjustment is retained across constant balance points',
    () async {
      final account = await createAccount('Minus');
      await repository.adjustAccountBalance(
        account,
        AccountBalanceAdjustmentDraft(
          targetBalance: -100,
          occurredAt: DateTime(2024, 1, 15),
        ),
      );

      final snapshot = await repository
          .watchOverviewCharts(DateTime(2024, 7, 15))
          .first;

      expect(snapshot.balancePoints, hasLength(7));
      expect(
        snapshot.balancePoints.map((point) => point.balance),
        everyElement(-100),
      );
    },
  );

  test('watcher refreshes after ledger and current group changes', () async {
    final iterator = StreamIterator(
      repository.watchOverviewCharts(DateTime(2024, 7, 15)),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.balancePoints.last.balance, 0);

    final account = await createAccount('Berubah', openingBalance: 100);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.balancePoints.last.balance, 100);

    await repository.updateAccount(
      account,
      const AccountUpdateDraft(
        name: 'Berubah',
        type: AccountType.bank,
        balanceGroup: AccountBalanceGroup.savingsInvestment,
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.balancePoints.last.balance, 0);
    await iterator.cancel();
  });
}
