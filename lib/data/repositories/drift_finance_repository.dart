import 'package:drift/drift.dart';

import '../../domain/finance.dart';
import '../../domain/finance_repository.dart';
import '../database/app_database.dart';

class DriftFinanceRepository implements FinanceRepository {
  DriftFinanceRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<CategoryGroup>> watchCategoryTree(
    CategoryKind kind, {
    bool includeArchived = false,
  }) {
    final query = _db.select(_db.categories)
      ..where((category) {
        final sameKind = category.kind.equals(kind.index);
        return includeArchived
            ? sameKind
            : sameKind & category.isArchived.equals(false);
      })
      ..orderBy([
        (category) => OrderingTerm.asc(category.sortOrder),
        (category) => OrderingTerm.asc(category.normalizedName),
        (category) => OrderingTerm.asc(category.id),
      ]);
    return query.watch().map((rows) {
      final parents = rows.where((row) => row.parentId == null);
      return List.unmodifiable(
        parents.map(
          (parent) => CategoryGroup(
            parent: _toCategory(parent),
            children: rows
                .where((row) => row.parentId == parent.id)
                .map(_toCategory)
                .toList(),
          ),
        ),
      );
    });
  }

  @override
  Stream<List<FinanceAccount>> watchAccounts({bool includeArchived = false}) {
    return _db
        .customSelect(
          '''
          SELECT a.id, a.name, a.type, a.balance_group, a.is_archived,
                 COALESCE(b.balance, 0) AS balance
          FROM accounts AS a
          LEFT JOIN (
            SELECT account_id, SUM(delta) AS balance FROM (
              SELECT account_id,
                CASE WHEN kind IN (0, 3) THEN amount ELSE -amount END AS delta
              FROM ledger_entries
              UNION ALL
              SELECT destination_account_id AS account_id, amount AS delta
              FROM ledger_entries WHERE kind = 2
            ) GROUP BY account_id
          ) AS b ON b.account_id = a.id
          WHERE ? = 1 OR a.is_archived = 0
          ORDER BY a.normalized_name, a.id
          ''',
          variables: [Variable.withInt(includeArchived ? 1 : 0)],
          readsFrom: {_db.accounts, _db.ledgerEntries},
        )
        .watch()
        .map((rows) => List.unmodifiable(rows.map(_accountFromQueryRow)));
  }

  @override
  Stream<AccountDetails?> watchAccountDetails(int id) {
    if (id < 1) return Stream.value(null);
    return _db
        .customSelect(
          'SELECT COUNT(*) AS change_marker FROM accounts',
          readsFrom: {_db.accounts, _db.ledgerEntries},
        )
        .watchSingle()
        .asyncMap((_) => getAccountDetails(id));
  }

  @override
  Future<AccountDetails?> getAccountDetails(int id) {
    if (id < 1) return Future.value(null);
    return _db.transaction(() async {
      final row = await (_db.select(
        _db.accounts,
      )..where((account) => account.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      final balance = await _loadAccountBalance(id);
      final ledgerEntryCount = await _ledgerReferenceCount(id);
      return AccountDetails(
        account: _toAccount(row, balance),
        createdAt: row.createdAt,
        ledgerEntryCount: ledgerEntryCount,
      );
    });
  }

  @override
  Stream<FinanceEntry?> watchEntry(int id) {
    if (id < 1) return Stream.value(null);
    return _db
        .customSelect(
          '''SELECT COUNT(*) AS change_marker
             FROM ledger_entries WHERE id = ?''',
          variables: [Variable.withInt(id)],
          readsFrom: {_db.ledgerEntries, _db.ledgerAllocations, _db.categories},
        )
        .watchSingle()
        .asyncMap((_) => _loadEntry(id));
  }

  @override
  Stream<FinanceSnapshot> watchMonth(DateTime month, {int limit = 50}) {
    final normalizedMonth = _normalizeMonthForRead(month);
    return _db
        .customSelect(
          'SELECT COUNT(*) AS entry_count FROM ledger_entries',
          readsFrom: {
            _db.accounts,
            _db.categories,
            _db.ledgerEntries,
            _db.ledgerAllocations,
          },
        )
        .watch()
        .asyncMap((_) => loadMonth(normalizedMonth, limit: limit));
  }

  @override
  Stream<CalendarMonthSnapshot> watchCalendarMonth(DateTime month) {
    final normalizedMonth = _normalizeMonthForRead(month);
    final start = _dayKey(normalizedMonth);
    final end = _dayKey(
      DateTime(normalizedMonth.year, normalizedMonth.month + 1),
    );
    return _db
        .customSelect(
          '''SELECT occurred_day,
               COALESCE(SUM(CASE WHEN kind = 0 THEN amount ELSE 0 END), 0)
                 AS income,
               COALESCE(SUM(CASE WHEN kind = 1 THEN amount ELSE 0 END), 0)
                 AS expense,
               SUM(CASE WHEN kind = 2 THEN 1 ELSE 0 END) AS transfer_count,
               SUM(CASE WHEN kind = 3 THEN 1 ELSE 0 END) AS adjustment_count,
               COUNT(*) AS entry_count
             FROM ledger_entries
             WHERE occurred_day >= ? AND occurred_day < ?
             GROUP BY occurred_day
             ORDER BY occurred_day ASC''',
          variables: [Variable.withInt(start), Variable.withInt(end)],
          readsFrom: {_db.ledgerEntries},
        )
        .watch()
        .map(
          (rows) => CalendarMonthSnapshot(
            month: normalizedMonth,
            days: rows.map(_calendarDaySummaryFromQueryRow).toList(),
          ),
        );
  }

  @override
  Stream<List<FinanceEntry>> watchDay(DateTime day) {
    final normalizedDay = _normalizeDayForRead(day);
    final dayKey = _dayKey(normalizedDay);
    return _db
        .customSelect(
          '''SELECT COUNT(*) AS change_marker
             FROM ledger_entries WHERE occurred_day = ?''',
          variables: [Variable.withInt(dayKey)],
          readsFrom: {_db.ledgerEntries, _db.ledgerAllocations, _db.categories},
        )
        .watchSingle()
        .asyncMap((_) => _loadDayEntries(dayKey));
  }

  @override
  Future<FinanceSnapshot> loadMonth(DateTime month, {int limit = 50}) {
    if (limit < 1) {
      throw const FinanceValidationException(
        'Jumlah transaksi yang ditampilkan minimal 1.',
      );
    }
    final normalizedMonth = _normalizeMonthForRead(month);
    final start = _dayKey(normalizedMonth);
    final end = _dayKey(
      DateTime(normalizedMonth.year, normalizedMonth.month + 1),
    );

    // A read transaction keeps the balances, summary, and list consistent.
    return _db.transaction(() async {
      final accountRows = await _db.customSelect('''
        SELECT a.id, a.name, a.type, a.balance_group, a.is_archived,
               COALESCE(b.balance, 0) AS balance
        FROM accounts a
        LEFT JOIN (
          SELECT account_id, SUM(delta) AS balance FROM (
            SELECT account_id,
              CASE WHEN kind IN (0, 3) THEN amount ELSE -amount END AS delta
            FROM ledger_entries
            UNION ALL
            SELECT destination_account_id AS account_id, amount AS delta
            FROM ledger_entries WHERE kind = 2
          ) GROUP BY account_id
        ) b ON a.id = b.account_id
        ORDER BY a.normalized_name, a.id
      ''').get();
      final totals = await _db
          .customSelect(
            '''SELECT
              COALESCE(SUM(CASE WHEN kind = 0 THEN amount ELSE 0 END), 0) AS income,
              COALESCE(SUM(CASE WHEN kind = 1 THEN amount ELSE 0 END), 0) AS expense,
              COUNT(*) AS total_entries
              FROM ledger_entries WHERE occurred_day >= ? AND occurred_day < ?''',
            variables: [Variable.withInt(start), Variable.withInt(end)],
          )
          .getSingle();
      final entryQuery = _db.select(_db.ledgerEntries);
      entryQuery
        ..where(
          (entry) =>
              entry.occurredDay.isBiggerOrEqualValue(start) &
              entry.occurredDay.isSmallerThanValue(end),
        )
        ..orderBy([
          (entry) => OrderingTerm.desc(entry.occurredDay),
          (entry) => OrderingTerm.desc(entry.id),
        ])
        ..limit(limit);
      final rows = await entryQuery.get();
      final entries = await _entriesWithAllocations(rows);

      return FinanceSnapshot(
        accounts: accountRows
            .map(
              (row) => FinanceAccount(
                id: row.read<int>('id'),
                name: row.read<String>('name'),
                type: AccountType.values[row.read<int>('type')],
                balance: row.read<int>('balance'),
                balanceGroup:
                    AccountBalanceGroup.values[row.read<int>('balance_group')],
                isArchived: row.read<int>('is_archived') != 0,
              ),
            )
            .toList(),
        entries: entries,
        income: totals.read<int>('income'),
        expense: totals.read<int>('expense'),
        totalEntries: totals.read<int>('total_entries'),
      );
    });
  }

  @override
  Future<int> createAccount(AccountDraft draft) async {
    final name = _normalizeAccountName(draft.name);
    _validateAmount(draft.openingBalance, allowZero: true);
    _validateDate(draft.openedAt);
    final normalizedName = name.toLowerCase();

    return _db.transaction(() async {
      await _ensureUniqueAccountName(normalizedName: normalizedName);
      final now = DateTime.now();
      final accountId = await _db
          .into(_db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: name,
              normalizedName: normalizedName,
              type: draft.type.index,
              balanceGroup: Value(draft.balanceGroup.index),
              createdAt: now,
            ),
          );
      if (draft.openingBalance > 0) {
        await _db
            .into(_db.ledgerEntries)
            .insert(
              LedgerEntriesCompanion.insert(
                kind: EntryKind.adjustment.index,
                accountId: accountId,
                amount: draft.openingBalance,
                note: const Value('Saldo awal'),
                occurredDay: _dayKey(draft.openedAt),
                createdAt: now,
              ),
            );
      }
      return accountId;
    });
  }

  @override
  Future<void> updateAccount(int id, AccountUpdateDraft draft) async {
    _validateAccountId(id);
    final name = _normalizeAccountName(draft.name);
    final normalizedName = name.toLowerCase();
    await _db.transaction(() async {
      await _requireAccount(id);
      await _ensureUniqueAccountName(
        normalizedName: normalizedName,
        exceptId: id,
      );
      final affected =
          await (_db.update(
            _db.accounts,
          )..where((account) => account.id.equals(id))).write(
            AccountsCompanion(
              name: Value(name),
              normalizedName: Value(normalizedName),
              type: Value(draft.type.index),
              balanceGroup: Value(draft.balanceGroup.index),
            ),
          );
      if (affected != 1) _throwAccountNotFound();
    });
  }

  @override
  Future<void> setAccountArchived(int id, bool archived) async {
    _validateAccountId(id);
    await _db.transaction(() async {
      final account = await _requireAccount(id);
      if (account.isArchived == archived) return;
      if (archived) {
        final balance = await _loadAccountBalance(id);
        if (balance != 0) {
          throw const FinanceValidationException(
            'Saldo rekening harus Rp0 sebelum diarsipkan.',
          );
        }
        final activeCount = await _activeAccountCount();
        if (activeCount <= 1) {
          throw const FinanceValidationException(
            'Sisakan minimal satu rekening aktif.',
          );
        }
      }
      final affected =
          await (_db.update(_db.accounts)..where((row) => row.id.equals(id)))
              .write(AccountsCompanion(isArchived: Value(archived)));
      if (affected != 1) _throwAccountNotFound();
    });
  }

  @override
  Future<void> deleteAccount(int id) async {
    _validateAccountId(id);
    await _db.transaction(() async {
      await _requireAccount(id);
      if (await _ledgerReferenceCount(id) != 0) {
        throw const FinanceValidationException(
          'Rekening yang memiliki riwayat transaksi tidak dapat dihapus.',
        );
      }
      final affected = await (_db.delete(
        _db.accounts,
      )..where((account) => account.id.equals(id))).go();
      if (affected != 1) _throwAccountNotFound();
    });
  }

  @override
  Future<int> adjustAccountBalance(
    int id,
    AccountBalanceAdjustmentDraft draft,
  ) async {
    _validateAccountId(id);
    _validateTargetBalance(draft.targetBalance);
    _validateDate(draft.occurredAt);
    final trimmedNote = draft.note.trim();
    final note = trimmedNote.isEmpty ? 'Penyesuaian saldo' : trimmedNote;
    if (note.length > 500) {
      throw const FinanceValidationException('Catatan maksimal 500 karakter.');
    }

    return _db.transaction(() async {
      await _requireAccount(id, requireActive: true);
      final currentBalance = await _loadAccountBalance(id);
      final delta = draft.targetBalance - currentBalance;
      if (delta == 0) {
        throw const FinanceValidationException(
          'Saldo sudah sesuai, tidak ada penyesuaian.',
        );
      }
      if (delta.abs() > maxAmount) {
        throw const FinanceValidationException(
          'Selisih penyesuaian saldo terlalu besar.',
        );
      }
      return _db
          .into(_db.ledgerEntries)
          .insert(
            LedgerEntriesCompanion.insert(
              kind: EntryKind.adjustment.index,
              accountId: id,
              amount: delta,
              note: Value(note),
              occurredDay: _dayKey(draft.occurredAt),
              createdAt: DateTime.now(),
            ),
          );
    });
  }

  @override
  Future<int> addEntry(EntryDraft draft) async {
    final normalized = _validateAndNormalizeEntry(draft);

    return _db.transaction(() async {
      await _requireAccounts(normalized);
      await _requireUsableAllocations(normalized);
      // A transfer is one insert: it cannot leave a half-completed debit/credit.
      final entryId = await _db
          .into(_db.ledgerEntries)
          .insert(_insertCompanion(normalized, createdAt: DateTime.now()));
      await _writeAllocations(entryId, normalized.allocations);
      await _assertEntryAllocationIntegrity(entryId);
      return entryId;
    });
  }

  @override
  Future<void> updateEntry(int id, EntryDraft draft) async {
    _validateEntryId(id);
    final normalized = _validateAndNormalizeEntry(draft);

    await _db.transaction(() async {
      final existing = await _requireEntry(id);
      final existingAllocations = await _loadAllocationRows(id);
      await _requireEntryAccountsActive(existing);
      if (existing.kind == EntryKind.adjustment.index) {
        throw const FinanceValidationException(
          'Penyesuaian saldo tidak dapat diubah dari riwayat transaksi.',
        );
      }
      await _requireAccounts(normalized);
      await _requireUsableAllocations(
        normalized,
        existingCategoryIds: {
          for (final allocation in existingAllocations) allocation.categoryId,
        },
        existingKind: existing.kind,
      );
      await (_db.delete(
        _db.ledgerAllocations,
      )..where((allocation) => allocation.entryId.equals(id))).go();
      final affected =
          await (_db.update(
            _db.ledgerEntries,
          )..where((entry) => entry.id.equals(id))).write(
            LedgerEntriesCompanion(
              kind: Value(normalized.kind.index),
              accountId: Value(normalized.accountId),
              destinationAccountId: Value(normalized.destinationAccountId),
              amount: Value(normalized.amount),
              note: Value(normalized.note),
              occurredDay: Value(_dayKey(normalized.occurredAt)),
            ),
          );
      if (affected != 1) _throwEntryNotFound();
      await _writeAllocations(id, normalized.allocations);
      await _assertEntryAllocationIntegrity(id);
    });
  }

  @override
  Future<void> deleteEntry(int id) async {
    _validateEntryId(id);
    await _db.transaction(() async {
      final existing = await _requireEntry(id);
      await _requireEntryAccountsActive(existing);
      if (existing.kind == EntryKind.adjustment.index) {
        throw const FinanceValidationException(
          'Penyesuaian saldo tidak dapat dihapus dari riwayat transaksi.',
        );
      }
      final affected = await (_db.delete(
        _db.ledgerEntries,
      )..where((entry) => entry.id.equals(id))).go();
      if (affected != 1) _throwEntryNotFound();
    });
  }

  @override
  Future<int> createCategoryGroup(CategoryGroupDraft draft) async {
    final parent = _validateCategoryFields(
      name: draft.parentName,
      iconKey: draft.parentIconKey,
      sortOrder: draft.parentSortOrder,
    );
    final child = _validateCategoryFields(
      name: draft.firstChildName,
      iconKey: draft.firstChildIconKey,
      sortOrder: draft.firstChildSortOrder,
    );
    return _db.transaction(() async {
      await _ensureUniqueCategoryName(
        kind: draft.kind,
        parentId: null,
        normalizedName: parent.normalizedName,
      );
      final now = DateTime.now();
      final parentId = await _db
          .into(_db.categories)
          .insert(
            CategoriesCompanion.insert(
              kind: draft.kind.index,
              name: parent.name,
              normalizedName: parent.normalizedName,
              iconKey: parent.iconKey,
              sortOrder: Value(parent.sortOrder),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _db
          .into(_db.categories)
          .insert(
            CategoriesCompanion.insert(
              parentId: Value(parentId),
              kind: draft.kind.index,
              name: child.name,
              normalizedName: child.normalizedName,
              iconKey: child.iconKey,
              sortOrder: Value(child.sortOrder),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return parentId;
    });
  }

  @override
  Future<int> createSubcategory(CategoryDraft draft) async {
    final parentId = draft.parentId;
    if (parentId == null) {
      throw const FinanceValidationException('Pilih kelompok kategori.');
    }
    final values = _validateCategoryDraft(draft);
    return _db.transaction(() async {
      final parent = await _requireCategory(parentId);
      if (parent.parentId != null) {
        throw const FinanceValidationException(
          'Subkategori hanya dapat dibuat di bawah kelompok utama.',
        );
      }
      if (parent.isArchived) {
        throw const FinanceValidationException(
          'Aktifkan kelompok kategori sebelum menambah subkategori.',
        );
      }
      final kind = CategoryKind.values[parent.kind];
      await _ensureUniqueCategoryName(
        kind: kind,
        parentId: parentId,
        normalizedName: values.normalizedName,
      );
      final now = DateTime.now();
      return _db
          .into(_db.categories)
          .insert(
            CategoriesCompanion.insert(
              parentId: Value(parentId),
              kind: parent.kind,
              name: values.name,
              normalizedName: values.normalizedName,
              iconKey: values.iconKey,
              sortOrder: Value(values.sortOrder),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
  }

  @override
  Future<void> updateCategory(int categoryId, CategoryDraft draft) async {
    _validateCategoryId(categoryId);
    final values = _validateCategoryDraft(draft);
    await _db.transaction(() async {
      final existing = await _requireCategory(categoryId);
      if (existing.parentId != draft.parentId) {
        throw const FinanceValidationException(
          'Kelompok kategori tidak dapat dipindahkan.',
        );
      }
      await _ensureUniqueCategoryName(
        kind: CategoryKind.values[existing.kind],
        parentId: existing.parentId,
        normalizedName: values.normalizedName,
        exceptId: categoryId,
      );
      await (_db.update(
        _db.categories,
      )..where((category) => category.id.equals(categoryId))).write(
        CategoriesCompanion(
          name: Value(values.name),
          normalizedName: Value(values.normalizedName),
          iconKey: Value(values.iconKey),
          sortOrder: Value(values.sortOrder),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> setCategoryArchived(int categoryId, bool archived) async {
    _validateCategoryId(categoryId);
    await _db.transaction(() async {
      final category = await _requireCategory(categoryId);
      if (category.isArchived == archived) return;
      if (archived) {
        final effective = await _effectiveLeafCount(category.kind);
        final removed = await _effectiveLeavesRemoved(category);
        if (effective - removed < 1) {
          throw const FinanceValidationException(
            'Sisakan minimal satu subkategori aktif untuk jenis transaksi ini.',
          );
        }
      } else if (category.parentId == null) {
        final activeChildren =
            await (_db.select(_db.categories)..where(
                  (child) =>
                      child.parentId.equals(category.id) &
                      child.isArchived.equals(false),
                ))
                .get();
        if (activeChildren.isEmpty) {
          throw const FinanceValidationException(
            'Aktifkan minimal satu subkategori terlebih dahulu.',
          );
        }
      }
      await (_db.update(
        _db.categories,
      )..where((row) => row.id.equals(categoryId))).write(
        CategoriesCompanion(
          isArchived: Value(archived),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  static _NormalizedEntryDraft _validateAndNormalizeEntry(EntryDraft draft) {
    if (draft.kind == EntryKind.adjustment) {
      throw const FinanceValidationException(
        'Penyesuaian saldo hanya dibuat melalui pengelolaan rekening.',
      );
    }
    _validateDate(draft.occurredAt);
    final note = draft.note.trim();
    if (note.length > 500) {
      throw const FinanceValidationException('Catatan maksimal 500 karakter.');
    }

    if (draft.kind == EntryKind.transfer) {
      if (draft.destinationAccountId == null ||
          draft.destinationAccountId == draft.accountId) {
        throw const FinanceValidationException(
          'Transfer membutuhkan dua rekening yang berbeda.',
        );
      }
      if (draft.allocations.isNotEmpty) {
        throw const FinanceValidationException(
          'Transfer tidak memiliki alokasi kategori.',
        );
      }
      final amount = draft.transferAmount;
      if (amount == null) {
        throw const FinanceValidationException('Masukkan nominal transfer.');
      }
      _validateAmount(amount);
      return _NormalizedEntryDraft(
        kind: draft.kind,
        accountId: draft.accountId,
        destinationAccountId: draft.destinationAccountId,
        amount: amount,
        allocations: const [],
        note: note,
        occurredAt: draft.occurredAt,
      );
    }

    if (draft.destinationAccountId != null || draft.transferAmount != null) {
      throw const FinanceValidationException(
        'Rekening tujuan dan nominal transfer hanya berlaku untuk transfer.',
      );
    }
    final allocations = draft.allocations;
    if (allocations.isEmpty || allocations.length > maxEntryAllocations) {
      throw const FinanceValidationException(
        'Pemasukan atau pengeluaran harus memiliki 1 sampai 50 alokasi.',
      );
    }
    final categoryIds = <int>{};
    var total = 0;
    for (final allocation in allocations) {
      _validateCategoryId(allocation.categoryId);
      _validateAmount(allocation.amount);
      if (!categoryIds.add(allocation.categoryId)) {
        throw const FinanceValidationException(
          'Satu subkategori hanya boleh dipakai sekali dalam satu transaksi.',
        );
      }
      if (total > maxAmount - allocation.amount) {
        throw const FinanceValidationException(
          'Total transaksi melebihi Rp999.999.999.999.',
        );
      }
      total += allocation.amount;
    }

    return _NormalizedEntryDraft(
      kind: draft.kind,
      accountId: draft.accountId,
      destinationAccountId: null,
      amount: total,
      allocations: allocations,
      note: note,
      occurredAt: draft.occurredAt,
    );
  }

  Future<void> _requireAccounts(_NormalizedEntryDraft draft) async {
    await _requireAccount(draft.accountId, requireActive: true);
    if (draft.destinationAccountId != null) {
      await _requireAccount(draft.destinationAccountId!, requireActive: true);
    }
  }

  Future<void> _requireEntryAccountsActive(LedgerRow entry) async {
    await _requireAccount(entry.accountId, requireActive: true);
    if (entry.destinationAccountId != null) {
      await _requireAccount(entry.destinationAccountId!, requireActive: true);
    }
  }

  Future<void> _requireUsableAllocations(
    _NormalizedEntryDraft draft, {
    Set<int> existingCategoryIds = const {},
    int? existingKind,
  }) async {
    if (draft.allocations.isEmpty) return;
    final categoryIds = draft.allocations
        .map((allocation) => allocation.categoryId)
        .toSet();
    final parent = _db.alias(_db.categories, 'allocation_parent_category');
    final query = _db.select(_db.categories).join([
      leftOuterJoin(parent, parent.id.equalsExp(_db.categories.parentId)),
    ])..where(_db.categories.id.isIn(categoryIds));
    final rows = await query.get();
    if (rows.length != categoryIds.length) {
      throw const FinanceValidationException('Kategori tidak ditemukan.');
    }
    for (final row in rows) {
      final category = row.readTable(_db.categories);
      final parentCategory = row.readTableOrNull(parent);
      if (category.parentId == null ||
          parentCategory == null ||
          parentCategory.parentId != null ||
          category.kind != draft.kind.index ||
          parentCategory.kind != draft.kind.index) {
        throw const FinanceValidationException(
          'Subkategori tidak sesuai dengan jenis transaksi.',
        );
      }
      final unchangedArchivedCategory =
          existingKind == draft.kind.index &&
          existingCategoryIds.contains(category.id);
      if ((category.isArchived || parentCategory.isArchived) &&
          !unchangedArchivedCategory) {
        throw const FinanceValidationException(
          'Subkategori telah diarsipkan. Pilih subkategori aktif.',
        );
      }
    }
  }

  Future<LedgerRow> _requireEntry(int id) async {
    final entry = await (_db.select(
      _db.ledgerEntries,
    )..where((entry) => entry.id.equals(id))).getSingleOrNull();
    if (entry == null) _throwEntryNotFound();
    return entry;
  }

  Future<FinanceEntry?> _loadEntry(int id) {
    return _db.transaction(() async {
      final row = await (_db.select(
        _db.ledgerEntries,
      )..where((entry) => entry.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return (await _entriesWithAllocations([row])).single;
    });
  }

  Future<List<FinanceEntry>> _loadDayEntries(int dayKey) {
    return _db.transaction(() async {
      final query = _db.select(_db.ledgerEntries)
        ..where((entry) => entry.occurredDay.equals(dayKey))
        ..orderBy([
          (entry) => OrderingTerm.desc(entry.createdAt),
          (entry) => OrderingTerm.desc(entry.id),
        ]);
      return _entriesWithAllocations(await query.get());
    });
  }

  Future<List<FinanceEntry>> _entriesWithAllocations(
    Iterable<LedgerRow> rows,
  ) async {
    final headers = List<LedgerRow>.of(rows);
    if (headers.isEmpty) return const [];
    final allocationsByEntry = await _loadAllocationsForEntries(
      headers.map((row) => row.id),
    );
    return List.unmodifiable(
      headers.map(
        (row) =>
            _toEntry(row, allocations: allocationsByEntry[row.id] ?? const []),
      ),
    );
  }

  Future<Map<int, List<FinanceEntryAllocation>>> _loadAllocationsForEntries(
    Iterable<int> entryIds,
  ) async {
    final ids = entryIds.toSet();
    if (ids.isEmpty) return const {};
    final parent = _db.alias(_db.categories, 'allocation_parent_category');
    final query = _db.select(_db.ledgerAllocations).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.ledgerAllocations.categoryId),
      ),
      leftOuterJoin(parent, parent.id.equalsExp(_db.categories.parentId)),
    ]);
    query
      ..where(_db.ledgerAllocations.entryId.isIn(ids))
      ..orderBy([
        OrderingTerm.asc(_db.ledgerAllocations.entryId),
        OrderingTerm.asc(_db.ledgerAllocations.position),
      ]);
    final grouped = <int, List<FinanceEntryAllocation>>{};
    for (final result in await query.get()) {
      final allocation = result.readTable(_db.ledgerAllocations);
      final category = result.readTableOrNull(_db.categories);
      final parentCategory = result.readTableOrNull(parent);
      if (category == null || parentCategory == null) {
        throw StateError('Relasi kategori alokasi transaksi tidak valid.');
      }
      grouped
          .putIfAbsent(allocation.entryId, () => [])
          .add(
            FinanceEntryAllocation(
              position: allocation.position,
              categoryId: allocation.categoryId,
              amount: allocation.amount,
              categoryName: category.name,
              parentCategoryName: parentCategory.name,
              categoryIconKey: category.iconKey,
              categoryArchived:
                  category.isArchived || parentCategory.isArchived,
            ),
          );
    }
    return {
      for (final entry in grouped.entries)
        entry.key: List.unmodifiable(entry.value),
    };
  }

  Future<List<LedgerAllocationRow>> _loadAllocationRows(int entryId) {
    final query = _db.select(_db.ledgerAllocations)
      ..where((allocation) => allocation.entryId.equals(entryId))
      ..orderBy([(allocation) => OrderingTerm.asc(allocation.position)]);
    return query.get();
  }

  Future<void> _writeAllocations(
    int entryId,
    List<EntryAllocationDraft> allocations,
  ) async {
    if (allocations.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAll(_db.ledgerAllocations, [
        for (var position = 0; position < allocations.length; position++)
          LedgerAllocationsCompanion.insert(
            entryId: entryId,
            position: position,
            categoryId: allocations[position].categoryId,
            amount: allocations[position].amount,
          ),
      ]);
    });
  }

  Future<void> _assertEntryAllocationIntegrity(int entryId) async {
    final result = await _db
        .customSelect(
          '''SELECT l.kind AS kind,
                    l.amount AS header_amount,
                    COUNT(a.entry_id) AS allocation_count,
                    COALESCE(SUM(a.amount), 0) AS allocation_total,
                    COALESCE(MIN(a.position), -1) AS min_position,
                    COALESCE(MAX(a.position), -1) AS max_position,
                    COUNT(DISTINCT a.category_id) AS category_count,
                    COALESCE(SUM(CASE
                      WHEN a.entry_id IS NOT NULL AND
                        (c.id IS NULL OR c.parent_id IS NULL OR c.kind <> l.kind OR
                         p.id IS NULL OR p.parent_id IS NOT NULL OR p.kind <> l.kind)
                      THEN 1 ELSE 0 END), 0) AS invalid_category_count,
                    COALESCE(SUM(CASE
                      WHEN a.entry_id IS NOT NULL AND
                        (a.amount < 1 OR a.amount > ?)
                      THEN 1 ELSE 0 END), 0) AS invalid_amount_count
             FROM ledger_entries AS l
             LEFT JOIN ledger_allocations AS a ON a.entry_id = l.id
             LEFT JOIN categories AS c ON c.id = a.category_id
             LEFT JOIN categories AS p ON p.id = c.parent_id
             WHERE l.id = ?
             GROUP BY l.id, l.kind, l.amount''',
          variables: [Variable.withInt(maxAmount), Variable.withInt(entryId)],
        )
        .getSingleOrNull();
    if (result == null) _throwEntryNotFound();
    final kind = result.read<int>('kind');
    final amount = result.read<int>('header_amount');
    final allocationCount = result.read<int>('allocation_count');
    final allocationTotal = result.read<int>('allocation_total');
    final minPosition = result.read<int>('min_position');
    final maxPosition = result.read<int>('max_position');
    final categoryCount = result.read<int>('category_count');
    final invalidCategoryCount = result.read<int>('invalid_category_count');
    final invalidAmountCount = result.read<int>('invalid_amount_count');
    final categorized =
        kind == EntryKind.income.index || kind == EntryKind.expense.index;
    final valid = categorized
        ? allocationCount >= 1 &&
              allocationCount <= maxEntryAllocations &&
              allocationTotal == amount &&
              minPosition == 0 &&
              maxPosition == allocationCount - 1 &&
              categoryCount == allocationCount &&
              invalidCategoryCount == 0 &&
              invalidAmountCount == 0
        : allocationCount == 0;
    if (!valid) {
      throw StateError('Invariant alokasi transaksi tidak valid.');
    }
  }

  Future<CategoryRow> _requireCategory(int id) async {
    final category = await (_db.select(
      _db.categories,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (category == null) {
      throw const FinanceValidationException('Kategori tidak ditemukan.');
    }
    return category;
  }

  Future<int> _effectiveLeafCount(int kind) async {
    final result = await _db
        .customSelect(
          '''SELECT COUNT(*) AS amount
         FROM categories AS child
         JOIN categories AS parent ON parent.id = child.parent_id
         WHERE child.kind = ? AND child.is_archived = 0
           AND parent.is_archived = 0''',
          variables: [Variable.withInt(kind)],
          readsFrom: {_db.categories},
        )
        .getSingle();
    return result.read<int>('amount');
  }

  Future<int> _effectiveLeavesRemoved(CategoryRow category) async {
    if (category.isArchived) return 0;
    if (category.parentId != null) {
      final parent = await _requireCategory(category.parentId!);
      return parent.isArchived ? 0 : 1;
    }
    final result = await _db
        .customSelect(
          '''SELECT COUNT(*) AS amount FROM categories
         WHERE parent_id = ? AND is_archived = 0''',
          variables: [Variable.withInt(category.id)],
          readsFrom: {_db.categories},
        )
        .getSingle();
    return result.read<int>('amount');
  }

  Future<void> _ensureUniqueCategoryName({
    required CategoryKind kind,
    required int? parentId,
    required String normalizedName,
    int? exceptId,
  }) async {
    final query = _db.select(_db.categories)
      ..where((category) {
        Expression<bool> condition =
            category.kind.equals(kind.index) &
            category.normalizedName.equals(normalizedName) &
            (parentId == null
                ? category.parentId.isNull()
                : category.parentId.equals(parentId));
        if (exceptId != null) {
          condition = condition & category.id.equals(exceptId).not();
        }
        return condition;
      });
    if (await query.getSingleOrNull() != null) {
      throw const FinanceValidationException(
        'Nama kategori sudah digunakan pada kelompok ini.',
      );
    }
  }

  static ({String name, String normalizedName, String iconKey, int sortOrder})
  _validateCategoryDraft(CategoryDraft draft) => _validateCategoryFields(
    name: draft.name,
    iconKey: draft.iconKey,
    sortOrder: draft.sortOrder,
  );

  static ({String name, String normalizedName, String iconKey, int sortOrder})
  _validateCategoryFields({
    required String name,
    required String iconKey,
    required int sortOrder,
  }) {
    final cleanedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanedName.isEmpty || cleanedName.length > 80) {
      throw const FinanceValidationException(
        'Nama kategori wajib diisi dan maksimal 80 karakter.',
      );
    }
    if (!categoryIconKeys.contains(iconKey)) {
      throw const FinanceValidationException('Ikon kategori tidak valid.');
    }
    if (sortOrder < 0 || sortOrder > 1000000) {
      throw const FinanceValidationException('Urutan kategori tidak valid.');
    }
    return (
      name: cleanedName,
      normalizedName: cleanedName.toLowerCase(),
      iconKey: iconKey,
      sortOrder: sortOrder,
    );
  }

  static void _validateCategoryId(int id) {
    if (id < 1) {
      throw const FinanceValidationException('Kategori tidak ditemukan.');
    }
  }

  Future<AccountRow> _requireAccount(
    int id, {
    bool requireActive = false,
  }) async {
    final account = await (_db.select(
      _db.accounts,
    )..where((account) => account.id.equals(id))).getSingleOrNull();
    if (account == null) {
      _throwAccountNotFound();
    }
    if (requireActive && account.isArchived) {
      throw const FinanceValidationException(
        'Rekening telah diarsipkan. Aktifkan kembali rekening terlebih dahulu.',
      );
    }
    return account;
  }

  Future<void> _ensureUniqueAccountName({
    required String normalizedName,
    int? exceptId,
  }) async {
    final query = _db.select(_db.accounts)
      ..where((account) {
        Expression<bool> condition = account.normalizedName.equals(
          normalizedName,
        );
        if (exceptId != null) {
          condition = condition & account.id.equals(exceptId).not();
        }
        return condition;
      });
    if (await query.getSingleOrNull() != null) {
      throw const FinanceValidationException(
        'Nama rekening sudah digunakan. Pilih nama lain.',
      );
    }
  }

  Future<int> _loadAccountBalance(int id) async {
    final result = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(delta), 0) AS balance
          FROM (
            SELECT CASE WHEN kind IN (0, 3) THEN amount ELSE -amount END AS delta
            FROM ledger_entries WHERE account_id = ?
            UNION ALL
            SELECT amount AS delta FROM ledger_entries
            WHERE kind = 2 AND destination_account_id = ?
          )
          ''',
          variables: [Variable.withInt(id), Variable.withInt(id)],
        )
        .getSingle();
    return result.read<int>('balance');
  }

  Future<int> _ledgerReferenceCount(int id) async {
    final result = await _db
        .customSelect(
          '''
          SELECT COUNT(*) AS amount FROM ledger_entries
          WHERE account_id = ? OR destination_account_id = ?
          ''',
          variables: [Variable.withInt(id), Variable.withInt(id)],
        )
        .getSingle();
    return result.read<int>('amount');
  }

  Future<int> _activeAccountCount() async {
    final result = await _db
        .customSelect(
          'SELECT COUNT(*) AS amount FROM accounts WHERE is_archived = 0',
        )
        .getSingle();
    return result.read<int>('amount');
  }

  static String _normalizeAccountName(String value) {
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.length > 80) {
      throw const FinanceValidationException(
        'Nama rekening wajib diisi dan maksimal 80 karakter.',
      );
    }
    return name;
  }

  static void _validateTargetBalance(int balance) {
    if (balance < -maxAmount || balance > maxAmount) {
      throw const FinanceValidationException(
        'Target saldo harus antara -Rp999.999.999.999 dan '
        'Rp999.999.999.999.',
      );
    }
  }

  static void _validateAccountId(int id) {
    if (id < 1) _throwAccountNotFound();
  }

  static void _validateAmount(int amount, {bool allowZero = false}) {
    if (amount < (allowZero ? 0 : 1) || amount > maxAmount) {
      throw FinanceValidationException(
        allowZero
            ? 'Saldo awal harus antara Rp0 dan Rp999.999.999.999.'
            : 'Nominal harus antara Rp1 dan Rp999.999.999.999.',
      );
    }
  }

  static void _validateDate(DateTime date) {
    final day = _dayKey(date);
    if (day < 20000101 || day > _dayKey(DateTime.now())) {
      throw const FinanceValidationException(
        'Tanggal harus antara 1 Januari 2000 dan hari ini.',
      );
    }
  }

  static DateTime _normalizeDayForRead(DateTime date) {
    _validateDate(date);
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime _normalizeMonthForRead(DateTime month) {
    final normalized = DateTime(month.year, month.month);
    final monthKey = normalized.year * 100 + normalized.month;
    final current = DateTime.now();
    final currentMonthKey = current.year * 100 + current.month;
    if (monthKey < 200001 || monthKey > currentMonthKey) {
      throw const FinanceValidationException(
        'Bulan harus antara Januari 2000 dan bulan ini.',
      );
    }
    return normalized;
  }

  static void _validateEntryId(int id) {
    if (id < 1) _throwEntryNotFound();
  }

  static Never _throwEntryNotFound() =>
      throw const FinanceValidationException('Transaksi tidak ditemukan.');

  static Never _throwAccountNotFound() =>
      throw const FinanceValidationException('Rekening tidak ditemukan.');

  static LedgerEntriesCompanion _insertCompanion(
    _NormalizedEntryDraft draft, {
    required DateTime createdAt,
  }) => LedgerEntriesCompanion.insert(
    kind: draft.kind.index,
    accountId: draft.accountId,
    destinationAccountId: Value(draft.destinationAccountId),
    amount: draft.amount,
    note: Value(draft.note),
    occurredDay: _dayKey(draft.occurredAt),
    createdAt: createdAt,
  );

  static int _dayKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static FinanceAccount _accountFromQueryRow(QueryRow row) => FinanceAccount(
    id: row.read<int>('id'),
    name: row.read<String>('name'),
    type: AccountType.values[row.read<int>('type')],
    balance: row.read<int>('balance'),
    balanceGroup: AccountBalanceGroup.values[row.read<int>('balance_group')],
    isArchived: row.read<int>('is_archived') != 0,
  );

  static CalendarDaySummary _calendarDaySummaryFromQueryRow(QueryRow row) {
    final dayKey = row.read<int>('occurred_day');
    return CalendarDaySummary(
      day: DateTime(dayKey ~/ 10000, dayKey ~/ 100 % 100, dayKey % 100),
      income: row.read<int>('income'),
      expense: row.read<int>('expense'),
      transferCount: row.read<int>('transfer_count'),
      adjustmentCount: row.read<int>('adjustment_count'),
      entryCount: row.read<int>('entry_count'),
    );
  }

  static FinanceAccount _toAccount(AccountRow row, int balance) =>
      FinanceAccount(
        id: row.id,
        name: row.name,
        type: AccountType.values[row.type],
        balance: balance,
        balanceGroup: AccountBalanceGroup.values[row.balanceGroup],
        isArchived: row.isArchived,
      );

  static FinanceCategory _toCategory(CategoryRow row) => FinanceCategory(
    id: row.id,
    parentId: row.parentId,
    kind: CategoryKind.values[row.kind],
    name: row.name,
    iconKey: row.iconKey,
    isArchived: row.isArchived,
    sortOrder: row.sortOrder,
    systemKey: row.systemKey,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static FinanceEntry _toEntry(
    LedgerRow row, {
    required List<FinanceEntryAllocation> allocations,
  }) {
    final kind = EntryKind.values[row.kind];
    final categorized = kind == EntryKind.income || kind == EntryKind.expense;
    if (categorized) {
      var total = 0;
      final categoryIds = <int>{};
      for (var position = 0; position < allocations.length; position++) {
        final allocation = allocations[position];
        if (allocation.position != position ||
            !categoryIds.add(allocation.categoryId)) {
          throw StateError('Urutan alokasi transaksi tidak valid.');
        }
        total += allocation.amount;
      }
      if (allocations.isEmpty ||
          allocations.length > maxEntryAllocations ||
          total != row.amount) {
        throw StateError('Total alokasi transaksi tidak valid.');
      }
    } else if (allocations.isNotEmpty) {
      throw StateError('Transfer atau penyesuaian memiliki alokasi.');
    }
    return FinanceEntry(
      id: row.id,
      kind: kind,
      accountId: row.accountId,
      destinationAccountId: row.destinationAccountId,
      amount: row.amount,
      allocations: allocations,
      note: row.note,
      occurredAt: DateTime(
        row.occurredDay ~/ 10000,
        row.occurredDay ~/ 100 % 100,
        row.occurredDay % 100,
      ),
      createdAt: row.createdAt,
    );
  }
}

class _NormalizedEntryDraft {
  _NormalizedEntryDraft({
    required this.kind,
    required this.accountId,
    required this.destinationAccountId,
    required this.amount,
    required Iterable<EntryAllocationDraft> allocations,
    required this.note,
    required this.occurredAt,
  }) : allocations = List.unmodifiable(allocations);

  final EntryKind kind;
  final int accountId;
  final int? destinationAccountId;
  final int amount;
  final List<EntryAllocationDraft> allocations;
  final String note;
  final DateTime occurredAt;
}
