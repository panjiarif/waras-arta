import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/app.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/domain/finance_repository.dart';
import 'package:waras_arta/features/ledger/view_models/ledger_view_model.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  Future<void> pumpApp(WidgetTester tester, _UiRepository repository) async {
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
}

class _UiRepository implements FinanceRepository {
  _UiRepository({bool withAccounts = false, this.failRead = false}) {
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
  }

  final bool failRead;
  final accounts = <FinanceAccount>[];
  AccountDraft? savedAccount;
  EntryDraft? savedEntry;

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
    return accounts.length;
  }

  @override
  Future<int> addEntry(EntryDraft draft) async {
    savedEntry = draft;
    return 1;
  }

  @override
  Future<FinanceSnapshot> loadMonth(DateTime month, {int limit = 50}) async =>
      FinanceSnapshot(
        accounts: accounts,
        entries: [],
        income: 0,
        expense: 0,
        totalEntries: 0,
      );

  @override
  Stream<FinanceSnapshot> watchMonth(DateTime month, {int limit = 50}) async* {
    if (failRead) throw StateError('Read failure');
    yield await loadMonth(month, limit: limit);
  }
}
