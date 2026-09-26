import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/budget.dart';
import '../../../domain/budget_repository.dart';
import '../../../domain/finance.dart';
import '../../calendar/view_models/calendar_view_model.dart';

class BudgetFilterSelection {
  const BudgetFilterSelection({
    required this.selectedYear,
    required this.selectedMonth,
    this.periodKind,
    this.followsCurrentPeriod = true,
  });

  factory BudgetFilterSelection.current(DateTime today) =>
      BudgetFilterSelection(
        selectedYear: today.year,
        selectedMonth: today.month,
      );

  final int selectedYear;
  final int selectedMonth;
  final BudgetPeriodKind? periodKind;
  final bool followsCurrentPeriod;

  bool get usesYearNavigator => periodKind == BudgetPeriodKind.yearly;

  BudgetFilterSelection copyWith({
    int? selectedYear,
    int? selectedMonth,
    BudgetPeriodKind? periodKind,
    bool clearPeriodKind = false,
    bool? followsCurrentPeriod,
  }) => BudgetFilterSelection(
    selectedYear: selectedYear ?? this.selectedYear,
    selectedMonth: selectedMonth ?? this.selectedMonth,
    periodKind: clearPeriodKind ? null : periodKind ?? this.periodKind,
    followsCurrentPeriod: followsCurrentPeriod ?? this.followsCurrentPeriod,
  );
}

final budgetFilterProvider =
    NotifierProvider<BudgetFilterController, BudgetFilterSelection>(
      BudgetFilterController.new,
    );

class BudgetFilterController extends Notifier<BudgetFilterSelection> {
  @override
  BudgetFilterSelection build() =>
      BudgetFilterSelection.current(ref.read(currentDateProvider));

  void reset() {
    state = BudgetFilterSelection.current(ref.read(currentDateProvider));
  }

  void refreshToday({DateTime? today}) {
    final DateTime current = today ?? ref.read(currentDateProvider);
    final selectedIndex = state.selectedYear * 12 + state.selectedMonth;
    final currentIndex = current.year * 12 + current.month;
    if (state.followsCurrentPeriod || selectedIndex > currentIndex) {
      state = state.copyWith(
        selectedYear: current.year,
        selectedMonth: current.month,
        followsCurrentPeriod: true,
      );
    }
  }

  void selectKind(BudgetPeriodKind? value) {
    if (value == state.periodKind) return;
    state = value == null
        ? state.copyWith(clearPeriodKind: true)
        : state.copyWith(periodKind: value);
  }

  void showPreviousPeriod() {
    if (state.usesYearNavigator) {
      if (state.selectedYear <= 2000) return;
      state = state.copyWith(
        selectedYear: state.selectedYear - 1,
        followsCurrentPeriod: false,
      );
      return;
    }
    final previous = DateTime(state.selectedYear, state.selectedMonth - 1);
    if (previous.year < 2000) return;
    state = state.copyWith(
      selectedYear: previous.year,
      selectedMonth: previous.month,
      followsCurrentPeriod: false,
    );
  }

  void showNextPeriod() {
    final today = ref.read(currentDateProvider);
    if (state.usesYearNavigator) {
      if (state.selectedYear >= today.year) return;
      final nextYear = state.selectedYear + 1;
      state = state.copyWith(
        selectedYear: nextYear,
        followsCurrentPeriod: nextYear == today.year,
      );
      return;
    }
    final currentIndex = today.year * 12 + today.month;
    final selectedIndex = state.selectedYear * 12 + state.selectedMonth;
    if (selectedIndex >= currentIndex) return;
    final next = DateTime(state.selectedYear, state.selectedMonth + 1);
    state = state.copyWith(
      selectedYear: next.year,
      selectedMonth: next.month,
      followsCurrentPeriod:
          next.year == today.year && next.month == today.month,
    );
  }
}

final budgetReferenceDayProvider = Provider<int>((ref) {
  return dateTimeToCivilDay(ref.watch(currentDateProvider));
});

final budgetListQueryProvider = Provider.autoDispose<BudgetBrowseFilter>((ref) {
  final selection = ref.watch(budgetFilterProvider);
  final referenceDay = ref.watch(budgetReferenceDayProvider);
  if (selection.usesYearNavigator) {
    final period = BudgetPeriod.yearly(selection.selectedYear);
    return BudgetBrowseFilter.year(
      year: selection.selectedYear,
      usageThroughDay: referenceDay < period.endDay
          ? referenceDay
          : period.endDay,
      periodKind: BudgetPeriodKind.yearly,
    );
  }
  final period = BudgetPeriod.monthly(
    selection.selectedYear,
    selection.selectedMonth,
  );
  return BudgetBrowseFilter.month(
    year: selection.selectedYear,
    month: selection.selectedMonth,
    usageThroughDay: referenceDay < period.endDay
        ? referenceDay
        : period.endDay,
    periodKind: selection.periodKind,
  );
});

final budgetSnapshotProvider = StreamProvider.autoDispose
    .family<BudgetListSnapshot, BudgetBrowseFilter>((ref, filter) {
      return ref.watch(budgetRepositoryProvider).watchBudgetsForPeriod(filter);
    });

final legacyBudgetSnapshotProvider = StreamProvider.autoDispose
    .family<BudgetListSnapshot, BudgetListFilter>((ref, filter) {
      return ref.watch(budgetRepositoryProvider).watchBudgets(filter);
    });

final filteredBudgetListProvider =
    Provider.autoDispose<AsyncValue<BudgetListSnapshot>>((ref) {
      return ref.watch(
        budgetSnapshotProvider(ref.watch(budgetListQueryProvider)),
      );
    });

class BudgetMonthlyCopyContext {
  const BudgetMonthlyCopyContext({
    required this.source,
    required this.target,
    required this.itemCount,
  });

  final BudgetPeriod source;
  final BudgetPeriod target;
  final int itemCount;
}

final budgetMonthlyCopyAvailabilityProvider =
    Provider.autoDispose<AsyncValue<BudgetMonthlyCopyContext?>>((ref) {
      final selection = ref.watch(budgetFilterProvider);
      if (selection.periodKind == BudgetPeriodKind.yearly ||
          selection.periodKind == BudgetPeriodKind.custom) {
        return const AsyncValue.data(null);
      }
      final target = BudgetPeriod.monthly(
        selection.selectedYear,
        selection.selectedMonth,
      );
      final previousDate = DateTime(
        selection.selectedYear,
        selection.selectedMonth - 1,
      );
      if (previousDate.year < 2000) return const AsyncValue.data(null);
      final source = BudgetPeriod.monthly(
        previousDate.year,
        previousDate.month,
      );
      final targetFilter = BudgetBrowseFilter(
        windowStartDay: target.startDay,
        windowEndDay: target.endDay,
        usageThroughDay: target.endDay,
        periodKind: BudgetPeriodKind.monthly,
      );
      final sourceFilter = BudgetBrowseFilter(
        windowStartDay: source.startDay,
        windowEndDay: source.endDay,
        usageThroughDay: source.endDay,
        periodKind: BudgetPeriodKind.monthly,
      );
      final targetSnapshot = ref.watch(budgetSnapshotProvider(targetFilter));
      final sourceSnapshot = ref.watch(budgetSnapshotProvider(sourceFilter));
      return targetSnapshot.when(
        loading: () => const AsyncValue.loading(),
        error: AsyncValue.error,
        data: (targetValue) {
          if (targetValue.items.isNotEmpty) {
            return const AsyncValue.data(null);
          }
          return sourceSnapshot.when(
            loading: () => const AsyncValue.loading(),
            error: AsyncValue.error,
            data: (sourceValue) => sourceValue.items.isEmpty
                ? const AsyncValue.data(null)
                : AsyncValue.data(
                    BudgetMonthlyCopyContext(
                      source: source,
                      target: target,
                      itemCount: sourceValue.items.length,
                    ),
                  ),
          );
        },
      );
    });

final activeBudgetSummaryProvider =
    StreamProvider.autoDispose<BudgetListSnapshot>((ref) {
      return ref
          .watch(budgetRepositoryProvider)
          .watchBudgets(
            BudgetListFilter(
              temporalStatus: BudgetTemporalStatus.active,
              referenceDay: ref.watch(budgetReferenceDayProvider),
            ),
          );
    });

final upcomingBudgetSummaryProvider =
    StreamProvider.autoDispose<BudgetListSnapshot>((ref) {
      return ref
          .watch(budgetRepositoryProvider)
          .watchBudgets(
            BudgetListFilter(
              temporalStatus: BudgetTemporalStatus.upcoming,
              referenceDay: ref.watch(budgetReferenceDayProvider),
            ),
          );
    });

final budgetDetailsProvider = StreamProvider.autoDispose
    .family<BudgetDetails?, int>((ref, budgetId) {
      return ref.watch(budgetRepositoryProvider).watchBudget(budgetId);
    });

final budgetProgressProvider = Provider.autoDispose
    .family<AsyncValue<BudgetProgress?>, int>((ref, budgetId) {
      final details = ref.watch(budgetDetailsProvider(budgetId));
      return details.when(
        loading: () => const AsyncValue<BudgetProgress?>.loading(),
        error: (error, stackTrace) =>
            AsyncValue<BudgetProgress?>.error(error, stackTrace),
        data: (value) {
          if (value == null) {
            return const AsyncValue<BudgetProgress?>.data(null);
          }
          final filter = BudgetListFilter(
            temporalStatus: value.budget.period.statusAt(
              ref.watch(budgetReferenceDayProvider),
            ),
            referenceDay: ref.watch(budgetReferenceDayProvider),
          );
          return ref.watch(legacyBudgetSnapshotProvider(filter)).whenData((
            snapshot,
          ) {
            for (final progress in snapshot.items) {
              if (progress.budget.id == budgetId) return progress;
            }
            return null;
          });
        },
      );
    });

typedef BudgetConflictQuery = ({BudgetPeriod period, int? excludingBudgetId});

final budgetConflictsProvider = StreamProvider.autoDispose
    .family<Map<int, List<BudgetConflict>>, BudgetConflictQuery>((ref, query) {
      return ref
          .watch(budgetRepositoryProvider)
          .watchCategoryConflicts(
            query.period,
            excludingBudgetId: query.excludingBudgetId,
          );
    });

final budgetExpenseCategoriesProvider =
    StreamProvider.autoDispose<List<CategoryGroup>>((ref) {
      return ref
          .watch(financeRepositoryProvider)
          .watchCategoryTree(CategoryKind.expense, includeArchived: true);
    });

enum BudgetOperation { create, update, delete, copy }

class BudgetActionState {
  const BudgetActionState({this.operation, this.targetId, this.error});

  final BudgetOperation? operation;
  final int? targetId;
  final String? error;

  bool get isSaving => operation != null;
}

final budgetActionsProvider =
    NotifierProvider<BudgetActions, BudgetActionState>(BudgetActions.new);

class BudgetActions extends Notifier<BudgetActionState> {
  @override
  BudgetActionState build() => const BudgetActionState();

  Future<int?> createBudget(BudgetDraft draft) async {
    if (state.isSaving) return null;
    state = const BudgetActionState(operation: BudgetOperation.create);
    try {
      final id = await ref.read(budgetRepositoryProvider).createBudget(draft);
      if (ref.mounted) state = const BudgetActionState();
      return id;
    } on BudgetValidationException catch (error) {
      if (ref.mounted) state = BudgetActionState(error: error.message);
    } on FinanceValidationException catch (error) {
      if (ref.mounted) state = BudgetActionState(error: error.message);
    } catch (_) {
      if (ref.mounted) {
        state = const BudgetActionState(
          error: 'Anggaran belum tersimpan. Coba lagi beberapa saat lagi.',
        );
      }
    }
    return null;
  }

  Future<bool> updateBudget(int id, BudgetUpdateDraft draft) => _run(
    operation: BudgetOperation.update,
    targetId: id,
    action: (repository) => repository.updateBudget(id, draft),
  );

  Future<bool> deleteBudget(int id) => _run(
    operation: BudgetOperation.delete,
    targetId: id,
    action: (repository) => repository.deleteBudget(id),
  );

  Future<int?> copyMonthlyBudgets({
    required BudgetPeriod source,
    required BudgetPeriod target,
  }) async {
    if (state.isSaving) return null;
    state = const BudgetActionState(operation: BudgetOperation.copy);
    try {
      final count = await ref
          .read(budgetRepositoryProvider)
          .copyMonthlyBudgets(source: source, target: target);
      if (ref.mounted) state = const BudgetActionState();
      return count;
    } on BudgetValidationException catch (error) {
      if (ref.mounted) state = BudgetActionState(error: error.message);
    } on FinanceValidationException catch (error) {
      if (ref.mounted) state = BudgetActionState(error: error.message);
    } catch (_) {
      if (ref.mounted) {
        state = const BudgetActionState(
          error: 'Anggaran belum disalin. Coba lagi beberapa saat lagi.',
        );
      }
    }
    return null;
  }

  void clearError() {
    if (!state.isSaving && state.error != null) {
      state = const BudgetActionState();
    }
  }

  Future<bool> _run({
    required BudgetOperation operation,
    required int targetId,
    required Future<void> Function(BudgetRepository repository) action,
  }) async {
    if (state.isSaving) return false;
    state = BudgetActionState(operation: operation, targetId: targetId);
    try {
      await action(ref.read(budgetRepositoryProvider));
      if (ref.mounted) state = const BudgetActionState();
      return true;
    } on BudgetValidationException catch (error) {
      if (ref.mounted) state = BudgetActionState(error: error.message);
    } on FinanceValidationException catch (error) {
      if (ref.mounted) state = BudgetActionState(error: error.message);
    } catch (_) {
      if (ref.mounted) {
        state = BudgetActionState(
          targetId: targetId,
          error: operation == BudgetOperation.delete
              ? 'Anggaran belum dihapus. Coba lagi beberapa saat lagi.'
              : 'Anggaran belum disimpan. Coba lagi beberapa saat lagi.',
        );
      }
    }
    return false;
  }
}
