import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/backup/drift_backup_data_store.dart';
import 'package:waras_arta/data/database/app_database.dart';
import 'package:waras_arta/data/repositories/drift_finance_repository.dart';
import 'package:waras_arta/domain/backup.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
  late bool previousMultipleDatabaseWarning;
  final createdAtUtc = DateTime.utc(2026, 9, 6, 7, 30);
  final occurredAt = DateTime(2024, 3, 15);
  late AppDatabase sourceDb;
  late AppDatabase targetDb;
  late DriftFinanceRepository sourceFinance;
  late DriftFinanceRepository targetFinance;
  late DriftBackupDataStore sourceStore;
  late DriftBackupDataStore targetStore;

  setUpAll(() {
    previousMultipleDatabaseWarning =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        previousMultipleDatabaseWarning;
  });

  setUp(() {
    sourceDb = AppDatabase(NativeDatabase.memory());
    targetDb = AppDatabase(NativeDatabase.memory());
    sourceFinance = DriftFinanceRepository(sourceDb);
    targetFinance = DriftFinanceRepository(targetDb);
    sourceStore = DriftBackupDataStore(sourceDb);
    targetStore = DriftBackupDataStore(targetDb);
  });

  tearDown(() async {
    await sourceDb.close();
    await targetDb.close();
  });

  Future<int> createAccount(
    DriftFinanceRepository repository,
    String name, {
    int openingBalance = 0,
    AccountBalanceGroup balanceGroup = AccountBalanceGroup.primary,
  }) => repository.createAccount(
    AccountDraft(
      name: name,
      type: AccountType.bank,
      balanceGroup: balanceGroup,
      openingBalance: openingBalance,
      openedAt: occurredAt,
    ),
  );

  EntryDraft income(
    int accountId,
    int amount, {
    String note = '',
    int categoryId = 2,
  }) => EntryDraft.singleAllocation(
    kind: EntryKind.income,
    accountId: accountId,
    amount: amount,
    categoryId: categoryId,
    note: note,
    occurredAt: occurredAt,
  );

  test(
    'JSON v3 split round-trip preserves account groups and ID sequences',
    () async {
      final walletId = await createAccount(
        sourceFinance,
        'Dompet Utama',
        openingBalance: 1000,
      );
      final bankId = await createAccount(
        sourceFinance,
        'Bank',
        balanceGroup: AccountBalanceGroup.savingsInvestment,
      );
      final disposableId = await createAccount(sourceFinance, 'Sementara');
      await sourceFinance.deleteAccount(disposableId);
      final bonusCategoryId = await sourceFinance.createSubcategory(
        const CategoryDraft(
          parentId: 1,
          name: 'Bonus tahunan',
          iconKey: 'redeem',
          sortOrder: 7,
        ),
      );

      await sourceFinance.addEntry(
        EntryDraft.withAllocations(
          kind: EntryKind.income,
          accountId: walletId,
          allocations: [
            const EntryAllocationDraft(categoryId: 2, amount: 300),
            EntryAllocationDraft(categoryId: bonusCategoryId, amount: 200),
          ],
          note: 'Gaji tambahan',
          occurredAt: occurredAt,
        ),
      );
      await sourceFinance.addEntry(
        EntryDraft.singleAllocation(
          kind: EntryKind.expense,
          accountId: walletId,
          amount: 200,
          categoryId: 10,
          note: 'Makan siang',
          occurredAt: occurredAt,
        ),
      );
      await sourceFinance.addEntry(
        EntryDraft.transfer(
          accountId: walletId,
          destinationAccountId: bankId,
          amount: 100,
          note: 'Pindah dana',
          occurredAt: occurredAt,
        ),
      );
      await sourceFinance.adjustAccountBalance(
        bankId,
        AccountBalanceAdjustmentDraft(
          targetBalance: 50,
          note: 'Koreksi',
          occurredAt: occurredAt,
        ),
      );
      final removedEntryId = await sourceFinance.addEntry(
        income(bankId, 25, note: 'Akan dihapus'),
      );
      await sourceFinance.deleteEntry(removedEntryId);

      final source = await sourceStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      final decoded = BackupDocument.fromJson(
        (jsonDecode(jsonEncode(source.toJson())) as Map)
            .cast<String, Object?>(),
      );
      expect(decoded.summary.accountCount, 2);
      expect(
        decoded.accounts
            .singleWhere((account) => account.id == bankId)
            .balanceGroup,
        AccountBalanceGroup.savingsInvestment,
      );
      expect(decoded.summary.categoryCount, 23);
      expect(decoded.summary.ledgerEntryCount, 5);
      final split = decoded.ledgerEntries.singleWhere(
        (entry) => entry.note == 'Gaji tambahan',
      );
      expect(split.allocations.map((item) => item.position), [0, 1]);
      expect(split.allocations.map((item) => item.amount), [300, 200]);
      expect(
        decoded.sequences.accounts,
        greaterThan(_maximumAccountId(decoded)),
      );
      expect(
        decoded.sequences.ledgerEntries,
        greaterThan(_maximumLedgerId(decoded)),
      );

      for (var index = 0; index < 12; index++) {
        final id = await createAccount(targetFinance, 'Target $index');
        await targetFinance.deleteAccount(id);
      }
      final dirty = await targetStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      expect(dirty.sequences.accounts, greaterThan(decoded.sequences.accounts));

      await targetStore.restoreDocument(decoded);
      final restored = await targetStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      expect(restored.toJson(), decoded.toJson());

      final nextAccountId = await createAccount(
        targetFinance,
        'Sesudah restore',
      );
      expect(nextAccountId, decoded.sequences.accounts + 1);
      final nextCategoryId = await targetFinance.createSubcategory(
        const CategoryDraft(
          parentId: 1,
          name: 'Sesudah restore',
          iconKey: 'work',
        ),
      );
      expect(nextCategoryId, decoded.sequences.categories + 1);
      final nextLedgerId = await targetFinance.addEntry(
        income(nextAccountId, 1, note: 'Sesudah restore'),
      );
      expect(nextLedgerId, decoded.sequences.ledgerEntries + 1);
    },
  );

  test('restores payload v1/schema 3 into schema 5 allocations', () async {
    final accountId = await createAccount(sourceFinance, 'Sumber lama');
    await sourceFinance.addEntry(income(accountId, 125, note: 'Transaksi v1'));
    final current = await sourceStore.exportDocument(
      createdAtUtc: createdAtUtc,
    );
    final legacyJson = (jsonDecode(jsonEncode(current.toJson())) as Map)
        .cast<String, Object?>();
    legacyJson['backupVersion'] = 1;
    legacyJson['databaseSchemaVersion'] = 3;
    final data = legacyJson['data']! as Map<String, Object?>;
    final accounts = data['accounts']! as List<Object?>;
    for (final value in accounts) {
      (value as Map<String, Object?>).remove('balanceGroup');
    }
    final entries = data['ledgerEntries']! as List<Object?>;
    for (final value in entries) {
      final entry = value as Map<String, Object?>;
      final allocations = entry.remove('allocations')! as List<Object?>;
      entry['categoryId'] = allocations.isEmpty
          ? null
          : (allocations.single as Map<String, Object?>)['categoryId'];
    }
    final legacy = BackupDocument.fromJson(legacyJson);

    await targetStore.restoreDocument(legacy);
    final restored = await targetStore.exportDocument(
      createdAtUtc: createdAtUtc,
    );

    expect(restored.backupVersion, 3);
    expect(restored.databaseSchemaVersion, 5);
    expect(restored.accounts.single.balanceGroup, AccountBalanceGroup.primary);
    final restoredEntry = restored.ledgerEntries.single;
    expect(restoredEntry.id, legacy.ledgerEntries.single.id);
    expect(restoredEntry.amount, 125);
    expect(restoredEntry.allocations, hasLength(1));
    expect(restoredEntry.allocations.single.position, 0);
    expect(restoredEntry.allocations.single.categoryId, 2);
    expect(restoredEntry.allocations.single.amount, 125);
  });

  test('restores payload v2/schema 4 accounts as Saldo utama', () async {
    final accountId = await createAccount(
      sourceFinance,
      'Simpanan lama',
      balanceGroup: AccountBalanceGroup.savingsInvestment,
    );
    await sourceFinance.addEntry(income(accountId, 250));
    final current = await sourceStore.exportDocument(
      createdAtUtc: createdAtUtc,
    );
    final legacyJson = (jsonDecode(jsonEncode(current.toJson())) as Map)
        .cast<String, Object?>();
    legacyJson['backupVersion'] = 2;
    legacyJson['databaseSchemaVersion'] = 4;
    final data = legacyJson['data']! as Map<String, Object?>;
    final accounts = data['accounts']! as List<Object?>;
    for (final value in accounts) {
      (value as Map<String, Object?>).remove('balanceGroup');
    }

    final legacy = BackupDocument.fromJson(legacyJson);
    expect(legacy.accounts.single.balanceGroup, AccountBalanceGroup.primary);

    await targetStore.restoreDocument(legacy);
    final details = await targetFinance.getAccountDetails(accountId);
    expect(details?.account.balance, 250);
    expect(details?.account.balanceGroup, AccountBalanceGroup.primary);
  });

  test('backup adapter coverage pins schema v5 tables and persistent columns', () async {
    expect(
      sourceDb.schemaVersion,
      5,
      reason:
          'A database schema bump must update the backup DTO, encoder, restore, '
          'decoder migration, and coverage guard before this expectation.',
    );
    final actualTableColumns = <String, Set<String>>{
      for (final table in sourceDb.allTables)
        table.actualTableName: {
          for (final column in table.$columns) column.$name,
        },
    };
    expect(
      actualTableColumns,
      const <String, Set<String>>{
        'accounts': {
          'id',
          'name',
          'normalized_name',
          'type',
          'balance_group',
          'is_archived',
          'created_at',
        },
        'categories': {
          'id',
          'parent_id',
          'kind',
          'name',
          'normalized_name',
          'icon_key',
          'is_archived',
          'sort_order',
          'system_key',
          'created_at',
          'updated_at',
        },
        'ledger_entries': {
          'id',
          'kind',
          'account_id',
          'destination_account_id',
          'amount',
          'note',
          'occurred_day',
          'created_at',
        },
        'ledger_allocations': {'entry_id', 'position', 'category_id', 'amount'},
      },
      reason:
          'Every persistent table and column must be represented by the backup '
          'format before the adapter coverage is updated.',
    );

    final document = await sourceStore.exportDocument(
      createdAtUtc: createdAtUtc,
    );
    expect(document.backupVersion, 3);
    expect(document.databaseSchemaVersion, 5);
  });

  test('export fails closed for an uncovered database schema', () async {
    final futureDb = _UncoveredSchemaDatabase(NativeDatabase.memory());
    addTearDown(futureDb.close);
    final futureStore = DriftBackupDataStore(futureDb);

    await expectLater(
      futureStore.exportDocument(createdAtUtc: createdAtUtc),
      throwsA(
        isA<BackupPersistenceException>().having(
          (error) => error.message,
          'message',
          contains('belum mencakup struktur database'),
        ),
      ),
    );
  });

  test(
    'restore fails closed when target database schema is uncovered',
    () async {
      final currentDocument = await sourceStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      final futureDb = _UncoveredSchemaDatabase(NativeDatabase.memory());
      addTearDown(futureDb.close);
      final futureStore = DriftBackupDataStore(futureDb);

      await expectLater(
        futureStore.restoreDocument(currentDocument),
        throwsA(
          isA<BackupPersistenceException>().having(
            (error) => error.message,
            'message',
            contains('belum mencakup struktur database'),
          ),
        ),
      );
    },
  );

  test('restore keeps archived accounts and their historical ledger', () async {
    final archivedId = await createAccount(
      sourceFinance,
      'Rekening Lama',
      balanceGroup: AccountBalanceGroup.savingsInvestment,
    );
    final activeId = await createAccount(sourceFinance, 'Rekening Aktif');
    await sourceFinance.addEntry(
      income(archivedId, 100, note: 'Riwayat sebelum arsip'),
    );
    await sourceFinance.addEntry(
      EntryDraft.transfer(
        accountId: archivedId,
        destinationAccountId: activeId,
        amount: 100,
        note: 'Kosongkan rekening',
        occurredAt: occurredAt,
      ),
    );
    await sourceFinance.setAccountArchived(archivedId, true);

    final document = await sourceStore.exportDocument(
      createdAtUtc: createdAtUtc,
    );
    await targetStore.restoreDocument(document);

    final archivedRow = await (targetDb.select(
      targetDb.accounts,
    )..where((row) => row.id.equals(archivedId))).getSingle();
    expect(archivedRow.isArchived, isTrue);
    expect(
      AccountBalanceGroup.values[archivedRow.balanceGroup],
      AccountBalanceGroup.savingsInvestment,
    );
    expect(await targetDb.select(targetDb.ledgerEntries).get(), hasLength(2));
    final details = await targetFinance.getAccountDetails(archivedId);
    expect(details?.account.balance, 0);
    expect(
      details?.account.balanceGroup,
      AccountBalanceGroup.savingsInvestment,
    );
    expect(details?.ledgerEntryCount, 2);
  });

  test(
    'export and restore allow a valid state with only archived accounts',
    () async {
      final archivedId = await createAccount(sourceFinance, 'Rekening Lama');
      final disposableId = await createAccount(sourceFinance, 'Sementara');
      await sourceFinance.setAccountArchived(archivedId, true);
      await sourceFinance.deleteAccount(disposableId);

      final document = await sourceStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      expect(document.accounts, hasLength(1));
      expect(document.accounts.single.isArchived, isTrue);

      await targetStore.restoreDocument(document);
      final restored = await targetStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      expect(restored.toJson(), document.toJson());
    },
  );

  test(
    'allocation insert failure rolls back account groups, data, and sequences',
    () async {
      final sourceId = await createAccount(sourceFinance, 'Sumber backup');
      final secondCategoryId = await sourceFinance.createSubcategory(
        const CategoryDraft(
          parentId: 1,
          name: 'Pemicu rollback',
          iconKey: 'redeem',
        ),
      );
      await sourceFinance.addEntry(
        EntryDraft.withAllocations(
          kind: EntryKind.income,
          accountId: sourceId,
          allocations: [
            const EntryAllocationDraft(categoryId: 2, amount: 10),
            EntryAllocationDraft(categoryId: secondCategoryId, amount: 15),
          ],
          note: 'Paksa kegagalan restore',
          occurredAt: occurredAt,
        ),
      );
      final incoming = await sourceStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );

      final oldId = await createAccount(
        targetFinance,
        'Data lama',
        balanceGroup: AccountBalanceGroup.savingsInvestment,
      );
      await targetFinance.addEntry(income(oldId, 10, note: 'Harus tetap ada'));
      final before = await targetStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      expect(
        before.accounts.single.balanceGroup,
        AccountBalanceGroup.savingsInvestment,
      );
      await targetDb.customStatement('''
      CREATE TRIGGER test_force_restore_failure
      BEFORE INSERT ON ledger_allocations
      WHEN NEW.position = 1
      BEGIN SELECT RAISE(ABORT, 'forced restore failure'); END
    ''');

      await expectLater(
        targetStore.restoreDocument(incoming),
        throwsA(isA<BackupPersistenceException>()),
      );

      final after = await targetStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      expect(after.toJson(), before.toJson());
      expect(
        after.accounts.single.balanceGroup,
        AccountBalanceGroup.savingsInvestment,
      );
      expect(after.sequences.toJson(), before.sequences.toJson());
    },
  );

  test(
    'corrupt relationships are rejected before existing data changes',
    () async {
      final sourceId = await createAccount(sourceFinance, 'Sumber');
      await sourceFinance.addEntry(income(sourceId, 50));
      final valid = await sourceStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      final corruptedJson = valid.toJson();
      final data = corruptedJson['data']! as Map<String, Object?>;
      final ledgerEntries = data['ledgerEntries']! as List<Object?>;
      final firstEntry = ledgerEntries.first as Map<String, Object?>;
      firstEntry['accountId'] = 999999;

      final oldId = await createAccount(targetFinance, 'Tetap tersimpan');
      await targetFinance.addEntry(income(oldId, 10));
      final before = await targetStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );

      expect(
        () => BackupDocument.fromJson(corruptedJson),
        throwsA(isA<BackupValidationException>()),
      );
      final after = await targetStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      expect(after.toJson(), before.toJson());
    },
  );
}

int _maximumAccountId(BackupDocument document) => document.accounts.fold(
  0,
  (maximum, account) => account.id > maximum ? account.id : maximum,
);

int _maximumLedgerId(BackupDocument document) => document.ledgerEntries.fold(
  0,
  (maximum, entry) => entry.id > maximum ? entry.id : maximum,
);

class _UncoveredSchemaDatabase extends AppDatabase {
  _UncoveredSchemaDatabase(super.executor);

  @override
  int get schemaVersion => 999;
}
