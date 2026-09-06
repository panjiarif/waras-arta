import 'package:drift/drift.dart';

import '../../domain/finance.dart';
import '../../domain/finance_repository.dart';
import '../database/app_database.dart';

class DriftFinanceRepository implements FinanceRepository {
  DriftFinanceRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<FinanceEntry?> watchEntry(int id) {
    if (id < 1) return Stream.value(null);
    final query = _db.select(_db.ledgerEntries)
      ..where((entry) => entry.id.equals(id));
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _toEntry(row),
    );
  }

  @override
  Stream<FinanceSnapshot> watchMonth(DateTime month, {int limit = 50}) => _db
      .customSelect(
        'SELECT COUNT(*) AS entry_count FROM ledger_entries',
        readsFrom: {_db.accounts, _db.ledgerEntries},
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
        SELECT a.id, a.name, a.type, COALESCE(b.balance, 0) AS balance
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
      final rows =
          await (_db.select(_db.ledgerEntries)
                ..where(
                  (entry) =>
                      entry.occurredDay.isBiggerOrEqualValue(start) &
                      entry.occurredDay.isSmallerThanValue(end),
                )
                ..orderBy([
                  (entry) => OrderingTerm.desc(entry.occurredDay),
                  (entry) => OrderingTerm.desc(entry.id),
                ])
                ..limit(limit))
              .get();

      return FinanceSnapshot(
        accounts: accountRows
            .map(
              (row) => FinanceAccount(
                id: row.read<int>('id'),
                name: row.read<String>('name'),
                type: AccountType.values[row.read<int>('type')],
                balance: row.read<int>('balance'),
              ),
            )
            .toList(),
        entries: rows.map(_toEntry).toList(),
        income: totals.read<int>('income'),
        expense: totals.read<int>('expense'),
        totalEntries: totals.read<int>('total_entries'),
      );
    });
  }

  @override
  Future<int> createAccount(AccountDraft draft) async {
    final name = draft.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.length > 80) {
      throw const FinanceValidationException(
        'Nama rekening wajib diisi dan maksimal 80 karakter.',
      );
    }
    _validateAmount(draft.openingBalance, allowZero: true);
    _validateDate(draft.openedAt);
    final normalizedName = name.toLowerCase();

    return _db.transaction(() async {
      final existing =
          await (_db.select(_db.accounts)..where(
                (account) => account.normalizedName.equals(normalizedName),
              ))
              .getSingleOrNull();
      if (existing != null) {
        throw const FinanceValidationException(
          'Nama rekening sudah digunakan. Pilih nama lain.',
        );
      }
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
  Future<int> addEntry(EntryDraft draft) async {
    final normalized = _validateAndNormalizeEntry(draft);

    return _db.transaction(() async {
      await _requireAccounts(normalized);
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
      if (existing.kind == EntryKind.adjustment.index) {
        throw const FinanceValidationException(
          'Saldo awal tidak dapat diubah dari riwayat transaksi.',
        );
      }
      await _requireAccounts(normalized);
      final affected =
          await (_db.update(
            _db.ledgerEntries,
          )..where((entry) => entry.id.equals(id))).write(
            LedgerEntriesCompanion(
              kind: Value(normalized.kind.index),
              accountId: Value(normalized.accountId),
              destinationAccountId: Value(normalized.destinationAccountId),
              amount: Value(normalized.amount),
              category: Value(normalized.category),
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
      if (existing.kind == EntryKind.adjustment.index) {
        throw const FinanceValidationException(
          'Saldo awal tidak dapat dihapus dari riwayat transaksi.',
        );
      }
      final affected = await (_db.delete(
        _db.ledgerEntries,
      )..where((entry) => entry.id.equals(id))).go();
      if (affected != 1) _throwEntryNotFound();
    });
  }

  static EntryDraft _validateAndNormalizeEntry(EntryDraft draft) {
    if (draft.kind == EntryKind.adjustment) {
      throw const FinanceValidationException(
        'Saldo awal hanya dibuat saat menambahkan rekening.',
      );
    }
    _validateAmount(draft.amount);
    _validateDate(draft.occurredAt);
    final note = draft.note.trim();
    if (note.length > 500) {
      throw const FinanceValidationException('Catatan maksimal 500 karakter.');
    }
    final category = draft.category?.trim();
    if (draft.kind == EntryKind.transfer) {
      if (draft.destinationAccountId == null ||
          draft.destinationAccountId == draft.accountId) {
        throw const FinanceValidationException(
          'Transfer membutuhkan dua rekening yang berbeda.',
        );
      }
      if (category != null) {
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
      final categories = draft.kind == EntryKind.income
          ? incomeCategories
          : expenseCategories;
      if (!categories.contains(category)) {
        throw const FinanceValidationException('Pilih kategori yang sesuai.');
      }
    }

    return EntryDraft(
      kind: draft.kind,
      accountId: draft.accountId,
      destinationAccountId: draft.destinationAccountId,
      amount: draft.amount,
      category: category,
      note: note,
      occurredAt: draft.occurredAt,
    );
  }

  Future<void> _requireAccounts(EntryDraft draft) async {
    await _requireAccount(draft.accountId);
    if (draft.destinationAccountId != null) {
      await _requireAccount(draft.destinationAccountId!);
    }
  }

  Future<LedgerRow> _requireEntry(int id) async {
    final entry = await (_db.select(
      _db.ledgerEntries,
    )..where((entry) => entry.id.equals(id))).getSingleOrNull();
    if (entry == null) _throwEntryNotFound();
    return entry;
  }

  Future<void> _requireAccount(int id) async {
    final account = await (_db.select(
      _db.accounts,
    )..where((account) => account.id.equals(id))).getSingleOrNull();
    if (account == null) {
      throw const FinanceValidationException('Rekening tidak ditemukan.');
    }
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

  static LedgerEntriesCompanion _insertCompanion(
    EntryDraft draft, {
    required DateTime createdAt,
  }) => LedgerEntriesCompanion.insert(
    kind: draft.kind.index,
    accountId: draft.accountId,
    destinationAccountId: Value(draft.destinationAccountId),
    amount: draft.amount,
    category: Value(draft.category),
    note: Value(draft.note),
    occurredDay: _dayKey(draft.occurredAt),
    createdAt: createdAt,
  );

  static int _dayKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static FinanceEntry _toEntry(LedgerRow row) => FinanceEntry(
    id: row.id,
    kind: EntryKind.values[row.kind],
    accountId: row.accountId,
    destinationAccountId: row.destinationAccountId,
    amount: row.amount,
    category: row.category,
    note: row.note,
    occurredAt: DateTime(
      row.occurredDay ~/ 10000,
      row.occurredDay ~/ 100 % 100,
      row.occurredDay % 100,
    ),
    createdAt: row.createdAt,
  );
}
