import 'package:drift/drift.dart';

import '../../domain/backup.dart';
import '../../domain/backup_repository.dart';
import '../../domain/budget.dart';
import '../../domain/finance.dart';
import '../database/app_database.dart';

// Deliberately independent from AppDatabase.schemaVersion. A database or
// backup-format change must first extend the DTO, export, restore, and decoder
// migration before these adapter coverage pins are updated.
const _encodedBackupVersion = 4;
const _encodedDatabaseSchemaVersion = 6;
const _encodedTableColumns = <String, Set<String>>{
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
  'budgets': {
    'id',
    'period_kind',
    'start_day',
    'end_day',
    'name',
    'normalized_name',
    'limit_amount',
    'created_at',
    'updated_at',
  },
  'budget_categories': {'budget_id', 'category_id'},
};

class DriftBackupDataStore implements BackupDataStore {
  DriftBackupDataStore(this._db);

  final AppDatabase _db;

  @override
  int get databaseSchemaVersion => _db.schemaVersion;

  @override
  Future<BackupDocument> exportDocument({
    required DateTime createdAtUtc,
  }) async {
    try {
      _ensureAdapterCoversCurrentDatabase();
      return await _db.transaction(() async {
        final accounts = await (_db.select(
          _db.accounts,
        )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
        final categories = await (_db.select(
          _db.categories,
        )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
        final ledgerEntries = await (_db.select(
          _db.ledgerEntries,
        )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
        final ledgerAllocations =
            await (_db.select(_db.ledgerAllocations)..orderBy([
                  (row) => OrderingTerm.asc(row.entryId),
                  (row) => OrderingTerm.asc(row.position),
                ]))
                .get();
        final budgets = await (_db.select(
          _db.budgets,
        )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
        final budgetCategories =
            await (_db.select(_db.budgetCategories)..orderBy([
                  (row) => OrderingTerm.asc(row.budgetId),
                  (row) => OrderingTerm.asc(row.categoryId),
                ]))
                .get();
        final ledgerIds = ledgerEntries.map((row) => row.id).toSet();
        if (ledgerAllocations.any(
          (allocation) => !ledgerIds.contains(allocation.entryId),
        )) {
          throw const BackupPersistenceException(
            'Allocation transaksi tidak mempunyai header yang valid.',
          );
        }
        final allocationsByEntry = <int, List<LedgerAllocationRow>>{};
        for (final allocation in ledgerAllocations) {
          allocationsByEntry
              .putIfAbsent(allocation.entryId, () => [])
              .add(allocation);
        }
        final budgetIds = budgets.map((row) => row.id).toSet();
        if (budgetCategories.any(
          (mapping) => !budgetIds.contains(mapping.budgetId),
        )) {
          throw const BackupPersistenceException(
            'Kategori anggaran tidak mempunyai anggaran yang valid.',
          );
        }
        final categoryIdsByBudget = <int, List<int>>{};
        for (final mapping in budgetCategories) {
          categoryIdsByBudget
              .putIfAbsent(mapping.budgetId, () => [])
              .add(mapping.categoryId);
        }
        final sequences = await _readSequences(
          maximumAccountId: _maximum(accounts.map((row) => row.id)),
          maximumCategoryId: _maximum(categories.map((row) => row.id)),
          maximumLedgerId: _maximum(ledgerEntries.map((row) => row.id)),
          maximumBudgetId: _maximum(budgets.map((row) => row.id)),
        );

        final document = BackupDocument(
          databaseSchemaVersion: _db.schemaVersion,
          createdAtUtc: createdAtUtc.toUtc(),
          sequences: sequences,
          accounts: accounts.map(_backupAccount),
          categories: categories.map(_backupCategory),
          ledgerEntries: ledgerEntries.map(
            (row) =>
                _backupLedgerEntry(row, allocationsByEntry[row.id] ?? const []),
          ),
          budgets: budgets.map(
            (row) =>
                _backupBudget(row, categoryIdsByBudget[row.id] ?? const []),
          ),
        );
        validateBackupDocument(document, requireSequenceHeadroom: false);
        return document;
      });
    } on BackupException {
      rethrow;
    } catch (error) {
      throw BackupPersistenceException(
        'Data belum dapat disiapkan untuk backup.',
        cause: error,
      );
    }
  }

  void _ensureAdapterCoversCurrentDatabase() {
    final actualTableColumns = <String, Set<String>>{
      for (final table in _db.allTables)
        table.actualTableName: {
          for (final column in table.$columns) column.$name,
        },
    };
    final coversPersistentSchema =
        actualTableColumns.length == _encodedTableColumns.length &&
        _encodedTableColumns.entries.every((expected) {
          final actualColumns = actualTableColumns[expected.key];
          return actualColumns != null &&
              actualColumns.length == expected.value.length &&
              actualColumns.containsAll(expected.value);
        });
    if (currentBackupVersion != _encodedBackupVersion ||
        _db.schemaVersion != _encodedDatabaseSchemaVersion ||
        !coversPersistentSchema) {
      throw const BackupPersistenceException(
        'Format backup belum mencakup struktur database aplikasi ini.',
      );
    }
  }

  @override
  Future<void> restoreDocument(BackupDocument document) async {
    _ensureAdapterCoversCurrentDatabase();
    validateBackupDocument(document);
    if (!canRestoreBackupDocumentToSchema(document, _db.schemaVersion)) {
      throw const BackupValidationException(
        'Versi database pada backup belum didukung oleh aplikasi ini.',
      );
    }

    try {
      await _db.transaction(() async {
        // Ledger delete/insert triggers reject archived accounts. Temporarily
        // activate accounts on both sides of the replacement, then restore the
        // archived flags only after every ledger row exists.
        await _db
            .update(_db.accounts)
            .write(const AccountsCompanion(isArchived: Value(false)));
        await _db.delete(_db.ledgerAllocations).go();
        await _db.delete(_db.ledgerEntries).go();
        await _db.delete(_db.budgetCategories).go();
        await _db.delete(_db.budgets).go();
        await (_db.delete(
          _db.categories,
        )..where((row) => row.parentId.isNotNull())).go();
        await (_db.delete(
          _db.categories,
        )..where((row) => row.parentId.isNull())).go();
        await _db.delete(_db.accounts).go();

        final accountRows = [
          for (final account in document.accounts)
            AccountRow(
              id: account.id,
              name: account.name,
              normalizedName: account.normalizedName,
              type: account.type.index,
              balanceGroup: account.balanceGroup.index,
              isArchived: false,
              createdAt: account.createdAtUtc,
            ),
        ];
        final categoryRoots = <CategoryRow>[];
        final categoryChildren = <CategoryRow>[];
        for (final category in document.categories) {
          final row = CategoryRow(
            id: category.id,
            parentId: category.parentId,
            kind: category.kind.index,
            name: category.name,
            normalizedName: category.normalizedName,
            iconKey: category.iconKey,
            isArchived: category.isArchived,
            sortOrder: category.sortOrder,
            systemKey: category.systemKey,
            createdAt: category.createdAtUtc,
            updatedAt: category.updatedAtUtc,
          );
          (category.parentId == null ? categoryRoots : categoryChildren).add(
            row,
          );
        }
        final ledgerRows = [
          for (final entry in document.ledgerEntries)
            LedgerRow(
              id: entry.id,
              kind: entry.kind.index,
              accountId: entry.accountId,
              destinationAccountId: entry.destinationAccountId,
              amount: entry.amount,
              note: entry.note,
              occurredDay: entry.occurredDay,
              createdAt: entry.createdAtUtc,
            ),
        ];
        final allocationRows = [
          for (final entry in document.ledgerEntries)
            for (final allocation in entry.allocations)
              LedgerAllocationRow(
                entryId: entry.id,
                position: allocation.position,
                categoryId: allocation.categoryId,
                amount: allocation.amount,
              ),
        ];
        final budgetRows = [
          for (final budget in document.budgets)
            BudgetRow(
              id: budget.id,
              periodKind: budget.periodKind.index,
              startDay: budget.startDay,
              endDay: budget.endDay,
              name: budget.name,
              normalizedName: budget.normalizedName,
              limitAmount: budget.limitAmount,
              createdAt: budget.createdAtUtc,
              updatedAt: budget.updatedAtUtc,
            ),
        ];
        final budgetCategoryRows = [
          for (final budget in document.budgets)
            for (final categoryId in budget.categoryIds)
              BudgetCategoryRow(budgetId: budget.id, categoryId: categoryId),
        ];

        await _db.batch((batch) {
          if (accountRows.isNotEmpty) {
            batch.insertAll(_db.accounts, accountRows);
          }
          if (categoryRoots.isNotEmpty) {
            batch.insertAll(_db.categories, categoryRoots);
          }
          if (categoryChildren.isNotEmpty) {
            batch.insertAll(_db.categories, categoryChildren);
          }
          if (budgetRows.isNotEmpty) {
            batch.insertAll(_db.budgets, budgetRows);
          }
          if (budgetCategoryRows.isNotEmpty) {
            batch.insertAll(_db.budgetCategories, budgetCategoryRows);
          }
          if (ledgerRows.isNotEmpty) {
            batch.insertAll(_db.ledgerEntries, ledgerRows);
          }
          if (allocationRows.isNotEmpty) {
            batch.insertAll(_db.ledgerAllocations, allocationRows);
          }
        });

        final archivedIds = document.accounts
            .where((account) => account.isArchived)
            .map((account) => account.id)
            .toList(growable: false);
        if (archivedIds.isNotEmpty) {
          await (_db.update(_db.accounts)
                ..where((row) => row.id.isIn(archivedIds)))
              .write(const AccountsCompanion(isArchived: Value(true)));
        }

        await _writeSequences(document.sequences);
        await _verifyRestore(document);
      });
    } on BackupException {
      rethrow;
    } catch (error) {
      throw BackupPersistenceException(
        'Data lama tetap tersimpan karena proses restore gagal.',
        cause: error,
      );
    }
  }

  Future<BackupSequences> _readSequences({
    required int maximumAccountId,
    required int maximumCategoryId,
    required int maximumLedgerId,
    required int maximumBudgetId,
  }) async {
    final rows = await _db.customSelect('''
      SELECT name, COALESCE(seq, 0) AS seq
      FROM sqlite_sequence
      WHERE name IN ('accounts', 'categories', 'ledger_entries', 'budgets')
    ''').get();
    final values = {
      for (final row in rows) row.read<String>('name'): row.read<int>('seq'),
    };
    return BackupSequences(
      accounts: _atLeast(values['accounts'] ?? 0, maximumAccountId),
      categories: _atLeast(values['categories'] ?? 0, maximumCategoryId),
      ledgerEntries: _atLeast(values['ledger_entries'] ?? 0, maximumLedgerId),
      budgets: _atLeast(values['budgets'] ?? 0, maximumBudgetId),
    );
  }

  Future<void> _writeSequences(BackupSequences sequences) async {
    await _db.customStatement('''
      DELETE FROM sqlite_sequence
      WHERE name IN ('accounts', 'categories', 'ledger_entries', 'budgets')
    ''');
    await _db.customStatement(
      '''
        INSERT INTO sqlite_sequence (name, seq) VALUES
          ('accounts', ?),
          ('categories', ?),
          ('ledger_entries', ?),
          ('budgets', ?)
      ''',
      [
        sequences.accounts,
        sequences.categories,
        sequences.ledgerEntries,
        sequences.budgets,
      ],
    );
  }

  Future<void> _verifyRestore(BackupDocument document) async {
    final foreignKeyErrors = await _db
        .customSelect('PRAGMA foreign_key_check')
        .get();
    if (foreignKeyErrors.isNotEmpty) {
      throw const BackupValidationException(
        'Relasi data hasil restore tidak valid.',
      );
    }

    final counts = await _db.customSelect('''
      SELECT
        (SELECT COUNT(*) FROM accounts) AS account_count,
        (SELECT COUNT(*) FROM categories) AS category_count,
        (SELECT COUNT(*) FROM ledger_entries) AS ledger_count,
        (SELECT COUNT(*) FROM ledger_allocations) AS allocation_count,
        (SELECT COUNT(*) FROM budgets) AS budget_count,
        (SELECT COUNT(*) FROM budget_categories) AS budget_category_count
    ''').getSingle();
    final expectedAllocationCount = document.ledgerEntries.fold<int>(
      0,
      (count, entry) => count + entry.allocations.length,
    );
    final expectedBudgetCategoryCount = document.budgets.fold<int>(
      0,
      (count, budget) => count + budget.categoryIds.length,
    );
    if (counts.read<int>('account_count') != document.accounts.length ||
        counts.read<int>('category_count') != document.categories.length ||
        counts.read<int>('ledger_count') != document.ledgerEntries.length ||
        counts.read<int>('allocation_count') != expectedAllocationCount ||
        counts.read<int>('budget_count') != document.budgets.length ||
        counts.read<int>('budget_category_count') !=
            expectedBudgetCategoryCount) {
      throw const BackupValidationException(
        'Jumlah data hasil restore tidak sesuai dengan backup.',
      );
    }

    try {
      await _db.verifyLedgerAllocationIntegrity();
    } on StateError catch (error) {
      throw BackupValidationException(
        'Rincian allocation hasil restore tidak valid.',
        cause: error,
      );
    }
    try {
      await _db.verifyBudgetIntegrity();
    } on StateError catch (error) {
      throw BackupValidationException(
        'Rincian anggaran hasil restore tidak valid.',
        cause: error,
      );
    }

    final invalidArchivedBalances = await _db.customSelect('''
      SELECT COUNT(*) AS amount
      FROM (
        SELECT account.id
        FROM accounts AS account
        LEFT JOIN ledger_entries AS entry
          ON entry.account_id = account.id
          OR entry.destination_account_id = account.id
        WHERE account.is_archived = 1
        GROUP BY account.id
        HAVING COALESCE(SUM(
          CASE
            WHEN entry.kind = 0 AND entry.account_id = account.id
              THEN entry.amount
            WHEN entry.kind = 1 AND entry.account_id = account.id
              THEN -entry.amount
            WHEN entry.kind = 2 AND entry.account_id = account.id
              THEN -entry.amount
            WHEN entry.kind = 2 AND entry.destination_account_id = account.id
              THEN entry.amount
            WHEN entry.kind = 3 AND entry.account_id = account.id
              THEN entry.amount
            ELSE 0
          END
        ), 0) <> 0
      )
    ''').getSingle();
    if (invalidArchivedBalances.read<int>('amount') != 0) {
      throw const BackupValidationException(
        'Saldo rekening arsip hasil restore tidak valid.',
      );
    }

    final restoredSequences = await _readSequences(
      maximumAccountId: _maximum(document.accounts.map((row) => row.id)),
      maximumCategoryId: _maximum(document.categories.map((row) => row.id)),
      maximumLedgerId: _maximum(document.ledgerEntries.map((row) => row.id)),
      maximumBudgetId: _maximum(document.budgets.map((row) => row.id)),
    );
    if (restoredSequences.accounts != document.sequences.accounts ||
        restoredSequences.categories != document.sequences.categories ||
        restoredSequences.ledgerEntries != document.sequences.ledgerEntries ||
        restoredSequences.budgets != document.sequences.budgets) {
      throw const BackupValidationException(
        'Urutan ID hasil restore tidak sesuai dengan backup.',
      );
    }
  }

  static BackupAccount _backupAccount(AccountRow row) => BackupAccount(
    id: row.id,
    name: row.name,
    normalizedName: row.normalizedName,
    type: AccountType.values[row.type],
    balanceGroup: AccountBalanceGroup.values[row.balanceGroup],
    isArchived: row.isArchived,
    createdAtUtc: row.createdAt.toUtc(),
  );

  static BackupCategory _backupCategory(CategoryRow row) => BackupCategory(
    id: row.id,
    parentId: row.parentId,
    kind: CategoryKind.values[row.kind],
    name: row.name,
    normalizedName: row.normalizedName,
    iconKey: row.iconKey,
    isArchived: row.isArchived,
    sortOrder: row.sortOrder,
    systemKey: row.systemKey,
    createdAtUtc: row.createdAt.toUtc(),
    updatedAtUtc: row.updatedAt.toUtc(),
  );

  static BackupBudget _backupBudget(BudgetRow row, Iterable<int> categoryIds) =>
      BackupBudget(
        id: row.id,
        periodKind: BudgetPeriodKind.values[row.periodKind],
        startDay: row.startDay,
        endDay: row.endDay,
        name: row.name,
        normalizedName: row.normalizedName,
        limitAmount: row.limitAmount,
        categoryIds: categoryIds,
        createdAtUtc: row.createdAt.toUtc(),
        updatedAtUtc: row.updatedAt.toUtc(),
      );

  static BackupLedgerEntry _backupLedgerEntry(
    LedgerRow row,
    Iterable<LedgerAllocationRow> allocations,
  ) => BackupLedgerEntry(
    id: row.id,
    kind: EntryKind.values[row.kind],
    accountId: row.accountId,
    destinationAccountId: row.destinationAccountId,
    amount: row.amount,
    allocations: allocations.map(
      (allocation) => BackupLedgerAllocation(
        position: allocation.position,
        categoryId: allocation.categoryId,
        amount: allocation.amount,
      ),
    ),
    note: row.note,
    occurredDay: row.occurredDay,
    createdAtUtc: row.createdAt.toUtc(),
  );

  static int _maximum(Iterable<int> values) {
    var result = 0;
    for (final value in values) {
      if (value > result) result = value;
    }
    return result;
  }

  static int _atLeast(int value, int minimum) =>
      value < minimum ? minimum : value;
}
