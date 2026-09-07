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
  }) => repository.createAccount(
    AccountDraft(
      name: name,
      type: AccountType.bank,
      openingBalance: openingBalance,
      openedAt: occurredAt,
    ),
  );

  EntryDraft income(
    int accountId,
    int amount, {
    String note = '',
    int categoryId = 2,
  }) => EntryDraft(
    kind: EntryKind.income,
    accountId: accountId,
    amount: amount,
    categoryId: categoryId,
    note: note,
    occurredAt: occurredAt,
  );

  test(
    'JSON v1 round-trip replaces dirty data and preserves ID sequences',
    () async {
      final walletId = await createAccount(
        sourceFinance,
        'Dompet Utama',
        openingBalance: 1000,
      );
      final bankId = await createAccount(sourceFinance, 'Bank');
      final disposableId = await createAccount(sourceFinance, 'Sementara');
      await sourceFinance.deleteAccount(disposableId);

      await sourceFinance.addEntry(
        income(walletId, 500, note: 'Gaji tambahan'),
      );
      await sourceFinance.addEntry(
        EntryDraft(
          kind: EntryKind.expense,
          accountId: walletId,
          amount: 200,
          categoryId: 10,
          note: 'Makan siang',
          occurredAt: occurredAt,
        ),
      );
      await sourceFinance.addEntry(
        EntryDraft(
          kind: EntryKind.transfer,
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
      await sourceFinance.createSubcategory(
        const CategoryDraft(
          parentId: 1,
          name: 'Bonus tahunan',
          iconKey: 'redeem',
          sortOrder: 7,
        ),
      );

      final source = await sourceStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      final decoded = BackupDocument.fromJson(
        (jsonDecode(jsonEncode(source.toJson())) as Map)
            .cast<String, Object?>(),
      );
      expect(decoded.summary.accountCount, 2);
      expect(decoded.summary.categoryCount, 23);
      expect(decoded.summary.ledgerEntryCount, 5);
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

  test('backup adapter coverage pins schema v3 tables and persistent columns', () async {
    expect(
      sourceDb.schemaVersion,
      3,
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
          'category_id',
          'note',
          'occurred_day',
          'created_at',
        },
      },
      reason:
          'Every persistent table and column must be represented by the backup '
          'format before the adapter coverage is updated.',
    );

    final document = await sourceStore.exportDocument(
      createdAtUtc: createdAtUtc,
    );
    expect(document.backupVersion, 1);
    expect(document.databaseSchemaVersion, 3);
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
    'restore fails closed when payload claims an uncovered database schema',
    () async {
      final currentDocument = await sourceStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      final futureJson = currentDocument.toJson();
      futureJson['databaseSchemaVersion'] = 999;
      final claimedFutureDocument = BackupDocument.fromJson(futureJson);
      final futureDb = _UncoveredSchemaDatabase(NativeDatabase.memory());
      addTearDown(futureDb.close);
      final futureStore = DriftBackupDataStore(futureDb);

      await expectLater(
        futureStore.restoreDocument(claimedFutureDocument),
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
    final archivedId = await createAccount(sourceFinance, 'Rekening Lama');
    final activeId = await createAccount(sourceFinance, 'Rekening Aktif');
    await sourceFinance.addEntry(
      income(archivedId, 100, note: 'Riwayat sebelum arsip'),
    );
    await sourceFinance.addEntry(
      EntryDraft(
        kind: EntryKind.transfer,
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
    expect(await targetDb.select(targetDb.ledgerEntries).get(), hasLength(2));
    final details = await targetFinance.getAccountDetails(archivedId);
    expect(details?.account.balance, 0);
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
    'database failure midway rolls back rows and sqlite sequences',
    () async {
      final sourceId = await createAccount(sourceFinance, 'Sumber backup');
      await sourceFinance.addEntry(
        income(sourceId, 25, note: 'Paksa kegagalan restore'),
      );
      final incoming = await sourceStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );

      final oldId = await createAccount(targetFinance, 'Data lama');
      await targetFinance.addEntry(income(oldId, 10, note: 'Harus tetap ada'));
      final before = await targetStore.exportDocument(
        createdAtUtc: createdAtUtc,
      );
      await targetDb.customStatement('''
      CREATE TRIGGER test_force_restore_failure
      BEFORE INSERT ON ledger_entries
      WHEN NEW.note = 'Paksa kegagalan restore'
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
