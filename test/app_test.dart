import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/app.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/domain/finance_repository.dart';
import 'package:waras_arta/features/ledger/view_models/ledger_view_model.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  Future<void> pumpApp(WidgetTester tester, _UiRepository repository) async {
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeRepositoryProvider.overrideWithValue(repository)],
        child: const WarasArtaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'empty app leads to creating first account and saving opening balance',
    (tester) async {
      final repository = _UiRepository();
      await pumpApp(tester, repository);
      expect(find.text('Waras Arta'), findsOneWidget);
      expect(find.text('Tambah rekening'), findsOneWidget);
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('account-name')), 'Dompet');
      await tester.enterText(
        find.byKey(const Key('opening-balance')),
        '100000',
      );
      await tester.ensureVisible(find.byKey(const Key('save-account')));
      await tester.tap(find.byKey(const Key('save-account')));
      await tester.pumpAndSettle();
      expect(repository.savedAccount?.name, 'Dompet');
      expect(repository.savedAccount?.openingBalance, 100000);
      expect(find.text('Catat transaksi'), findsOneWidget);
      expect(find.text('Rp 100.000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expense form validates zero then saves integer amount', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-amount')), '0');
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();
    expect(repository.savedEntry, isNull);
    expect(find.text('Nominal harus lebih besar dari nol.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('entry-amount')));
    await tester.enterText(find.byKey(const Key('entry-amount')), '12500');
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();
    expect(repository.savedEntry?.kind, EntryKind.expense);
    expect(repository.savedEntry?.amount, 12500);
    expect(repository.savedEntry?.destinationAccountId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transfer uses distinct accounts and no category', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-amount')), '25000');
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();
    expect(repository.savedEntry?.kind, EntryKind.transfer);
    expect(repository.savedEntry?.accountId, 1);
    expect(repository.savedEntry?.destinationAccountId, 2);
    expect(repository.savedEntry?.category, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen and enlarged text do not overflow core screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, _UiRepository(withAccounts: true));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Rekening').last);
    await tester.pumpAndSettle();
    expect(find.text('Dompet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('repository failure shows retry instead of a fake zero balance', (
    tester,
  ) async {
    await pumpApp(tester, _UiRepository(failRead: true));
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(find.text('Rp 0'), findsNothing);
    expect(find.byKey(const Key('primary-action')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transaction card opens details and edit pre-fills the form', (
    tester,
  ) async {
    final entry = FinanceEntry(
      id: 7,
      kind: EntryKind.expense,
      accountId: 1,
      amount: 12500,
      category: 'Makan & minum',
      note: 'Makan siang',
      occurredAt: DateTime(2024, 8, 17),
      createdAt: DateTime(2024, 8, 17, 12, 30),
    );
    final repository = _UiRepository(withAccounts: true, entry: entry);
    await pumpApp(tester, repository);

    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-7')));
    await tester.pumpAndSettle();
    expect(find.text('Detail transaksi'), findsOneWidget);
    expect(find.text('Makan siang'), findsOneWidget);
    expect(find.text('17 Agu 2024'), findsOneWidget);
    expect(find.byKey(const Key('delete-entry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-entry')));
    await tester.pumpAndSettle();
    expect(find.text('Edit transaksi'), findsOneWidget);
    final amount = tester.widget<TextFormField>(
      find.byKey(const Key('entry-amount')),
    );
    final note = tester.widget<TextFormField>(
      find.byKey(const Key('entry-note')),
    );
    expect(amount.controller?.text, '12500');
    expect(note.controller?.text, 'Makan siang');

    await tester.enterText(find.byKey(const Key('entry-amount')), '15000');
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();
    expect(repository.updatedEntryId, 7);
    expect(repository.updatedEntry?.amount, 15000);
    expect(repository.updatedEntry?.category, 'Makan & minum');
    expect(repository.updateCount, 1);
    expect(
      tester.widget<Text>(find.byKey(const Key('entry-detail-amount'))).data,
      '− Rp 15.000',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete requires confirmation and removes one transaction', (
    tester,
  ) async {
    final repository = _UiRepository(
      withAccounts: true,
      entry: FinanceEntry(
        id: 8,
        kind: EntryKind.income,
        accountId: 1,
        amount: 50000,
        category: 'Gaji',
        note: '',
        occurredAt: DateTime(2024, 8, 18),
        createdAt: DateTime(2024, 8, 18, 9),
      ),
    );
    await pumpApp(tester, repository);
    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-8')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('delete-entry')));
    await tester.tap(find.byKey(const Key('delete-entry')));
    await tester.pumpAndSettle();
    expect(find.text('Hapus transaksi?'), findsOneWidget);
    expect(repository.deleteCount, 0);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(repository.deleteCount, 0);

    await tester.ensureVisible(find.byKey(const Key('delete-entry')));
    await tester.tap(find.byKey(const Key('delete-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(repository.deletedEntryId, 8);
    expect(repository.deleteCount, 1);
    expect(find.byKey(const Key('entry-8')), findsNothing);
    expect(find.text('Transaksi telah dihapus.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening balance details are read-only', (tester) async {
    final repository = _UiRepository(
      withAccounts: true,
      entry: FinanceEntry(
        id: 9,
        kind: EntryKind.adjustment,
        accountId: 1,
        amount: 100000,
        category: null,
        note: 'Saldo awal',
        occurredAt: DateTime(2024, 8, 1),
        createdAt: DateTime(2024, 8, 1),
      ),
    );
    await pumpApp(tester, repository);
    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-9')));
    await tester.pumpAndSettle();

    expect(find.text('Detail transaksi'), findsOneWidget);
    expect(find.byKey(const Key('edit-entry')), findsNothing);
    expect(find.byKey(const Key('delete-entry')), findsNothing);
    expect(
      find.textContaining('belum dapat diedit atau dihapus'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid transaction route shows not found safely', (
    tester,
  ) async {
    await pumpApp(tester, _UiRepository(withAccounts: true));
    final context = tester.element(find.text('Waras Arta'));

    GoRouter.of(context).go('/transactions/not-a-number');
    await tester.pumpAndSettle();
    expect(find.text('Transaksi tidak ditemukan'), findsOneWidget);
    expect(find.text('Coba lagi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail reports account-loading failure explicitly', (
    tester,
  ) async {
    final repository = _UiRepository(
      withAccounts: true,
      failRead: true,
      entry: FinanceEntry(
        id: 13,
        kind: EntryKind.income,
        accountId: 1,
        amount: 1000,
        category: 'Hadiah',
        note: '',
        occurredAt: DateTime(2024, 8, 23),
        createdAt: DateTime(2024, 8, 23),
      ),
    );
    await pumpApp(tester, repository);
    final context = tester.element(find.text('Coba lagi'));
    GoRouter.of(context).go('/transactions/13');
    await tester.pumpAndSettle();

    expect(find.text('Detail transaksi'), findsOneWidget);
    expect(find.text('Rekening belum tersedia'), findsOneWidget);
    expect(
      find.textContaining('Nama rekening belum dapat dimuat'),
      findsOneWidget,
    );
    expect(find.text('Muat ulang rekening'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed edit keeps form and shows business error', (
    tester,
  ) async {
    final repository = _UiRepository(
      withAccounts: true,
      entry: FinanceEntry(
        id: 10,
        kind: EntryKind.expense,
        accountId: 1,
        amount: 10000,
        category: 'Belanja',
        note: '',
        occurredAt: DateTime(2024, 8, 20),
        createdAt: DateTime(2024, 8, 20),
      ),
    );
    repository.onUpdateEntry = (_, _) async =>
        throw const FinanceValidationException('Transaksi tidak dapat diubah.');
    await pumpApp(tester, repository);
    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-10')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-entry')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();
    expect(find.text('Edit transaksi'), findsOneWidget);
    expect(find.text('Transaksi tidak dapat diubah.'), findsOneWidget);
    expect(find.text('Perubahan transaksi tersimpan.'), findsNothing);
    expect(repository.updateCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed delete keeps detail and can be retried', (tester) async {
    final repository = _UiRepository(
      withAccounts: true,
      entry: FinanceEntry(
        id: 11,
        kind: EntryKind.income,
        accountId: 1,
        amount: 75000,
        category: 'Usaha',
        note: '',
        occurredAt: DateTime(2024, 8, 21),
        createdAt: DateTime(2024, 8, 21),
      ),
    );
    repository.onDeleteEntry = (_) async =>
        throw const FinanceValidationException(
          'Transaksi belum dapat dihapus.',
        );
    await pumpApp(tester, repository);
    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-11')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-entry')));
    await tester.tap(find.byKey(const Key('delete-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();

    expect(find.text('Detail transaksi'), findsOneWidget);
    expect(find.text('Transaksi belum dapat dihapus.'), findsOneWidget);
    expect(find.text('Transaksi telah dihapus.'), findsNothing);
    expect(repository.deleteCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back from a dirty edit asks before discarding changes', (
    tester,
  ) async {
    final repository = _UiRepository(
      withAccounts: true,
      entry: FinanceEntry(
        id: 12,
        kind: EntryKind.expense,
        accountId: 1,
        amount: 8000,
        category: 'Transportasi',
        note: '',
        occurredAt: DateTime(2024, 8, 22),
        createdAt: DateTime(2024, 8, 22),
      ),
    );
    await pumpApp(tester, repository);
    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-amount')), '9000');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Buang perubahan?'), findsOneWidget);
    await tester.tap(find.text('Tetap di sini'));
    await tester.pumpAndSettle();
    expect(find.text('Edit transaksi'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard-entry-changes')));
    await tester.pumpAndSettle();
    expect(find.text('Detail transaksi'), findsOneWidget);
    expect(repository.updateCount, 0);
    expect(tester.takeException(), isNull);
  });
}

class _UiRepository implements FinanceRepository {
  _UiRepository({
    bool withAccounts = false,
    this.failRead = false,
    FinanceEntry? entry,
  }) {
    if (withAccounts) {
      accounts.addAll(const [
        FinanceAccount(
          id: 1,
          name: 'Dompet',
          type: AccountType.cash,
          balance: 100000,
        ),
        FinanceAccount(id: 2, name: 'Bank', type: AccountType.bank, balance: 0),
      ]);
    }
    if (entry != null) entries.add(entry);
  }

  final bool failRead;
  final accounts = <FinanceAccount>[];
  final entries = <FinanceEntry>[];
  AccountDraft? savedAccount;
  EntryDraft? savedEntry;
  int? updatedEntryId;
  EntryDraft? updatedEntry;
  int updateCount = 0;
  int? deletedEntryId;
  int deleteCount = 0;
  Future<void> Function(int, EntryDraft)? onUpdateEntry;
  Future<void> Function(int)? onDeleteEntry;
  final _changes = StreamController<void>.broadcast(sync: true);

  Future<void> dispose() => _changes.close();

  @override
  Future<int> createAccount(AccountDraft draft) async {
    savedAccount = draft;
    accounts.add(
      FinanceAccount(
        id: accounts.length + 1,
        name: draft.name,
        type: draft.type,
        balance: draft.openingBalance,
      ),
    );
    _changes.add(null);
    return accounts.length;
  }

  @override
  Future<int> addEntry(EntryDraft draft) async {
    savedEntry = draft;
    return 1;
  }

  @override
  Stream<FinanceEntry?> watchEntry(int id) => _changes.stream
      .map((_) => entries.where((entry) => entry.id == id).firstOrNull)
      .startWith(entries.where((entry) => entry.id == id).firstOrNull);

  @override
  Future<void> updateEntry(int id, EntryDraft draft) async {
    updatedEntryId = id;
    updatedEntry = draft;
    updateCount++;
    if (onUpdateEntry != null) return onUpdateEntry!(id, draft);
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index < 0) {
      throw const FinanceValidationException('Transaksi tidak ditemukan.');
    }
    final previous = entries[index];
    entries[index] = FinanceEntry(
      id: id,
      kind: draft.kind,
      accountId: draft.accountId,
      destinationAccountId: draft.destinationAccountId,
      amount: draft.amount,
      category: draft.category,
      note: draft.note,
      occurredAt: draft.occurredAt,
      createdAt: previous.createdAt,
    );
    _changes.add(null);
  }

  @override
  Future<void> deleteEntry(int id) async {
    deletedEntryId = id;
    deleteCount++;
    if (onDeleteEntry != null) return onDeleteEntry!(id);
    entries.removeWhere((entry) => entry.id == id);
    _changes.add(null);
  }

  @override
  Future<FinanceSnapshot> loadMonth(DateTime month, {int limit = 50}) async =>
      FinanceSnapshot(
        accounts: accounts,
        entries: entries,
        income: 0,
        expense: 0,
        totalEntries: entries.length,
      );

  @override
  Stream<FinanceSnapshot> watchMonth(DateTime month, {int limit = 50}) async* {
    if (failRead) throw StateError('Read failure');
    yield await loadMonth(month, limit: limit);
    await for (final _ in _changes.stream) {
      yield await loadMonth(month, limit: limit);
    }
  }
}

extension<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
