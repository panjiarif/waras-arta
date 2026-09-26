import 'dart:async';

import 'package:waras_arta/domain/budget.dart';
import 'package:waras_arta/domain/budget_repository.dart';

class FakeBudgetRepository implements BudgetRepository {
  FakeBudgetRepository({
    Iterable<BudgetProgress> items = const [],
    Map<int, List<BudgetConflict>> conflicts = const {},
    this.failRead = false,
    this.failConflictRead = false,
  }) : items = List.of(items),
       conflicts = Map.of(conflicts);

  final bool failRead;
  bool failConflictRead;
  final List<BudgetProgress> items;
  final Map<int, List<BudgetConflict>> conflicts;
  final _changes = StreamController<void>.broadcast(sync: true);

  int conflictWatchCount = 0;

  BudgetDraft? createdDraft;
  int? updatedId;
  BudgetUpdateDraft? updatedDraft;
  int? deletedId;
  BudgetPeriod? copiedSource;
  BudgetPeriod? copiedTarget;

  Future<void> dispose() => _changes.close();

  @override
  Stream<BudgetListSnapshot> watchBudgets(BudgetListFilter filter) async* {
    if (failRead) throw StateError('Read failure');
    yield _snapshot(filter);
    await for (final _ in _changes.stream) {
      yield _snapshot(filter);
    }
  }

  @override
  Future<BudgetListSnapshot> loadBudgets(BudgetListFilter filter) async {
    if (failRead) throw StateError('Read failure');
    return _snapshot(filter);
  }

  @override
  Stream<BudgetListSnapshot> watchBudgetsForPeriod(
    BudgetBrowseFilter filter,
  ) async* {
    if (failRead) throw StateError('Read failure');
    yield _periodSnapshot(filter);
    await for (final _ in _changes.stream) {
      yield _periodSnapshot(filter);
    }
  }

  @override
  Future<BudgetListSnapshot> loadBudgetsForPeriod(
    BudgetBrowseFilter filter,
  ) async {
    if (failRead) throw StateError('Read failure');
    return _periodSnapshot(filter);
  }

  BudgetListSnapshot _periodSnapshot(BudgetBrowseFilter filter) {
    final matching = items
        .where((item) {
          final period = item.budget.period;
          return period.startDay <= filter.windowEndDay &&
              filter.windowStartDay <= period.endDay &&
              (filter.periodKind == null || period.kind == filter.periodKind);
        })
        .toList(growable: false);
    return BudgetListSnapshot.fromItems(matching);
  }

  BudgetListSnapshot _snapshot(BudgetListFilter filter) {
    final matching = items
        .where(
          (item) =>
              item.budget.period.statusAt(filter.referenceDay) ==
                  filter.temporalStatus &&
              (filter.periodKind == null ||
                  item.budget.period.kind == filter.periodKind),
        )
        .toList(growable: false);
    return BudgetListSnapshot.fromItems(matching);
  }

  @override
  Stream<BudgetDetails?> watchBudget(int id) async* {
    if (failRead) throw StateError('Read failure');
    yield await getBudget(id);
    await for (final _ in _changes.stream) {
      yield await getBudget(id);
    }
  }

  @override
  Future<BudgetDetails?> getBudget(int id) async {
    final index = items.indexWhere((item) => item.budget.id == id);
    if (index < 0) return null;
    final item = items[index];
    return BudgetDetails(budget: item.budget, categories: item.categories);
  }

  @override
  Stream<Map<int, List<BudgetConflict>>> watchCategoryConflicts(
    BudgetPeriod period, {
    int? excludingBudgetId,
  }) async* {
    conflictWatchCount++;
    if (failRead || failConflictRead) throw StateError('Read failure');
    Map<int, List<BudgetConflict>> visible() => {
      for (final entry in conflicts.entries)
        entry.key: entry.value
            .where(
              (item) =>
                  item.budgetId != excludingBudgetId &&
                  item.period.overlaps(period),
            )
            .toList(growable: false),
    };
    yield visible();
    await for (final _ in _changes.stream) {
      yield visible();
    }
  }

  @override
  Future<int> createBudget(BudgetDraft draft) async {
    createdDraft = draft;
    final id =
        items.fold<int>(
          0,
          (largest, item) =>
              item.budget.id > largest ? item.budget.id : largest,
        ) +
        1;
    final now = DateTime.utc(2026, 2, 10);
    items.add(
      BudgetProgress(
        budget: Budget(
          id: id,
          period: draft.period,
          name: draft.name.trim(),
          normalizedName: draft.name.trim().toLowerCase(),
          limitAmount: draft.limitAmount,
          createdAt: now,
          updatedAt: now,
        ),
        categories: [
          for (final categoryId in draft.categoryIds)
            fakeBudgetCategory(id: categoryId),
        ],
        spentAmount: 0,
      ),
    );
    _changes.add(null);
    return id;
  }

  @override
  Future<void> updateBudget(int id, BudgetUpdateDraft draft) async {
    updatedId = id;
    updatedDraft = draft;
    final index = items.indexWhere((item) => item.budget.id == id);
    if (index < 0) {
      throw const BudgetValidationException('Anggaran tidak ditemukan.');
    }
    final previous = items[index];
    items[index] = BudgetProgress(
      budget: Budget(
        id: id,
        period: previous.budget.period,
        name: draft.name.trim(),
        normalizedName: draft.name.trim().toLowerCase(),
        limitAmount: draft.limitAmount,
        createdAt: previous.budget.createdAt,
        updatedAt: DateTime.utc(2026, 2, 11),
      ),
      categories: [
        for (final categoryId in draft.categoryIds)
          previous.categories
                  .where((category) => category.id == categoryId)
                  .firstOrNull ??
              fakeBudgetCategory(id: categoryId),
      ],
      spentAmount: previous.spentAmount,
    );
    _changes.add(null);
  }

  @override
  Future<void> deleteBudget(int id) async {
    deletedId = id;
    final before = items.length;
    items.removeWhere((item) => item.budget.id == id);
    if (items.length == before) {
      throw const BudgetValidationException('Anggaran tidak ditemukan.');
    }
    _changes.add(null);
  }

  @override
  Future<int> copyMonthlyBudgets({
    required BudgetPeriod source,
    required BudgetPeriod target,
  }) async {
    if (source.kind != BudgetPeriodKind.monthly ||
        target.kind != BudgetPeriodKind.monthly) {
      throw const BudgetValidationException(
        'Hanya anggaran bulanan yang dapat disalin.',
      );
    }
    final expectedTarget = DateTime(
      civilDayToDateTime(source.startDay).year,
      civilDayToDateTime(source.startDay).month + 1,
    );
    if (target.startDay != dateTimeToCivilDay(expectedTarget)) {
      throw const BudgetValidationException(
        'Tujuan harus bulan setelah sumber.',
      );
    }
    final sourceItems = items
        .where((item) => item.budget.period == source)
        .toList(growable: false);
    if (sourceItems.isEmpty) {
      throw const BudgetValidationException(
        'Bulan sebelumnya belum memiliki anggaran.',
      );
    }
    if (items.any((item) => item.budget.period == target)) {
      throw const BudgetValidationException(
        'Bulan tujuan sudah memiliki anggaran.',
      );
    }
    copiedSource = source;
    copiedTarget = target;
    var nextId = items.fold<int>(
      0,
      (largest, item) => item.budget.id > largest ? item.budget.id : largest,
    );
    final now = DateTime.utc(2026, 2, 10);
    for (final item in sourceItems) {
      nextId++;
      items.add(
        BudgetProgress(
          budget: Budget(
            id: nextId,
            period: target,
            name: item.budget.name,
            normalizedName: item.budget.normalizedName,
            limitAmount: item.budget.limitAmount,
            createdAt: now,
            updatedAt: now,
          ),
          categories: item.categories,
          spentAmount: 0,
        ),
      );
    }
    _changes.add(null);
    return sourceItems.length;
  }
}

BudgetCategoryRef fakeBudgetCategory({
  int id = 10,
  String name = 'Umum',
  String parentName = 'Makan & minum',
  String iconKey = 'restaurant',
  bool isArchived = false,
  bool parentIsArchived = false,
}) => BudgetCategoryRef(
  id: id,
  name: name,
  parentName: parentName,
  iconKey: iconKey,
  isArchived: isArchived,
  parentIsArchived: parentIsArchived,
);

BudgetProgress fakeBudgetProgress({
  int id = 1,
  String name = 'Makan di luar',
  int limitAmount = 1000000,
  int spentAmount = 250000,
  BudgetPeriod? period,
  List<BudgetCategoryRef>? categories,
}) {
  final now = DateTime.utc(2026, 2, 1);
  return BudgetProgress(
    budget: Budget(
      id: id,
      period: period ?? BudgetPeriod.monthly(2026, 2),
      name: name,
      normalizedName: name.toLowerCase(),
      limitAmount: limitAmount,
      createdAt: now,
      updatedAt: now,
    ),
    categories: categories ?? [fakeBudgetCategory()],
    spentAmount: spentAmount,
  );
}
