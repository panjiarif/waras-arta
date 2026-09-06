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
          SELECT a.id, a.name, a.type, a.is_archived,
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
    final parent = _db.alias(_db.categories, 'parent_category');
    final query = _db.select(_db.ledgerEntries).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.ledgerEntries.categoryId),
      ),
      leftOuterJoin(parent, parent.id.equalsExp(_db.categories.parentId)),
    ])..where(_db.ledgerEntries.id.equals(id));
    return query.watchSingleOrNull().map(
      (row) => row == null
          ? null
          : _toEntry(
              row.readTable(_db.ledgerEntries),
              category: row.readTableOrNull(_db.categories),
              parent: row.readTableOrNull(parent),
            ),
    );
  }

  @override
  Stream<FinanceSnapshot> watchMonth(DateTime month, {int limit = 50}) => _db
      .customSelect(
        'SELECT COUNT(*) AS entry_count FROM ledger_entries',
        readsFrom: {_db.accounts, _db.categories, _db.ledgerEntries},
      )
      .watch()
      .asyncMap((_) => loadMonth(month, limit: limit));

  @override
  Future<FinanceSnapshot> loadMonth(DateTime month, {int limit = 50}) {
    if (limit < 1) {
      throw const FinanceValidationException(
        'Jumlah transaksi yang ditampilkan minimal 1.',
      );
    }
    final start = _dayKey(DateTime(month.year, month.month));
    final end = _dayKey(DateTime(month.year, month.month + 1));

    // A read transaction keeps the balances, summary, and list consistent.
    return _db.transaction(() async {
      final accountRows = await _db.customSelect('''
        SELECT a.id, a.name, a.type, a.is_archived,
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
      final parent = _db.alias(_db.categories, 'parent_category');
      final entryQuery = _db.select(_db.ledgerEntries).join([
        leftOuterJoin(
          _db.categories,
          _db.categories.id.equalsExp(_db.ledgerEntries.categoryId),
        ),
        leftOuterJoin(parent, parent.id.equalsExp(_db.categories.parentId)),
      ]);
      entryQuery
        ..where(
          _db.ledgerEntries.occurredDay.isBiggerOrEqualValue(start) &
              _db.ledgerEntries.occurredDay.isSmallerThanValue(end),
        )
        ..orderBy([
          OrderingTerm.desc(_db.ledgerEntries.occurredDay),
          OrderingTerm.desc(_db.ledgerEntries.id),
        ])
        ..limit(limit);
      final rows = await entryQuery.get();

      return FinanceSnapshot(
        accounts: accountRows
            .map(
              (row) => FinanceAccount(
                id: row.read<int>('id'),
                name: row.read<String>('name'),
                type: AccountType.values[row.read<int>('type')],
                balance: row.read<int>('balance'),
                isArchived: row.read<int>('is_archived') != 0,
              ),
            )
            .toList(),
        entries: rows
            .map(
              (row) => _toEntry(
                row.readTable(_db.ledgerEntries),
                category: row.readTableOrNull(_db.categories),
                parent: row.readTableOrNull(parent),
              ),
            )
            .toList(),
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
      await _requireUsableCategory(normalized);
      // A transfer is one insert: it cannot leave a half-completed debit/credit.
      return _db
          .into(_db.ledgerEntries)
          .insert(_insertCompanion(normalized, createdAt: DateTime.now()));
    });
  }

  @override
  Future<void> updateEntry(int id, EntryDraft draft) async {
    _validateEntryId(id);
    final normalized = _validateAndNormalizeEntry(draft);

    await _db.transaction(() async {
      final existing = await _requireEntry(id);
      await _requireEntryAccountsActive(existing);
      if (existing.kind == EntryKind.adjustment.index) {
        throw const FinanceValidationException(
          'Penyesuaian saldo tidak dapat diubah dari riwayat transaksi.',
        );
      }
      await _requireAccounts(normalized);
      await _requireUsableCategory(
        normalized,
        existingCategoryId: existing.categoryId,
        existingKind: existing.kind,
      );
      final affected =
          await (_db.update(
            _db.ledgerEntries,
          )..where((entry) => entry.id.equals(id))).write(
            LedgerEntriesCompanion(
              kind: Value(normalized.kind.index),
              accountId: Value(normalized.accountId),
              destinationAccountId: Value(normalized.destinationAccountId),
              amount: Value(normalized.amount),
              categoryId: Value(normalized.categoryId),
              note: Value(normalized.note),
              occurredDay: Value(_dayKey(normalized.occurredAt)),
            ),
          );
      if (affected != 1) _throwEntryNotFound();
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

  static EntryDraft _validateAndNormalizeEntry(EntryDraft draft) {
    if (draft.kind == EntryKind.adjustment) {
      throw const FinanceValidationException(
        'Penyesuaian saldo hanya dibuat melalui pengelolaan rekening.',
      );
    }
    _validateAmount(draft.amount);
    _validateDate(draft.occurredAt);
    final note = draft.note.trim();
    if (note.length > 500) {
      throw const FinanceValidationException('Catatan maksimal 500 karakter.');
    }
    final categoryId = draft.categoryId;
    if (draft.kind == EntryKind.transfer) {
      if (draft.destinationAccountId == null ||
          draft.destinationAccountId == draft.accountId) {
        throw const FinanceValidationException(
          'Transfer membutuhkan dua rekening yang berbeda.',
        );
      }
      if (categoryId != null) {
        throw const FinanceValidationException(
          'Transfer tidak memiliki kategori.',
        );
      }
    } else {
      if (draft.destinationAccountId != null) {
        throw const FinanceValidationException(
          'Rekening tujuan hanya berlaku untuk transfer.',
        );
      }
      if (categoryId == null) {
        throw const FinanceValidationException('Pilih subkategori.');
      }
    }

    return EntryDraft(
      kind: draft.kind,
      accountId: draft.accountId,
      destinationAccountId: draft.destinationAccountId,
      amount: draft.amount,
      categoryId: categoryId,
      note: note,
      occurredAt: draft.occurredAt,
    );
  }

  Future<void> _requireAccounts(EntryDraft draft) async {
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

  Future<void> _requireUsableCategory(
    EntryDraft draft, {
    int? existingCategoryId,
    int? existingKind,
  }) async {
    final categoryId = draft.categoryId;
    if (categoryId == null) return;
    final category = await _requireCategory(categoryId);
    if (category.parentId == null || category.kind != draft.kind.index) {
      throw const FinanceValidationException(
        'Subkategori tidak sesuai dengan jenis transaksi.',
      );
    }
    final parent = await _requireCategory(category.parentId!);
    final unchangedArchivedCategory =
        existingCategoryId == categoryId && existingKind == draft.kind.index;
    if ((category.isArchived || parent.isArchived) &&
        !unchangedArchivedCategory) {
      throw const FinanceValidationException(
        'Subkategori telah diarsipkan. Pilih subkategori aktif.',
      );
    }
  }

  Future<LedgerRow> _requireEntry(int id) async {
    final entry = await (_db.select(
      _db.ledgerEntries,
    )..where((entry) => entry.id.equals(id))).getSingleOrNull();
    if (entry == null) _throwEntryNotFound();
    return entry;
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

  static void _validateEntryId(int id) {
    if (id < 1) _throwEntryNotFound();
  }

  static Never _throwEntryNotFound() =>
      throw const FinanceValidationException('Transaksi tidak ditemukan.');

  static Never _throwAccountNotFound() =>
      throw const FinanceValidationException('Rekening tidak ditemukan.');

  static LedgerEntriesCompanion _insertCompanion(
    EntryDraft draft, {
    required DateTime createdAt,
  }) => LedgerEntriesCompanion.insert(
    kind: draft.kind.index,
    accountId: draft.accountId,
    destinationAccountId: Value(draft.destinationAccountId),
    amount: draft.amount,
    categoryId: Value(draft.categoryId),
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
    isArchived: row.read<int>('is_archived') != 0,
  );

  static FinanceAccount _toAccount(AccountRow row, int balance) =>
      FinanceAccount(
        id: row.id,
        name: row.name,
        type: AccountType.values[row.type],
        balance: balance,
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
    CategoryRow? category,
    CategoryRow? parent,
  }) => FinanceEntry(
    id: row.id,
    kind: EntryKind.values[row.kind],
    accountId: row.accountId,
    destinationAccountId: row.destinationAccountId,
    amount: row.amount,
    categoryId: row.categoryId,
    categoryName: category?.name,
    parentCategoryName: parent?.name,
    categoryIconKey: category?.iconKey,
    categoryArchived:
        category?.isArchived == true || parent?.isArchived == true,
    note: row.note,
    occurredAt: DateTime(
      row.occurredDay ~/ 10000,
      row.occurredDay ~/ 100 % 100,
      row.occurredDay % 100,
    ),
    createdAt: row.createdAt,
  );
}
