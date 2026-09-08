import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/app.dart';
import 'package:waras_arta/app/providers.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/domain/finance_repository.dart';
import 'package:waras_arta/features/calendar/view_models/calendar_view_model.dart';
import 'package:waras_arta/features/ledger/views/category_selection_field.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  Future<void> pumpApp(
    WidgetTester tester,
    _UiRepository repository, {
    DateTime? today,
  }) async {
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWithValue(repository),
          if (today != null) currentDateProvider.overrideWithValue(today),
        ],
        child: const WarasArtaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('more menu opens encrypted backup screen on a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);

    await tester.tap(find.byKey(const Key('more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup & pulihkan data'));
    await tester.pumpAndSettle();

    expect(find.text('Jaga catatan keuanganmu'), findsOneWidget);
    expect(find.byKey(const Key('backup-password-warning')), findsOneWidget);
    expect(
      find.textContaining('Jika lupa, file backup tidak akan bisa direstore'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('create-backup')), findsOneWidget);
    expect(find.byKey(const Key('restore-backup')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('account detail edits name and type without changing balance', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.text('Rekening').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-1')));
    await tester.pumpAndSettle();

    expect(find.text('Detail rekening'), findsOneWidget);
    expect(find.text('Rp 100.000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-edit-name')),
      'Bank Harian',
    );
    await tester.tap(find.byKey(const Key('account-edit-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-account-edit')));
    await tester.tap(find.byKey(const Key('save-account-edit')));
    await tester.pumpAndSettle();

    expect(repository.updatedAccountId, 1);
    expect(repository.updatedAccount?.name, 'Bank Harian');
    expect(repository.updatedAccount?.type, AccountType.bank);
    expect(find.text('Bank Harian'), findsOneWidget);
    expect(find.text('Rp 100.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('balance adjustment records a negative audited delta', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    expect(
      find.text(
        'Tidak termasuk transfer dan penyesuaian saldo, termasuk saldo awal.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Rekening').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('open-balance-adjustment')),
    );
    await tester.tap(find.byKey(const Key('open-balance-adjustment')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('target-account-balance')),
      '60000',
    );
    await tester.pump();
    expect(find.text('Penyesuaian mengurangi Rp 40.000.'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('save-balance-adjustment')),
    );
    await tester.tap(find.byKey(const Key('save-balance-adjustment')));
    await tester.pumpAndSettle();

    expect(repository.adjustedAccountId, 1);
    expect(repository.savedAdjustment?.targetBalance, 60000);
    expect(repository.entries.last.kind, EntryKind.adjustment);
    expect(repository.entries.last.amount, -40000);
    expect(find.text('Rp 60.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived account is hidden then can be shown and restored', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.text('Rekening').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('toggle-account-archive')));
    await tester.tap(find.byKey(const Key('toggle-account-archive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-archive-account')));
    await tester.pumpAndSettle();
    expect(
      repository.accounts.singleWhere((item) => item.id == 2).isArchived,
      isTrue,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-2')), findsNothing);
    await tester.tap(find.byKey(const Key('show-archived-accounts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('toggle-account-archive')));
    await tester.tap(find.byKey(const Key('toggle-account-archive')));
    await tester.pumpAndSettle();
    expect(
      repository.accounts.singleWhere((item) => item.id == 2).isArchived,
      isFalse,
    );
    expect(find.text('Aktif'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('last active account stays active and shows archive error', (
    tester,
  ) async {
    final repository = _UiRepository();
    repository.accounts.add(
      const FinanceAccount(
        id: 1,
        name: 'Tunai',
        type: AccountType.cash,
        balance: 0,
      ),
    );
    await pumpApp(tester, repository);
    await tester.tap(find.text('Rekening').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('toggle-account-archive')));
    await tester.tap(find.byKey(const Key('toggle-account-archive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-archive-account')));
    await tester.pumpAndSettle();

    expect(
      find.text('Sisakan setidaknya satu rekening aktif.'),
      findsOneWidget,
    );
    expect(repository.accounts.single.isArchived, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unused account can be permanently deleted after confirmation', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.text('Rekening').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-account')));
    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    expect(find.text('Hapus Bank?'), findsOneWidget);
    expect(repository.deletedAccountId, isNull);
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    await tester.pumpAndSettle();

    expect(repository.deletedAccountId, 2);
    expect(find.byKey(const ValueKey('account-2')), findsNothing);
    expect(find.text('Rekening telah dihapus.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    await tester.ensureVisible(find.byKey(const Key('entry-category')));
    await tester.tap(find.byKey(const Key('entry-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entry-category-option-10')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();
    expect(repository.savedEntry?.kind, EntryKind.expense);
    expect(repository.savedEntry?.amount, 12500);
    expect(repository.savedEntry?.categoryId, 10);
    expect(repository.savedEntry?.destinationAccountId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expense form saves ordered split allocations and live total', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('entry-allocation-row-0')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('entry-allocation-total')), findsNothing);

    await tester.enterText(find.byKey(const Key('entry-amount')), '15000');
    await tester.ensureVisible(find.byKey(const Key('entry-category')));
    await tester.tap(find.byKey(const Key('entry-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entry-category-option-10')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('add-entry-allocation')));
    await tester.tap(find.byKey(const Key('add-entry-allocation')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('entry-allocation-row-1')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('entry-allocation-amount-1')),
      '2000',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('entry-category-1')));
    await tester.tap(find.byKey(const ValueKey('entry-category-1')));
    await tester.pumpAndSettle();
    final usedCategory = tester.widget<ListTile>(
      find.byKey(const ValueKey('entry-category-option-10')),
    );
    expect(usedCategory.enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('entry-category-option-12')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('entry-allocation-total')),
        matching: find.text('Rp 17.000'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();

    expect(repository.savedEntry?.kind, EntryKind.expense);
    expect(repository.savedEntry?.amount, 17000);
    expect(repository.savedEntry?.categoryId, isNull);
    expect(repository.savedEntry?.allocations, hasLength(2));
    expect(
      repository.savedEntry?.allocations.map(
        (allocation) => (allocation.categoryId, allocation.amount),
      ),
      [(10, 15000), (12, 2000)],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('split form rejects a total above the transaction limit', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('entry-amount')),
      maxAmount.toString(),
    );
    await tester.ensureVisible(find.byKey(const Key('add-entry-allocation')));
    await tester.tap(find.byKey(const Key('add-entry-allocation')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('entry-allocation-amount-1')),
      '1',
    );
    await tester.pump();
    expect(find.text('Rp 1.000.000.000.000'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();

    expect(repository.savedEntry, isNull);
    expect(
      find.text('Total transaksi melebihi Rp999.999.999.999.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('entry-amount')),
      (maxAmount - 1).toString(),
    );
    await tester.pump();
    expect(
      find.text('Total transaksi melebihi Rp999.999.999.999.'),
      findsNothing,
    );
    expect(find.text('Rp 999.999.999.999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('split form reserves one active category for each empty row', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    repository.categoryGroups.removeWhere(
      (group) =>
          group.parent.kind == CategoryKind.expense &&
          !const {10, 12}.contains(group.children.single.id),
    );
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();

    final addButton = find.byKey(const Key('add-entry-allocation'));
    expect(tester.widget<OutlinedButton>(addButton).onPressed, isNotNull);
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('entry-allocation-row-1')),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(addButton).onPressed, isNull);
    expect(
      find.text('Tidak ada subkategori aktif lain untuk rincian baru.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('entry-allocation-row-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a middle allocation keeps the other row values', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-amount')), '100');
    await tester.ensureVisible(find.byKey(const Key('entry-category')));
    await tester.tap(find.byKey(const Key('entry-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entry-category-option-10')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('add-entry-allocation')));
    await tester.tap(find.byKey(const Key('add-entry-allocation')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('entry-allocation-amount-1')),
      '200',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('entry-category-1')));
    await tester.tap(find.byKey(const ValueKey('entry-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entry-category-option-12')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('add-entry-allocation')));
    await tester.tap(find.byKey(const Key('add-entry-allocation')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('entry-allocation-amount-2')),
      '300',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('entry-category-2')));
    await tester.tap(find.byKey(const ValueKey('entry-category-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entry-category-option-14')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('remove-entry-allocation-1')),
    );
    await tester.tap(find.byKey(const ValueKey('remove-entry-allocation-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('entry-allocation-row-1')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('entry-amount')))
          .controller
          ?.text,
      '100',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('entry-allocation-amount-2')),
          )
          .controller
          ?.text,
      '300',
    );
    expect(find.text('Rp 400'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();
    expect(
      repository.savedEntry?.allocations.map(
        (allocation) => (allocation.categoryId, allocation.amount),
      ),
      [(10, 100), (14, 300)],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching a split expense to transfer carries only its total', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-amount')), '15000');
    await tester.ensureVisible(find.byKey(const Key('add-entry-allocation')));
    await tester.tap(find.byKey(const Key('add-entry-allocation')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('entry-allocation-amount-1')),
      '2000',
    );

    await tester.ensureVisible(find.byKey(const Key('entry-kind')));
    await tester.tap(find.byKey(const Key('entry-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-entry-allocation')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('entry-amount')))
          .controller
          ?.text,
      '17000',
    );
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();

    expect(repository.savedEntry?.kind, EntryKind.transfer);
    expect(repository.savedEntry?.amount, 17000);
    expect(repository.savedEntry?.allocations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an invalid split clears a transfer total from an earlier toggle',
    (tester) async {
      await pumpApp(tester, _UiRepository(withAccounts: true));
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry-amount')), '17000');

      await tester.ensureVisible(find.byKey(const Key('entry-kind')));
      await tester.tap(find.byKey(const Key('entry-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('entry-amount')))
            .controller
            ?.text,
        '17000',
      );

      await tester.tap(find.byKey(const Key('entry-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pengeluaran').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry-amount')), '');
      await tester.ensureVisible(find.byKey(const Key('entry-kind')));
      await tester.tap(find.byKey(const Key('entry-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer').last);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('entry-amount')))
            .controller
            ?.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching transfer to expense carries amount but requires category',
    (tester) async {
      final repository = _UiRepository(withAccounts: true);
      await pumpApp(tester, repository);
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('entry-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry-amount')), '25000');

      await tester.tap(find.byKey(const Key('entry-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pengeluaran').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('entry-amount')))
            .controller
            ?.text,
        '25000',
      );
      expect(
        tester
            .widget<CategorySelectionField>(find.byType(CategorySelectionField))
            .value,
        isNull,
      );

      await tester.ensureVisible(find.byKey(const Key('save-entry')));
      await tester.tap(find.byKey(const Key('save-entry')));
      await tester.pumpAndSettle();
      expect(repository.savedEntry, isNull);
      expect(find.text('Pilih subkategori.'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('entry-category')));
      await tester.tap(find.byKey(const Key('entry-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('entry-category-option-10')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save-entry')));
      await tester.tap(find.byKey(const Key('save-entry')));
      await tester.pumpAndSettle();

      expect(repository.savedEntry?.kind, EntryKind.expense);
      expect(repository.savedEntry?.destinationAccountId, isNull);
      expect(repository.savedEntry?.allocations, hasLength(1));
      expect(repository.savedEntry?.allocations.single.categoryId, 10);
      expect(repository.savedEntry?.allocations.single.amount, 25000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('transfer uses distinct accounts and no category', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('entry-kind')));
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
    expect(repository.savedEntry?.categoryId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category picker selects leaves and kind changes clear it', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('entry-category')));
    await tester.tap(find.byKey(const Key('entry-category')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('entry-category-option-9')), findsNothing);
    expect(
      find.byKey(const ValueKey('entry-category-option-10')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('entry-category-option-10')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CategorySelectionField>(find.byType(CategorySelectionField))
          .value,
      10,
    );

    await tester.ensureVisible(find.byKey(const Key('add-entry-allocation')));
    await tester.tap(find.byKey(const Key('add-entry-allocation')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('entry-category-1')));
    await tester.tap(find.byKey(const ValueKey('entry-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entry-category-option-12')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CategorySelectionField>(
            find.byType(CategorySelectionField),
          )
          .map((field) => field.value),
      [10, 12],
    );

    await tester.ensureVisible(find.byKey(const Key('entry-kind')));
    await tester.tap(find.byKey(const Key('entry-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pemasukan').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CategorySelectionField>(
            find.byType(CategorySelectionField),
          )
          .map((field) => field.value),
      [null, null],
    );
    expect(repository.savedEntry, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty category field keeps label above its placeholder', (
    tester,
  ) async {
    await pumpApp(tester, _UiRepository(withAccounts: true));
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();

    final categoryField = find.byKey(const Key('entry-category'));
    final label = find.descendant(
      of: categoryField,
      matching: find.text('Subkategori'),
    );
    final placeholder = find.descendant(
      of: categoryField,
      matching: find.text('Pilih subkategori'),
    );
    expect(label, findsOneWidget);
    expect(placeholder, findsOneWidget);
    expect(
      tester.getRect(label).overlaps(tester.getRect(placeholder)),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('category management creates a customizable two-level group', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('manage-categories')));
    await tester.pumpAndSettle();
    expect(find.text('Kelola kategori'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-category-group')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-parent-name')),
      'Rumah',
    );
    await tester.enterText(
      find.byKey(const Key('category-first-child-name')),
      'Listrik',
    );
    await tester.ensureVisible(find.byKey(const Key('category-parent-icon')));
    await tester.tap(find.byKey(const Key('category-parent-icon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-icon-home')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-category-group')));
    await tester.tap(find.byKey(const Key('save-category-group')));
    await tester.pumpAndSettle();

    final group = repository.categoryGroups.singleWhere(
      (item) => item.parent.name == 'Rumah',
    );
    expect(group.parent.iconKey, 'home');
    expect(group.children.single.name, 'Listrik');
    await tester.scrollUntilVisible(
      find.text('Rumah'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Rumah'), findsOneWidget);
    expect(find.text('Listrik'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new category kind stays selected after the group is saved', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('manage-categories')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-category-group')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pemasukan').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-parent-name')),
      'Pendapatan pasif',
    );
    await tester.enterText(
      find.byKey(const Key('category-first-child-name')),
      'Bunga tabungan',
    );
    await tester.ensureVisible(find.byKey(const Key('save-category-group')));
    await tester.tap(find.byKey(const Key('save-category-group')));
    await tester.pumpAndSettle();

    final group = repository.categoryGroups.singleWhere(
      (item) => item.parent.name == 'Pendapatan pasif',
    );
    expect(group.parent.kind, CategoryKind.income);
    final kindSelector = tester.widget<SegmentedButton<CategoryKind>>(
      find.byType(SegmentedButton<CategoryKind>),
    );
    expect(kindSelector.selected, {CategoryKind.income});
    await tester.scrollUntilVisible(
      find.text('Pendapatan pasif'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Pendapatan pasif'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Bunga tabungan'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Bunga tabungan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back from a dirty category form confirms before discarding', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('manage-categories')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-category-group')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-parent-name')),
      'Belum disimpan',
    );
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Buang perubahan kategori?'), findsOneWidget);
    await tester.tap(find.text('Tetap di sini'));
    await tester.pumpAndSettle();
    expect(find.text('Tambah kelompok'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard-category-changes')));
    await tester.pumpAndSettle();
    expect(find.text('Kelola kategori'), findsOneWidget);
    expect(
      repository.categoryGroups.any(
        (item) => item.parent.name == 'Belum disimpan',
      ),
      isFalse,
    );
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('account-1')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Dompet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('split total and controls fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, _UiRepository(withAccounts: true));

    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('entry-amount')),
      maxAmount.toString(),
    );
    await tester.ensureVisible(find.byKey(const Key('add-entry-allocation')));
    await tester.tap(find.byKey(const Key('add-entry-allocation')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('entry-allocation-amount-1')),
      '1',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('entry-allocation-total')));
    await tester.pumpAndSettle();
    expect(find.text('Rp 1.000.000.000.000'), findsOneWidget);
    expect(
      find.text('Total transaksi melebihi Rp999.999.999.999.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remove-entry-allocation-1')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();
    final firstRowRect = tester.getRect(
      find.byKey(const ValueKey('entry-allocation-row-0')),
    );
    expect(firstRowRect.bottom, greaterThan(0));
    expect(firstRowRect.top, lessThan(800));
    expect(find.text('Pilih subkategori.'), findsNWidgets(2));
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

  testWidgets('overview and history use the same compact transaction row', (
    tester,
  ) async {
    final entry = _financeEntry(
      id: 27,
      kind: EntryKind.expense,
      accountId: 1,
      amount: 33500,
      categoryId: 12,
      categoryName: 'Umum',
      parentCategoryName: 'Transportasi',
      categoryIconKey: 'directions_car',
      note: 'Catatan hanya untuk halaman detail',
      occurredAt: DateTime(2026, 9, 5),
      createdAt: DateTime(2026, 9, 5, 10),
    );
    await pumpApp(tester, _UiRepository(withAccounts: true, entry: entry));

    final row = find.byKey(const ValueKey('entry-row-27'));
    await tester.scrollUntilVisible(
      row,
      240,
      scrollable: find.byType(Scrollable).last,
    );

    void expectCompactRow() {
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('entry-title-27'))).data,
        'Transportasi',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('entry-account-27')))
            .data,
        'Dompet',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('entry-amount-27'))).data,
        '− Rp 33.500',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('entry-date-27'))).data,
        '5 Sep 2026',
      );
      expect(find.text('Catatan hanya untuk halaman detail'), findsNothing);
      expect(tester.getSize(row).height, inInclusiveRange(48, 80));
      expect(find.ancestor(of: row, matching: find.byType(Card)), findsNothing);
    }

    expectCompactRow();
    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      row,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expectCompactRow();
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact transaction row fits narrow enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = _UiRepository(
      withAccounts: true,
      entry: _financeEntry(
        id: 28,
        kind: EntryKind.expense,
        accountId: 1,
        amount: maxAmount,
        categoryId: 12,
        categoryName: 'Perjalanan antarkota yang sangat panjang',
        parentCategoryName: 'Transportasi',
        categoryIconKey: 'directions_car',
        note: 'Detail panjang',
        occurredAt: DateTime(2026, 9, 5),
        createdAt: DateTime(2026, 9, 5, 10),
      ),
    );
    repository.accounts[0] = _copyUiAccount(
      repository.accounts[0],
      name: 'Rekening utama dengan nama sangat panjang',
    );
    await pumpApp(tester, repository);

    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('entry-row-28'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const ValueKey('entry-title-28')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-account-28')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('entry-amount-28'))).data,
      '− Rp 999.999.999.999',
    );
    final fittedAmount = tester.widget<FittedBox>(
      find.byKey(const ValueKey('entry-amount-fit-28')),
    );
    expect(fittedAmount.fit, BoxFit.scaleDown);
    expect(fittedAmount.alignment, Alignment.centerRight);
    expect(find.byKey(const ValueKey('entry-date-28')), findsOneWidget);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('transaction row opens details and edit pre-fills the form', (
    tester,
  ) async {
    final entry = _financeEntry(
      id: 7,
      kind: EntryKind.expense,
      accountId: 1,
      amount: 12500,
      categoryId: 10,
      categoryName: 'Umum',
      parentCategoryName: 'Makan & minum',
      categoryIconKey: 'restaurant',
      note: 'Makan siang',
      occurredAt: DateTime(2024, 8, 17),
      createdAt: DateTime(2024, 8, 17, 12, 30),
    );
    final repository = _UiRepository(withAccounts: true, entry: entry);
    await pumpApp(tester, repository);

    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('entry-title-7'))).data,
      'Makan & minum',
    );
    expect(find.text('Makan siang'), findsNothing);
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
    expect(repository.updatedEntry?.categoryId, 10);
    expect(repository.updateCount, 1);
    expect(
      tester.widget<Text>(find.byKey(const Key('entry-detail-amount'))).data,
      '− Rp 15.000',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('split transaction details and edit preserve every allocation', (
    tester,
  ) async {
    final entry = _financeEntry(
      id: 17,
      kind: EntryKind.expense,
      accountId: 1,
      amount: 17000,
      entryAllocations: const [
        FinanceEntryAllocation(
          position: 0,
          categoryId: 10,
          amount: 15000,
          categoryName: 'Umum',
          parentCategoryName: 'Makan & minum',
          categoryIconKey: 'restaurant',
          categoryArchived: false,
        ),
        FinanceEntryAllocation(
          position: 1,
          categoryId: 12,
          amount: 2000,
          categoryName: 'Umum',
          parentCategoryName: 'Transportasi',
          categoryIconKey: 'directions_car',
          categoryArchived: false,
        ),
      ],
      note: 'Makan siang dan parkir',
      occurredAt: DateTime(2024, 8, 17),
      createdAt: DateTime(2024, 8, 17, 12, 30),
    );
    final repository = _UiRepository(withAccounts: true, entry: entry);
    await pumpApp(tester, repository);

    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    expect(find.text('2 rincian'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('entry-amount-17'))).data,
      '− Rp 17.000',
    );
    expect(find.text('Rp 15.000'), findsNothing);
    expect(find.text('Rp 2.000'), findsNothing);
    await tester.tap(find.byKey(const Key('entry-17')));
    await tester.pumpAndSettle();

    expect(find.text('2 rincian'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('entry-detail-allocation-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('entry-detail-allocation-1')),
      findsOneWidget,
    );
    expect(find.text('Rp 15.000'), findsOneWidget);
    expect(find.text('Rp 2.000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-entry')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('entry-amount')))
          .controller
          ?.text,
      '15000',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('entry-allocation-amount-1')),
          )
          .controller
          ?.text,
      '2000',
    );
    expect(
      tester
          .widgetList<CategorySelectionField>(
            find.byType(CategorySelectionField),
          )
          .map((field) => field.value),
      [10, 12],
    );
    expect(find.text('Rp 17.000'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('entry-allocation-amount-1')),
      '3000',
    );
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();

    expect(repository.updatedEntryId, 17);
    expect(repository.updatedEntry?.amount, 18000);
    expect(repository.updatedEntry?.allocations, hasLength(2));
    expect(
      repository.updatedEntry?.allocations.map(
        (allocation) => (allocation.categoryId, allocation.amount),
      ),
      [(10, 15000), (12, 3000)],
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('entry-detail-amount'))).data,
      '− Rp 18.000',
    );
    expect(find.text('Rp 3.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete requires confirmation and removes one transaction', (
    tester,
  ) async {
    final repository = _UiRepository(
      withAccounts: true,
      entry: _financeEntry(
        id: 8,
        kind: EntryKind.income,
        accountId: 1,
        amount: 50000,
        categoryId: 2,
        categoryName: 'Umum',
        parentCategoryName: 'Gaji',
        categoryIconKey: 'work',
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
      entry: _financeEntry(
        id: 9,
        kind: EntryKind.adjustment,
        accountId: 1,
        amount: 100000,
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
    expect(find.text('Rekening'), findsOneWidget);
    expect(find.text('Dari rekening'), findsNothing);
    expect(find.byKey(const Key('edit-entry')), findsNothing);
    expect(find.byKey(const Key('delete-entry')), findsNothing);
    expect(
      find.textContaining('tidak dapat diedit atau dihapus'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('negative adjustment detail uses a neutral account label', (
    tester,
  ) async {
    final repository = _UiRepository(
      withAccounts: true,
      entry: _financeEntry(
        id: 10,
        kind: EntryKind.adjustment,
        accountId: 1,
        amount: -40000,
        note: 'Koreksi setelah cek mutasi',
        occurredAt: DateTime(2024, 8, 2),
        createdAt: DateTime(2024, 8, 2),
      ),
    );
    await pumpApp(tester, repository);
    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-10')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('entry-detail-amount'))).data,
      '-Rp 40.000',
    );
    expect(find.text('Rekening'), findsOneWidget);
    expect(find.text('Dari rekening'), findsNothing);
    expect(find.byKey(const Key('edit-entry')), findsNothing);
    expect(find.byKey(const Key('delete-entry')), findsNothing);
    expect(find.textContaining('bagian jejak audit'), findsOneWidget);
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
      entry: _financeEntry(
        id: 13,
        kind: EntryKind.income,
        accountId: 1,
        amount: 1000,
        categoryId: 6,
        categoryName: 'Umum',
        parentCategoryName: 'Hadiah',
        categoryIconKey: 'redeem',
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
      entry: _financeEntry(
        id: 10,
        kind: EntryKind.expense,
        accountId: 1,
        amount: 10000,
        categoryId: 14,
        categoryName: 'Umum',
        parentCategoryName: 'Belanja',
        categoryIconKey: 'shopping_bag',
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
      entry: _financeEntry(
        id: 11,
        kind: EntryKind.income,
        accountId: 1,
        amount: 75000,
        categoryId: 4,
        categoryName: 'Umum',
        parentCategoryName: 'Usaha',
        categoryIconKey: 'storefront',
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
      entry: _financeEntry(
        id: 12,
        kind: EntryKind.expense,
        accountId: 1,
        amount: 8000,
        categoryId: 12,
        categoryName: 'Umum',
        parentCategoryName: 'Transportasi',
        categoryIconKey: 'directions_car',
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

  testWidgets('calendar shows every entry kind and opens day entry details', (
    tester,
  ) async {
    final repository = _UiRepository(withAccounts: true);
    final date = DateTime(2024, 2, 29);
    repository.entries.addAll([
      _financeEntry(
        id: 31,
        kind: EntryKind.income,
        accountId: 1,
        amount: 90000,
        categoryName: 'Gaji bulanan',
        categoryIconKey: 'work',
        note: '',
        occurredAt: date,
        createdAt: date,
      ),
      _financeEntry(
        id: 32,
        kind: EntryKind.expense,
        accountId: 1,
        amount: 15000,
        categoryName: 'Makan siang',
        categoryIconKey: 'restaurant',
        note: '',
        occurredAt: date,
        createdAt: date,
      ),
      _financeEntry(
        id: 33,
        kind: EntryKind.transfer,
        accountId: 1,
        destinationAccountId: 2,
        amount: 20000,
        note: '',
        occurredAt: date,
        createdAt: date,
      ),
      _financeEntry(
        id: 34,
        kind: EntryKind.adjustment,
        accountId: 1,
        amount: -5000,
        note: 'Koreksi saldo',
        occurredAt: date,
        createdAt: date,
      ),
    ]);
    await pumpApp(tester, repository, today: date);

    await tester.tap(find.byKey(const Key('calendar-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Februari 2024'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -620));
    await tester.pumpAndSettle();
    expect(find.text('29 Feb 2024'), findsOneWidget);
    expect(find.text('Rp 90.000'), findsOneWidget);
    expect(find.text('Rp 15.000'), findsOneWidget);
    expect(find.text('4 catatan • 1 transfer • 1 penyesuaian'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-entry-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-entry-32')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-entry-33')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-entry-34')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('calendar-entry-33')));
    await tester.drag(find.byType(ListView).first, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-entry-33')));
    await tester.pumpAndSettle();
    expect(find.text('Detail transaksi'), findsOneWidget);
    expect(find.text('Dari rekening'), findsOneWidget);
    expect(find.text('Ke rekening'), findsOneWidget);
    expect(find.text('Dompet'), findsWidgets);
    expect(find.text('Bank'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'future calendar days are disabled and add pre-fills selected date',
    (tester) async {
      final repository = _UiRepository(withAccounts: true);
      await pumpApp(tester, repository, today: DateTime(2024, 8, 20));
      await tester.tap(find.byKey(const Key('calendar-tab')));
      await tester.pumpAndSettle();

      final futureDay = tester.widget<InkWell>(
        find.byKey(const ValueKey('calendar-day-2024-08-21')),
      );
      expect(futureDay.onTap, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('calendar-day-2024-08-17')),
      );
      await tester.tap(find.byKey(const ValueKey('calendar-day-2024-08-17')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pumpAndSettle();
      expect(find.text('Catat transaksi'), findsWidgets);
      expect(find.text('Tanggal transaksi: 17 Agu 2024'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar stays usable on a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = _UiRepository(withAccounts: true);
    repository.entries.add(
      _financeEntry(
        id: 41,
        kind: EntryKind.income,
        accountId: 1,
        amount: maxAmount,
        categoryName: 'Pendapatan dengan nama kategori yang sangat panjang',
        categoryIconKey: 'work',
        note: 'Catatan panjang untuk menguji kartu pada perangkat sempit.',
        occurredAt: DateTime(2024, 2, 29),
        createdAt: DateTime(2024, 2, 29),
      ),
    );
    await pumpApp(tester, repository, today: DateTime(2024, 2, 29));

    await tester.tap(find.byKey(const Key('calendar-tab')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('calendar-day-2024-02-29'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('calendar-entry-41')),
      find.byType(ListView).first,
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-entry-41')), findsOneWidget);
    expect(find.text('+ Rp 999.999.999.999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

FinanceEntry _financeEntry({
  required int id,
  required EntryKind kind,
  required int accountId,
  int? destinationAccountId,
  required int amount,
  int? categoryId,
  String? categoryName,
  String? parentCategoryName,
  String? categoryIconKey,
  bool categoryArchived = false,
  List<FinanceEntryAllocation>? entryAllocations,
  required String note,
  required DateTime occurredAt,
  required DateTime createdAt,
}) {
  final categorized = kind == EntryKind.income || kind == EntryKind.expense;
  return FinanceEntry(
    id: id,
    kind: kind,
    accountId: accountId,
    destinationAccountId: destinationAccountId,
    amount: amount,
    allocations: categorized
        ? entryAllocations ??
              [
                FinanceEntryAllocation(
                  position: 0,
                  categoryId: categoryId ?? (kind == EntryKind.income ? 2 : 10),
                  amount: amount,
                  categoryName: categoryName ?? 'Umum',
                  parentCategoryName:
                      parentCategoryName ??
                      (kind == EntryKind.income ? 'Pemasukan' : 'Pengeluaran'),
                  categoryIconKey: categoryIconKey ?? 'category',
                  categoryArchived: categoryArchived,
                ),
              ]
        : const [],
    note: note,
    occurredAt: occurredAt,
    createdAt: createdAt,
  );
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
  final categoryGroups = _defaultCategoryGroups();
  AccountDraft? savedAccount;
  EntryDraft? savedEntry;
  int? updatedEntryId;
  EntryDraft? updatedEntry;
  int updateCount = 0;
  int? deletedEntryId;
  int deleteCount = 0;
  int? updatedAccountId;
  AccountUpdateDraft? updatedAccount;
  int? adjustedAccountId;
  AccountBalanceAdjustmentDraft? savedAdjustment;
  int? archivedAccountId;
  int? deletedAccountId;
  Future<void> Function(int, EntryDraft)? onUpdateEntry;
  Future<void> Function(int)? onDeleteEntry;
  final _changes = StreamController<void>.broadcast(sync: true);

  Future<void> dispose() => _changes.close();

  @override
  Stream<List<FinanceAccount>> watchAccounts({
    bool includeArchived = false,
  }) async* {
    if (failRead) throw StateError('Read failure');
    List<FinanceAccount> visible() => accounts
        .where((account) => includeArchived || !account.isArchived)
        .toList(growable: false);
    yield visible();
    await for (final _ in _changes.stream) {
      yield visible();
    }
  }

  @override
  Stream<AccountDetails?> watchAccountDetails(int id) async* {
    if (failRead) throw StateError('Read failure');
    yield await getAccountDetails(id);
    await for (final _ in _changes.stream) {
      yield await getAccountDetails(id);
    }
  }

  @override
  Future<AccountDetails?> getAccountDetails(int id) async {
    final account = accounts.where((item) => item.id == id).firstOrNull;
    if (account == null) return null;
    var count = entries
        .where(
          (entry) => entry.accountId == id || entry.destinationAccountId == id,
        )
        .length;
    if (count == 0 && account.balance != 0) count = 1;
    return AccountDetails(
      account: account,
      createdAt: DateTime(2024, 1, 1),
      ledgerEntryCount: count,
    );
  }

  @override
  Stream<List<CategoryGroup>> watchCategoryTree(
    CategoryKind kind, {
    bool includeArchived = false,
  }) async* {
    yield _visibleCategoryGroups(kind, includeArchived: includeArchived);
    await for (final _ in _changes.stream) {
      yield _visibleCategoryGroups(kind, includeArchived: includeArchived);
    }
  }

  List<CategoryGroup> _visibleCategoryGroups(
    CategoryKind kind, {
    required bool includeArchived,
  }) => [
    for (final group in categoryGroups)
      if (group.parent.kind == kind &&
          (includeArchived || !group.parent.isArchived))
        CategoryGroup(
          parent: group.parent,
          children: [
            for (final child in group.children)
              if (includeArchived || !child.isArchived) child,
          ],
        ),
  ];

  @override
  Future<int> createCategoryGroup(CategoryGroupDraft draft) async {
    final parentId = _nextCategoryId;
    final childId = parentId + 1;
    final now = DateTime(2024, 1, 1);
    final parent = FinanceCategory(
      id: parentId,
      parentId: null,
      kind: draft.kind,
      name: draft.parentName.trim(),
      iconKey: draft.parentIconKey,
      isArchived: false,
      sortOrder: draft.parentSortOrder,
      systemKey: null,
      createdAt: now,
      updatedAt: now,
    );
    final child = FinanceCategory(
      id: childId,
      parentId: parentId,
      kind: draft.kind,
      name: draft.firstChildName.trim(),
      iconKey: draft.firstChildIconKey,
      isArchived: false,
      sortOrder: draft.firstChildSortOrder,
      systemKey: null,
      createdAt: now,
      updatedAt: now,
    );
    categoryGroups.add(CategoryGroup(parent: parent, children: [child]));
    _changes.add(null);
    return parentId;
  }

  @override
  Future<int> createSubcategory(CategoryDraft draft) async {
    final parentId = draft.parentId;
    final groupIndex = categoryGroups.indexWhere(
      (group) => group.parent.id == parentId,
    );
    if (groupIndex < 0) {
      throw const FinanceValidationException('Kategori tidak ditemukan.');
    }
    final group = categoryGroups[groupIndex];
    final id = _nextCategoryId;
    final child = FinanceCategory(
      id: id,
      parentId: parentId,
      kind: group.parent.kind,
      name: draft.name.trim(),
      iconKey: draft.iconKey,
      isArchived: false,
      sortOrder: draft.sortOrder,
      systemKey: null,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    categoryGroups[groupIndex] = CategoryGroup(
      parent: group.parent,
      children: [...group.children, child],
    );
    _changes.add(null);
    return id;
  }

  @override
  Future<void> updateCategory(int categoryId, CategoryDraft draft) async {
    for (var index = 0; index < categoryGroups.length; index++) {
      final group = categoryGroups[index];
      if (group.parent.id == categoryId) {
        categoryGroups[index] = CategoryGroup(
          parent: _copyUiCategory(
            group.parent,
            name: draft.name.trim(),
            iconKey: draft.iconKey,
            sortOrder: draft.sortOrder,
          ),
          children: group.children,
        );
        _changes.add(null);
        return;
      }
      final childIndex = group.children.indexWhere(
        (child) => child.id == categoryId,
      );
      if (childIndex >= 0) {
        final children = [...group.children];
        children[childIndex] = _copyUiCategory(
          children[childIndex],
          name: draft.name.trim(),
          iconKey: draft.iconKey,
          sortOrder: draft.sortOrder,
        );
        categoryGroups[index] = CategoryGroup(
          parent: group.parent,
          children: children,
        );
        _changes.add(null);
        return;
      }
    }
    throw const FinanceValidationException('Kategori tidak ditemukan.');
  }

  @override
  Future<void> setCategoryArchived(int categoryId, bool archived) async {
    for (var index = 0; index < categoryGroups.length; index++) {
      final group = categoryGroups[index];
      if (group.parent.id == categoryId) {
        categoryGroups[index] = CategoryGroup(
          parent: _copyUiCategory(group.parent, isArchived: archived),
          children: group.children,
        );
        _changes.add(null);
        return;
      }
      final childIndex = group.children.indexWhere(
        (child) => child.id == categoryId,
      );
      if (childIndex >= 0) {
        final children = [...group.children];
        children[childIndex] = _copyUiCategory(
          children[childIndex],
          isArchived: archived,
        );
        categoryGroups[index] = CategoryGroup(
          parent: group.parent,
          children: children,
        );
        _changes.add(null);
        return;
      }
    }
    throw const FinanceValidationException('Kategori tidak ditemukan.');
  }

  int get _nextCategoryId {
    var largest = 0;
    for (final group in categoryGroups) {
      if (group.parent.id > largest) largest = group.parent.id;
      for (final child in group.children) {
        if (child.id > largest) largest = child.id;
      }
    }
    return largest + 1;
  }

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
  Future<void> updateAccount(int id, AccountUpdateDraft draft) async {
    final index = accounts.indexWhere((account) => account.id == id);
    if (index < 0) {
      throw const FinanceValidationException('Rekening tidak ditemukan.');
    }
    final normalized = _normalizeUiAccountName(draft.name);
    if (normalized.isEmpty) {
      throw const FinanceValidationException('Nama rekening wajib diisi.');
    }
    if (accounts.any(
      (account) =>
          account.id != id &&
          _normalizeUiAccountName(account.name) == normalized,
    )) {
      throw const FinanceValidationException('Nama rekening sudah digunakan.');
    }
    updatedAccountId = id;
    updatedAccount = draft;
    accounts[index] = _copyUiAccount(
      accounts[index],
      name: draft.name.trim(),
      type: draft.type,
    );
    _changes.add(null);
  }

  @override
  Future<void> setAccountArchived(int id, bool archived) async {
    final index = accounts.indexWhere((account) => account.id == id);
    if (index < 0) {
      throw const FinanceValidationException('Rekening tidak ditemukan.');
    }
    final account = accounts[index];
    if (archived) {
      if (account.balance != 0) {
        throw const FinanceValidationException(
          'Saldo rekening harus Rp 0 sebelum diarsipkan.',
        );
      }
      if (accounts.where((item) => !item.isArchived).length <= 1) {
        throw const FinanceValidationException(
          'Sisakan setidaknya satu rekening aktif.',
        );
      }
    }
    archivedAccountId = id;
    accounts[index] = _copyUiAccount(account, isArchived: archived);
    _changes.add(null);
  }

  @override
  Future<void> deleteAccount(int id) async {
    final index = accounts.indexWhere((account) => account.id == id);
    if (index < 0) {
      throw const FinanceValidationException('Rekening tidak ditemukan.');
    }
    final details = await getAccountDetails(id);
    if (details == null || !details.canDelete) {
      throw const FinanceValidationException(
        'Rekening yang sudah memiliki riwayat tidak dapat dihapus.',
      );
    }
    deletedAccountId = id;
    accounts.removeAt(index);
    _changes.add(null);
  }

  @override
  Future<int> adjustAccountBalance(
    int id,
    AccountBalanceAdjustmentDraft draft,
  ) async {
    final index = accounts.indexWhere((account) => account.id == id);
    if (index < 0) {
      throw const FinanceValidationException('Rekening tidak ditemukan.');
    }
    final account = accounts[index];
    if (account.isArchived) {
      throw const FinanceValidationException(
        'Pulihkan rekening sebelum menyesuaikan saldo.',
      );
    }
    final delta = draft.targetBalance - account.balance;
    if (delta == 0) {
      throw const FinanceValidationException(
        'Saldo baru masih sama dengan saldo saat ini.',
      );
    }
    adjustedAccountId = id;
    savedAdjustment = draft;
    accounts[index] = _copyUiAccount(account, balance: draft.targetBalance);
    final entryId =
        entries.fold<int>(0, (max, item) {
          return item.id > max ? item.id : max;
        }) +
        1;
    entries.add(
      _financeEntry(
        id: entryId,
        kind: EntryKind.adjustment,
        accountId: id,
        amount: delta,
        note: draft.note.trim().isEmpty
            ? 'Penyesuaian saldo'
            : draft.note.trim(),
        occurredAt: draft.occurredAt,
        createdAt: DateTime(2024, 1, 1),
      ),
    );
    _changes.add(null);
    return entryId;
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
    final updatedAllocations = <FinanceEntryAllocation>[];
    for (var position = 0; position < draft.allocations.length; position++) {
      final allocation = draft.allocations[position];
      final selection = _findUiCategory(allocation.categoryId, categoryGroups);
      updatedAllocations.add(
        FinanceEntryAllocation(
          position: position,
          categoryId: allocation.categoryId,
          amount: allocation.amount,
          categoryName: selection.child.name,
          parentCategoryName: selection.parent.name,
          categoryIconKey: selection.child.iconKey,
          categoryArchived:
              selection.child.isArchived || selection.parent.isArchived,
        ),
      );
    }
    entries[index] = _financeEntry(
      id: id,
      kind: draft.kind,
      accountId: draft.accountId,
      destinationAccountId: draft.destinationAccountId,
      amount: draft.amount,
      categoryId: draft.categoryId,
      entryAllocations: updatedAllocations,
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

  @override
  Stream<CalendarMonthSnapshot> watchCalendarMonth(DateTime month) async* {
    if (failRead) throw StateError('Read failure');
    CalendarMonthSnapshot snapshot() => _calendarSnapshot(month);
    yield snapshot();
    await for (final _ in _changes.stream) {
      yield snapshot();
    }
  }

  CalendarMonthSnapshot _calendarSnapshot(DateTime month) {
    final matching = entries.where(
      (entry) =>
          entry.occurredAt.year == month.year &&
          entry.occurredAt.month == month.month,
    );
    final byDay = <int, List<FinanceEntry>>{};
    for (final entry in matching) {
      byDay.putIfAbsent(entry.occurredAt.day, () => []).add(entry);
    }
    return CalendarMonthSnapshot(
      month: DateTime(month.year, month.month),
      days: [
        for (final day in byDay.keys.toList()..sort())
          CalendarDaySummary(
            day: DateTime(month.year, month.month, day),
            income: byDay[day]!
                .where((entry) => entry.kind == EntryKind.income)
                .fold(0, (sum, entry) => sum + entry.amount),
            expense: byDay[day]!
                .where((entry) => entry.kind == EntryKind.expense)
                .fold(0, (sum, entry) => sum + entry.amount),
            transferCount: byDay[day]!
                .where((entry) => entry.kind == EntryKind.transfer)
                .length,
            adjustmentCount: byDay[day]!
                .where((entry) => entry.kind == EntryKind.adjustment)
                .length,
            entryCount: byDay[day]!.length,
          ),
      ],
    );
  }

  @override
  Stream<List<FinanceEntry>> watchDay(DateTime day) async* {
    if (failRead) throw StateError('Read failure');
    List<FinanceEntry> matching() => entries
        .where(
          (entry) =>
              entry.occurredAt.year == day.year &&
              entry.occurredAt.month == day.month &&
              entry.occurredAt.day == day.day,
        )
        .toList(growable: false);
    yield matching();
    await for (final _ in _changes.stream) {
      yield matching();
    }
  }
}

({FinanceCategory parent, FinanceCategory child}) _findUiCategory(
  int categoryId,
  List<CategoryGroup> groups,
) {
  for (final group in groups) {
    for (final child in group.children) {
      if (child.id == categoryId) return (parent: group.parent, child: child);
    }
  }
  throw StateError('Kategori test $categoryId tidak ditemukan.');
}

List<CategoryGroup> _defaultCategoryGroups() => [
  _uiGroup(1, 2, CategoryKind.income, 'Gaji', 'work'),
  _uiGroup(3, 4, CategoryKind.income, 'Usaha', 'storefront'),
  _uiGroup(5, 6, CategoryKind.income, 'Hadiah', 'redeem'),
  _uiGroup(7, 8, CategoryKind.income, 'Lainnya', 'more_horiz'),
  _uiGroup(9, 10, CategoryKind.expense, 'Makan & minum', 'restaurant'),
  _uiGroup(11, 12, CategoryKind.expense, 'Transportasi', 'directions_car'),
  _uiGroup(13, 14, CategoryKind.expense, 'Belanja', 'shopping_bag'),
  _uiGroup(15, 16, CategoryKind.expense, 'Tagihan', 'receipt_long'),
  _uiGroup(17, 18, CategoryKind.expense, 'Kesehatan', 'medical_services'),
  _uiGroup(19, 20, CategoryKind.expense, 'Hiburan', 'movie'),
  _uiGroup(21, 22, CategoryKind.expense, 'Lainnya', 'more_horiz'),
];

CategoryGroup _uiGroup(
  int parentId,
  int childId,
  CategoryKind kind,
  String name,
  String iconKey,
) {
  final date = DateTime(2024, 1, 1);
  return CategoryGroup(
    parent: FinanceCategory(
      id: parentId,
      parentId: null,
      kind: kind,
      name: name,
      iconKey: iconKey,
      isArchived: false,
      sortOrder: parentId,
      systemKey: 'test.parent.$parentId',
      createdAt: date,
      updatedAt: date,
    ),
    children: [
      FinanceCategory(
        id: childId,
        parentId: parentId,
        kind: kind,
        name: 'Umum',
        iconKey: iconKey,
        isArchived: false,
        sortOrder: 0,
        systemKey: 'test.child.$childId',
        createdAt: date,
        updatedAt: date,
      ),
    ],
  );
}

FinanceCategory _copyUiCategory(
  FinanceCategory category, {
  String? name,
  String? iconKey,
  bool? isArchived,
  int? sortOrder,
}) => FinanceCategory(
  id: category.id,
  parentId: category.parentId,
  kind: category.kind,
  name: name ?? category.name,
  iconKey: iconKey ?? category.iconKey,
  isArchived: isArchived ?? category.isArchived,
  sortOrder: sortOrder ?? category.sortOrder,
  systemKey: category.systemKey,
  createdAt: category.createdAt,
  updatedAt: DateTime(2024, 1, 2),
);

FinanceAccount _copyUiAccount(
  FinanceAccount account, {
  String? name,
  AccountType? type,
  int? balance,
  bool? isArchived,
}) => FinanceAccount(
  id: account.id,
  name: name ?? account.name,
  type: type ?? account.type,
  balance: balance ?? account.balance,
  isArchived: isArchived ?? account.isArchived,
);

String _normalizeUiAccountName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

extension<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
