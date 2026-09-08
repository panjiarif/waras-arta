import 'package:drift/drift.dart';

import '../../domain/budget.dart';
import '../../domain/budget_repository.dart';
import '../../domain/finance.dart';
import '../database/app_database.dart';

class DriftBudgetRepository implements BudgetRepository {
  DriftBudgetRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Stream<BudgetListSnapshot> watchBudgets(BudgetListFilter filter) {
    _validateReferenceDay(filter.referenceDay);
    return _db
        .customSelect(
          'SELECT COUNT(*) AS change_marker FROM budgets',
          readsFrom: {
            _db.budgets,
            _db.budgetCategories,
            _db.categories,
            _db.ledgerEntries,
            _db.ledgerAllocations,
          },
        )
        .watchSingle()
        .asyncMap((_) => loadBudgets(filter));
  }

  @override
  Future<BudgetListSnapshot> loadBudgets(BudgetListFilter filter) async {
    _validateReferenceDay(filter.referenceDay);
    return _db.transaction(() async {
      final query = _db.select(_db.budgets)
        ..where((budget) {
          final Expression<bool> temporalCondition =
              switch (filter.temporalStatus) {
                BudgetTemporalStatus.active =>
                  budget.startDay.isSmallerOrEqualValue(filter.referenceDay) &
                      budget.endDay.isBiggerOrEqualValue(filter.referenceDay),
                BudgetTemporalStatus.upcoming =>
                  budget.startDay.isBiggerThanValue(filter.referenceDay),
                BudgetTemporalStatus.history =>
                  budget.endDay.isSmallerThanValue(filter.referenceDay),
              };
          final kind = filter.periodKind;
          return kind == null
              ? temporalCondition
              : temporalCondition & budget.periodKind.equals(kind.index);
        });
      final rows = await query.get();
      if (rows.isEmpty) {
        return BudgetListSnapshot(items: const [], groups: const []);
      }

      final budgetIds = rows.map((row) => row.id).toSet();
      final categoriesByBudget = await _loadCategoriesForBudgets(budgetIds);
      final spentByBudget = await _loadSpentForBudgets(budgetIds);
      final items = <BudgetProgress>[];
      for (final row in rows) {
        final categories = categoriesByBudget[row.id];
        if (categories == null || categories.isEmpty) {
          throw StateError('Anggaran tidak memiliki subkategori.');
        }
        items.add(
          BudgetProgress(
            budget: _toBudget(row),
            categories: categories,
            spentAmount: spentByBudget[row.id] ?? 0,
          ),
        );
      }
      return _sortSnapshot(items, filter.temporalStatus);
    });
  }

  @override
  Stream<BudgetDetails?> watchBudget(int id) {
    if (id < 1) return Stream.value(null);
    return _db
        .customSelect(
          'SELECT COUNT(*) AS change_marker FROM budgets',
          readsFrom: {_db.budgets, _db.budgetCategories, _db.categories},
        )
        .watchSingle()
        .asyncMap((_) => getBudget(id));
  }

  @override
  Future<BudgetDetails?> getBudget(int id) {
    if (id < 1) return Future.value(null);
    return _db.transaction(() async {
      final row = await (_db.select(
        _db.budgets,
      )..where((budget) => budget.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      final categories = await _loadCategoriesForBudgets({id});
      final selected = categories[id];
      if (selected == null || selected.isEmpty) {
        throw StateError('Anggaran tidak memiliki subkategori.');
      }
      return BudgetDetails(budget: _toBudget(row), categories: selected);
    });
  }

  @override
  Stream<Map<int, List<BudgetConflict>>> watchCategoryConflicts(
    BudgetPeriod period, {
    int? excludingBudgetId,
  }) {
    if (excludingBudgetId != null) _validateBudgetId(excludingBudgetId);
    return _conflictQuery(
      period,
      excludingBudgetId: excludingBudgetId,
    ).watch().map(_conflictsFromRows);
  }

  @override
  Future<int> createBudget(BudgetDraft draft) async {
    final normalized = _normalizeDraft(
      period: draft.period,
      name: draft.name,
      limitAmount: draft.limitAmount,
      categoryIds: draft.categoryIds,
    );
    return _db.transaction(() async {
      await _requireUsableCategories(normalized.categoryIds);
      await _ensureUniqueName(
        period: normalized.period,
        normalizedName: normalized.normalizedName,
      );
      await _ensureNoConflicts(normalized.period, normalized.categoryIds);

      final now = _clock().toUtc();
      final id = await _db
          .into(_db.budgets)
          .insert(
            BudgetsCompanion.insert(
              periodKind: normalized.period.kind.index,
              startDay: normalized.period.startDay,
              endDay: normalized.period.endDay,
              name: normalized.name,
              normalizedName: normalized.normalizedName,
              limitAmount: normalized.limitAmount,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _insertMappings(id, normalized.categoryIds);
      await _assertHasCategory(id);
      return id;
    });
  }

  @override
  Future<void> updateBudget(int id, BudgetUpdateDraft draft) async {
    _validateBudgetId(id);
    final name = canonicalizeBudgetName(draft.name);
    _validateLimit(draft.limitAmount);
    final categoryIds = Set<int>.of(draft.categoryIds);
    _validateCategoryIds(categoryIds);

    await _db.transaction(() async {
      final existing = await _requireBudget(id);
      final existingCategoryIds = await _loadCategoryIds(id);
      await _requireUsableCategories(
        categoryIds,
        existingCategoryIds: existingCategoryIds,
      );
      final period = _periodFromRow(existing);
      final normalizedName = name.toLowerCase();
      await _ensureUniqueName(
        period: period,
        normalizedName: normalizedName,
        excludingBudgetId: id,
      );
      await _ensureNoConflicts(period, categoryIds, excludingBudgetId: id);

      final now = _clock().toUtc();
      final existingUpdatedAt = existing.updatedAt.toUtc();
      final updatedAt = now.isBefore(existingUpdatedAt)
          ? existingUpdatedAt
          : now;
      final affected =
          await (_db.update(
            _db.budgets,
          )..where((budget) => budget.id.equals(id))).write(
            BudgetsCompanion(
              name: Value(name),
              normalizedName: Value(normalizedName),
              limitAmount: Value(draft.limitAmount),
              updatedAt: Value(updatedAt),
            ),
          );
      if (affected != 1) _throwBudgetNotFound();

      final removed = existingCategoryIds.difference(categoryIds);
      final added = categoryIds.difference(existingCategoryIds);
      if (removed.isNotEmpty) {
        await (_db.delete(_db.budgetCategories)..where(
              (mapping) =>
                  mapping.budgetId.equals(id) &
                  mapping.categoryId.isIn(removed),
            ))
            .go();
      }
      await _insertMappings(id, added);
      await _assertHasCategory(id);
    });
  }

  @override
  Future<void> deleteBudget(int id) async {
    _validateBudgetId(id);
    await _db.transaction(() async {
      await _requireBudget(id);
      final affected = await (_db.delete(
        _db.budgets,
      )..where((budget) => budget.id.equals(id))).go();
      if (affected != 1) _throwBudgetNotFound();
    });
  }

  Future<Map<int, List<BudgetCategoryRef>>> _loadCategoriesForBudgets(
    Set<int> budgetIds,
  ) async {
    if (budgetIds.isEmpty) return const {};
    final parent = _db.alias(_db.categories, 'budget_parent_category');
    final query = _db.select(_db.budgetCategories).join([
      innerJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.budgetCategories.categoryId),
      ),
      innerJoin(parent, parent.id.equalsExp(_db.categories.parentId)),
    ]);
    query
      ..where(_db.budgetCategories.budgetId.isIn(budgetIds))
      ..orderBy([
        OrderingTerm.asc(_db.budgetCategories.budgetId),
        OrderingTerm.asc(parent.sortOrder),
        OrderingTerm.asc(parent.normalizedName),
        OrderingTerm.asc(parent.id),
        OrderingTerm.asc(_db.categories.sortOrder),
        OrderingTerm.asc(_db.categories.normalizedName),
        OrderingTerm.asc(_db.categories.id),
      ]);

    final result = <int, List<BudgetCategoryRef>>{};
    for (final joined in await query.get()) {
      final mapping = joined.readTable(_db.budgetCategories);
      final category = joined.readTable(_db.categories);
      final parentCategory = joined.readTable(parent);
      result
          .putIfAbsent(mapping.budgetId, () => [])
          .add(
            BudgetCategoryRef(
              id: category.id,
              name: category.name,
              parentName: parentCategory.name,
              iconKey: category.iconKey,
              isArchived: category.isArchived,
              parentIsArchived: parentCategory.isArchived,
            ),
          );
    }
    return {
      for (final entry in result.entries)
        entry.key: List<BudgetCategoryRef>.unmodifiable(entry.value),
    };
  }

  Future<Map<int, int>> _loadSpentForBudgets(Set<int> budgetIds) async {
    if (budgetIds.isEmpty) return const {};
    final sortedIds = budgetIds.toList()..sort();
    final placeholders = List.filled(sortedIds.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          '''
          SELECT mapping.budget_id AS budget_id,
                 SUM(allocation.amount) AS spent_amount
          FROM budget_categories AS mapping
          JOIN budgets AS budget ON budget.id = mapping.budget_id
          JOIN ledger_allocations AS allocation
            ON allocation.category_id = mapping.category_id
          JOIN ledger_entries AS entry ON entry.id = allocation.entry_id
          WHERE mapping.budget_id IN ($placeholders)
            AND entry.kind = ?
            AND entry.occurred_day >= budget.start_day
            AND entry.occurred_day <= budget.end_day
          GROUP BY mapping.budget_id
          ''',
          variables: [
            for (final id in sortedIds) Variable.withInt(id),
            Variable.withInt(EntryKind.expense.index),
          ],
          readsFrom: {
            _db.budgets,
            _db.budgetCategories,
            _db.ledgerEntries,
            _db.ledgerAllocations,
          },
        )
        .get();
    return {
      for (final row in rows)
        row.read<int>('budget_id'): row.read<int>('spent_amount'),
    };
  }

  Future<void> _requireUsableCategories(
    Set<int> categoryIds, {
    Set<int> existingCategoryIds = const {},
  }) async {
    final parent = _db.alias(_db.categories, 'budget_validation_parent');
    final query = _db.select(_db.categories).join([
      leftOuterJoin(parent, parent.id.equalsExp(_db.categories.parentId)),
    ])..where(_db.categories.id.isIn(categoryIds));
    final rows = await query.get();
    if (rows.length != categoryIds.length) {
      throw const BudgetValidationException('Subkategori tidak ditemukan.');
    }
    for (final joined in rows) {
      final category = joined.readTable(_db.categories);
      final parentCategory = joined.readTableOrNull(parent);
      if (category.parentId == null ||
          parentCategory == null ||
          parentCategory.parentId != null ||
          category.kind != CategoryKind.expense.index ||
          parentCategory.kind != CategoryKind.expense.index) {
        throw const BudgetValidationException(
          'Anggaran hanya dapat memakai subkategori pengeluaran.',
        );
      }
      final retained = existingCategoryIds.contains(category.id);
      if ((category.isArchived || parentCategory.isArchived) && !retained) {
        throw const BudgetValidationException(
          'Subkategori telah diarsipkan. Pilih subkategori aktif.',
        );
      }
    }
  }

  Future<void> _ensureUniqueName({
    required BudgetPeriod period,
    required String normalizedName,
    int? excludingBudgetId,
  }) async {
    final query = _db.select(_db.budgets)
      ..where((budget) {
        Expression<bool> condition =
            budget.startDay.equals(period.startDay) &
            budget.endDay.equals(period.endDay) &
            budget.normalizedName.equals(normalizedName);
        if (excludingBudgetId != null) {
          condition = condition & budget.id.equals(excludingBudgetId).not();
        }
        return condition;
      });
    if (await query.getSingleOrNull() != null) {
      throw const BudgetValidationException(
        'Nama anggaran sudah digunakan pada periode ini.',
      );
    }
  }

  Future<void> _ensureNoConflicts(
    BudgetPeriod period,
    Set<int> categoryIds, {
    int? excludingBudgetId,
  }) async {
    final rows = await _conflictQuery(
      period,
      excludingBudgetId: excludingBudgetId,
      categoryIds: categoryIds,
    ).get();
    final conflicts = _conflictsFromRows(rows);
    if (conflicts.isEmpty) return;
    final names = conflicts.values
        .expand((items) => items)
        .map((item) => item.budgetName)
        .toSet()
        .take(3)
        .join(', ');
    throw BudgetValidationException(
      'Subkategori sudah digunakan oleh anggaran yang beririsan: $names.',
    );
  }

  Selectable<QueryRow> _conflictQuery(
    BudgetPeriod period, {
    int? excludingBudgetId,
    Set<int>? categoryIds,
  }) {
    final conditions = <String>['budget.start_day <= ?', 'budget.end_day >= ?'];
    final variables = <Variable<int>>[
      Variable.withInt(period.endDay),
      Variable.withInt(period.startDay),
    ];
    if (excludingBudgetId != null) {
      conditions.add('budget.id <> ?');
      variables.add(Variable.withInt(excludingBudgetId));
    }
    if (categoryIds != null) {
      final sortedIds = categoryIds.toList()..sort();
      conditions.add(
        'mapping.category_id IN (${List.filled(sortedIds.length, '?').join(', ')})',
      );
      variables.addAll(sortedIds.map(Variable.withInt));
    }
    return _db.customSelect(
      '''
      SELECT mapping.category_id AS category_id,
             budget.id AS budget_id,
             budget.name AS budget_name,
             budget.period_kind AS period_kind,
             budget.start_day AS start_day,
             budget.end_day AS end_day
      FROM budget_categories AS mapping
      JOIN budgets AS budget ON budget.id = mapping.budget_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY mapping.category_id, budget.start_day, budget.end_day,
               budget.normalized_name, budget.id
      ''',
      variables: variables,
      readsFrom: {_db.budgets, _db.budgetCategories},
    );
  }

  static Map<int, List<BudgetConflict>> _conflictsFromRows(
    List<QueryRow> rows,
  ) {
    final result = <int, List<BudgetConflict>>{};
    for (final row in rows) {
      final categoryId = row.read<int>('category_id');
      result
          .putIfAbsent(categoryId, () => [])
          .add(
            BudgetConflict(
              categoryId: categoryId,
              budgetId: row.read<int>('budget_id'),
              budgetName: row.read<String>('budget_name'),
              period: BudgetPeriod(
                kind: BudgetPeriodKind.values[row.read<int>('period_kind')],
                startDay: row.read<int>('start_day'),
                endDay: row.read<int>('end_day'),
              ),
            ),
          );
    }
    return Map.unmodifiable({
      for (final entry in result.entries)
        entry.key: List<BudgetConflict>.unmodifiable(entry.value),
    });
  }

  Future<BudgetRow> _requireBudget(int id) async {
    final row = await (_db.select(
      _db.budgets,
    )..where((budget) => budget.id.equals(id))).getSingleOrNull();
    if (row == null) _throwBudgetNotFound();
    return row;
  }

  Future<Set<int>> _loadCategoryIds(int budgetId) async {
    final query = _db.select(_db.budgetCategories)
      ..where((mapping) => mapping.budgetId.equals(budgetId));
    return (await query.get()).map((row) => row.categoryId).toSet();
  }

  Future<void> _insertMappings(int budgetId, Set<int> categoryIds) async {
    if (categoryIds.isEmpty) return;
    final sortedIds = categoryIds.toList()..sort();
    await _db.batch((batch) {
      batch.insertAll(_db.budgetCategories, [
        for (final categoryId in sortedIds)
          BudgetCategoryRow(budgetId: budgetId, categoryId: categoryId),
      ]);
    });
  }

  Future<void> _assertHasCategory(int budgetId) async {
    final countExpression = _db.budgetCategories.budgetId.count();
    final count =
        await (_db.selectOnly(_db.budgetCategories)
              ..addColumns([countExpression])
              ..where(_db.budgetCategories.budgetId.equals(budgetId)))
            .map((row) => row.read(countExpression) ?? 0)
            .getSingle();
    if (count < 1) {
      throw const BudgetValidationException(
        'Pilih minimal satu subkategori pengeluaran.',
      );
    }
  }

  static _NormalizedBudgetDraft _normalizeDraft({
    required BudgetPeriod period,
    required String name,
    required int limitAmount,
    required Set<int> categoryIds,
  }) {
    final canonicalName = canonicalizeBudgetName(name);
    _validateLimit(limitAmount);
    final copiedCategoryIds = Set<int>.of(categoryIds);
    _validateCategoryIds(copiedCategoryIds);
    return _NormalizedBudgetDraft(
      period: period,
      name: canonicalName,
      normalizedName: canonicalName.toLowerCase(),
      limitAmount: limitAmount,
      categoryIds: copiedCategoryIds,
    );
  }

  static void _validateLimit(int value) {
    if (value < 1 || value > maxAmount) {
      throw const BudgetValidationException(
        'Batas anggaran harus antara Rp1 dan Rp999.999.999.999.',
      );
    }
  }

  static void _validateCategoryIds(Set<int> values) {
    if (values.isEmpty) {
      throw const BudgetValidationException(
        'Pilih minimal satu subkategori pengeluaran.',
      );
    }
    if (values.any((id) => id < 1)) {
      throw const BudgetValidationException('Subkategori tidak ditemukan.');
    }
  }

  static void _validateReferenceDay(int value) {
    if (!isValidCivilDay(value)) {
      throw const BudgetValidationException('Tanggal acuan tidak valid.');
    }
  }

  static void _validateBudgetId(int value) {
    if (value < 1) _throwBudgetNotFound();
  }

  static Never _throwBudgetNotFound() =>
      throw const BudgetValidationException('Anggaran tidak ditemukan.');

  static Budget _toBudget(BudgetRow row) => Budget(
    id: row.id,
    period: _periodFromRow(row),
    name: row.name,
    normalizedName: row.normalizedName,
    limitAmount: row.limitAmount,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
  );

  static BudgetPeriod _periodFromRow(BudgetRow row) => BudgetPeriod(
    kind: BudgetPeriodKind.values[row.periodKind],
    startDay: row.startDay,
    endDay: row.endDay,
  );

  static BudgetListSnapshot _sortSnapshot(
    List<BudgetProgress> source,
    BudgetTemporalStatus temporalStatus,
  ) {
    final byRange = <(int, int), List<BudgetProgress>>{};
    for (final item in source) {
      final period = item.budget.period;
      byRange.putIfAbsent((period.startDay, period.endDay), () => []).add(item);
    }
    final groups = <BudgetRangeGroup>[];
    for (final entry in byRange.entries) {
      entry.value.sort((left, right) {
        if (temporalStatus == BudgetTemporalStatus.active) {
          final status = _usageRank(left.usageStatus)
              .compareTo(_usageRank(right.usageStatus));
          if (status != 0) return status;
        }
        final name = left.budget.normalizedName.compareTo(
          right.budget.normalizedName,
        );
        return name != 0 ? name : left.budget.id.compareTo(right.budget.id);
      });
      groups.add(
        BudgetRangeGroup(
          startDay: entry.key.$1,
          endDay: entry.key.$2,
          items: entry.value,
        ),
      );
    }
    groups.sort((left, right) {
      int result;
      if (temporalStatus == BudgetTemporalStatus.active) {
        result = _worstUsageRank(left).compareTo(_worstUsageRank(right));
        if (result == 0) result = left.endDay.compareTo(right.endDay);
        if (result == 0) result = left.startDay.compareTo(right.startDay);
      } else if (temporalStatus == BudgetTemporalStatus.upcoming) {
        result = left.startDay.compareTo(right.startDay);
        if (result == 0) result = left.endDay.compareTo(right.endDay);
      } else {
        result = right.endDay.compareTo(left.endDay);
        if (result == 0) result = right.startDay.compareTo(left.startDay);
      }
      return result != 0
          ? result
          : _minimumBudgetId(left).compareTo(_minimumBudgetId(right));
    });
    return BudgetListSnapshot(
      items: groups.expand((group) => group.items),
      groups: groups,
    );
  }

  static int _usageRank(BudgetUsageStatus status) => switch (status) {
    BudgetUsageStatus.exceeded => 0,
    BudgetUsageStatus.exhausted => 1,
    BudgetUsageStatus.nearLimit => 2,
    BudgetUsageStatus.normal => 3,
  };

  static int _worstUsageRank(BudgetRangeGroup group) => group.items
      .map((item) => _usageRank(item.usageStatus))
      .reduce((left, right) => left < right ? left : right);

  static int _minimumBudgetId(BudgetRangeGroup group) => group.items
      .map((item) => item.budget.id)
      .reduce((left, right) => left < right ? left : right);
}

class _NormalizedBudgetDraft {
  const _NormalizedBudgetDraft({
    required this.period,
    required this.name,
    required this.normalizedName,
    required this.limitAmount,
    required this.categoryIds,
  });

  final BudgetPeriod period;
  final String name;
  final String normalizedName;
  final int limitAmount;
  final Set<int> categoryIds;
}
