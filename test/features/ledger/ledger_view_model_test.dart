import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/domain/finance_repository.dart';
import 'package:waras_arta/features/ledger/view_models/ledger_view_model.dart';

void main() {
  late FakeFinanceRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeFinanceRepository();
    container = ProviderContainer(
      overrides: [financeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  group('LedgerViewModel', () {
    test('starts in the current month with a 50-entry page', () {
      final now = DateTime.now();
      final filter = container.read(ledgerFilterProvider);
      expect(filter.month, DateTime(now.year, now.month));
      expect(filter.limit, 50);
    });

    test('normalizes selected dates and resets pagination', () {
      final model = container.read(ledgerFilterProvider.notifier);
      model.loadMore();
      model.loadMore();
      expect(container.read(ledgerFilterProvider).limit, 150);

      model.showMonth(DateTime(2024, 8, 17, 12, 30));
      final filter = container.read(ledgerFilterProvider);
      expect(filter.month, DateTime(2024, 8));
      expect(filter.limit, 50);
    });

    test('moves across year boundaries and resets pagination', () {
      final model = container.read(ledgerFilterProvider.notifier);
      model.showMonth(DateTime(2023, 12));
      model.loadMore();
      model.moveMonth(1);
      expect(container.read(ledgerFilterProvider).month, DateTime(2024));
      expect(container.read(ledgerFilterProvider).limit, 50);

      model.moveMonth(-1);
      expect(container.read(ledgerFilterProvider).month, DateTime(2023, 12));
    });

    test('does not navigate before January 2000', () {
      final model = container.read(ledgerFilterProvider.notifier);
      model.showMonth(DateTime(2000));
      model.loadMore();
      model.moveMonth(-1);
      expect(container.read(ledgerFilterProvider).month, DateTime(2000));
      expect(container.read(ledgerFilterProvider).limit, 100);
    });

    test('does not navigate into a future month', () {
      final now = DateTime.now();
      final model = container.read(ledgerFilterProvider.notifier);
      model.showMonth(now);
      model.loadMore();
      model.moveMonth(1);
      expect(
        container.read(ledgerFilterProvider).month,
        DateTime(now.year, now.month),
      );
      expect(container.read(ledgerFilterProvider).limit, 100);
    });

    test(
      'snapshot provider queries the selected month and page limit',
      () async {
        final model = container.read(ledgerFilterProvider.notifier);
        model.showMonth(DateTime(2024, 8, 17));
        model.loadMore();

        // Match the active UI subscription so Riverpod keeps the stream active.
        final subscription = container.listen(
          financeSnapshotProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);
        final snapshot = await container.read(financeSnapshotProvider.future);
        expect(snapshot, same(repository.snapshot));
        expect(repository.lastMonth, DateTime(2024, 8));
        expect(repository.lastLimit, 100);
      },
    );
  });

  group('FinanceActions', () {
    test('successful account creation selects its opening month', () async {
      final draft = AccountDraft(
        name: 'Dompet',
        type: AccountType.cash,
        openingBalance: 50000,
        openedAt: DateTime(2024, 7, 12),
      );
      final actions = container.read(financeActionsProvider.notifier);
      expect(await actions.createAccount(draft), isTrue);
      expect(repository.accounts, [same(draft)]);
      expect(container.read(ledgerFilterProvider).month, DateTime(2024, 7));
      expect(container.read(financeActionsProvider).isSaving, isFalse);
      expect(container.read(financeActionsProvider).error, isNull);
    });

    test(
      'successful entry selects occurrence month and resets pagination',
      () async {
        final draft = expenseDraft();
        container.read(ledgerFilterProvider.notifier).loadMore();
        final actions = container.read(financeActionsProvider.notifier);

        expect(await actions.addEntry(draft), isTrue);
        expect(repository.entries, [same(draft)]);
        expect(container.read(ledgerFilterProvider).month, DateTime(2024, 8));
        expect(container.read(ledgerFilterProvider).limit, 50);
        expect(container.read(financeActionsProvider).isSaving, isFalse);
        expect(container.read(financeActionsProvider).error, isNull);
      },
    );

    test('successful edit stores the id and selects the new month', () async {
      final draft = expenseDraft();
      final actions = container.read(financeActionsProvider.notifier);

      expect(await actions.updateEntry(42, draft), isTrue);
      expect(repository.updatedEntryId, 42);
      expect(repository.updatedEntry, same(draft));
      expect(container.read(ledgerFilterProvider).month, DateTime(2024, 8));
      expect(container.read(financeActionsProvider).isSaving, isFalse);
    });

    test('successful delete keeps the selected month', () async {
      final model = container.read(ledgerFilterProvider.notifier);
      model.showMonth(DateTime(2023, 6));
      final actions = container.read(financeActionsProvider.notifier);

      expect(await actions.deleteEntry(17), isTrue);
      expect(repository.deletedEntryId, 17);
      expect(container.read(ledgerFilterProvider).month, DateTime(2023, 6));
      expect(container.read(financeActionsProvider).isSaving, isFalse);
    });

    test(
      'surfaces business validation without changing selected month',
      () async {
        repository.onAddEntry = (_) async =>
            throw const FinanceValidationException(
              'Rekening asal dan tujuan harus berbeda.',
            );
        final before = container.read(ledgerFilterProvider).month;
        final actions = container.read(financeActionsProvider.notifier);

        expect(await actions.addEntry(expenseDraft()), isFalse);
        expect(container.read(ledgerFilterProvider).month, before);
        expect(container.read(financeActionsProvider).isSaving, isFalse);
        expect(
          container.read(financeActionsProvider).error,
          'Rekening asal dan tujuan harus berbeda.',
        );
      },
    );

    test('hides unknown error details and permits retry', () async {
      repository.onAddEntry = (_) async => throw StateError(
        'private-account-name.sqlite: confidential transaction details',
      );
      final actions = container.read(financeActionsProvider.notifier);

      expect(await actions.addEntry(expenseDraft()), isFalse);
      expect(
        container.read(financeActionsProvider).error,
        'Data belum tersimpan. Periksa ruang penyimpanan lalu coba lagi.',
      );
      expect(container.read(financeActionsProvider).isSaving, isFalse);

      repository.onAddEntry = (_) async => 2;
      expect(await actions.addEntry(expenseDraft()), isTrue);
      expect(repository.entries, hasLength(2));
      expect(container.read(financeActionsProvider).error, isNull);
    });

    test('blocks concurrent writes until the current save finishes', () async {
      final pending = Completer<int>();
      repository.onAddEntry = (_) => pending.future;
      final actions = container.read(financeActionsProvider.notifier);

      final firstSave = actions.addEntry(expenseDraft());
      expect(container.read(financeActionsProvider).isSaving, isTrue);
      expect(await actions.addEntry(expenseDraft()), isFalse);
      expect(repository.entries, hasLength(1));

      actions.clearError();
      expect(container.read(financeActionsProvider).isSaving, isTrue);
      pending.complete(1);
      expect(await firstSave, isTrue);
      expect(container.read(financeActionsProvider).isSaving, isFalse);
    });

    test('clearError resets a failed save state', () async {
      repository.onCreateAccount = (_) async =>
          throw const FinanceValidationException('Nama rekening wajib diisi.');
      final actions = container.read(financeActionsProvider.notifier);
      expect(
        await actions.createAccount(
          AccountDraft(
            name: '',
            type: AccountType.cash,
            openingBalance: 0,
            openedAt: DateTime(2024, 8),
          ),
        ),
        isFalse,
      );
      expect(container.read(financeActionsProvider).error, isNotNull);

      actions.clearError();
      expect(container.read(financeActionsProvider).error, isNull);
      expect(container.read(financeActionsProvider).isSaving, isFalse);
    });
  });
}

EntryDraft expenseDraft() => EntryDraft(
  kind: EntryKind.expense,
  accountId: 1,
  amount: 15000,
  category: 'Makan & minum',
  occurredAt: DateTime(2024, 8, 17),
);

class FakeFinanceRepository implements FinanceRepository {
  final snapshot = FinanceSnapshot(
    accounts: [],
    entries: [],
    income: 0,
    expense: 0,
    totalEntries: 0,
  );
  final accounts = <AccountDraft>[];
  final entries = <EntryDraft>[];
  int? updatedEntryId;
  EntryDraft? updatedEntry;
  int? deletedEntryId;
  Future<int> Function(AccountDraft)? onCreateAccount;
  Future<int> Function(EntryDraft)? onAddEntry;
  DateTime? lastMonth;
  int? lastLimit;

  @override
  Future<int> createAccount(AccountDraft draft) async {
    accounts.add(draft);
    return onCreateAccount == null ? 1 : await onCreateAccount!(draft);
  }

  @override
  Future<int> addEntry(EntryDraft draft) async {
    entries.add(draft);
    return onAddEntry == null ? 1 : await onAddEntry!(draft);
  }

  @override
  Future<void> updateEntry(int id, EntryDraft draft) async {
    updatedEntryId = id;
    updatedEntry = draft;
  }

  @override
  Future<void> deleteEntry(int id) async {
    deletedEntryId = id;
  }

  @override
  Stream<FinanceEntry?> watchEntry(int id) => Stream.value(null);

  @override
  Future<FinanceSnapshot> loadMonth(DateTime month, {int limit = 50}) async {
    lastMonth = month;
    lastLimit = limit;
    return snapshot;
  }

  @override
  Stream<FinanceSnapshot> watchMonth(DateTime month, {int limit = 50}) {
    lastMonth = month;
    lastLimit = limit;
    return Stream.value(snapshot);
  }
}
