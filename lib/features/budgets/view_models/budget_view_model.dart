import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/budget.dart';
import '../../../domain/budget_repository.dart';
import '../../../domain/finance.dart';
import '../../calendar/view_models/calendar_view_model.dart';

class BudgetFilterSelection {
  const BudgetFilterSelection({
    this.temporalStatus = BudgetTemporalStatus.active,
    this.periodKind,
  });

  final BudgetTemporalStatus temporalStatus;
  final BudgetPeriodKind? periodKind;

  BudgetFilterSelection copyWith({
    BudgetTemporalStatus? temporalStatus,
    BudgetPeriodKind? periodKind,
    bool clearPeriodKind = false,
  }) => BudgetFilterSelection(
    temporalStatus: temporalStatus ?? this.temporalStatus,
    periodKind: clearPeriodKind ? null : periodKind ?? this.periodKind,
  );
}

final budgetFilterProvider =
    NotifierProvider<BudgetFilterController, BudgetFilterSelection>(
      BudgetFilterController.new,
    );

class BudgetFilterController extends Notifier<BudgetFilterSelection> {
  @override
  BudgetFilterSelection build() => const BudgetFilterSelection();

  void reset() {
    state = const BudgetFilterSelection();
  }

  void selectStatus(BudgetTemporalStatus value) {
    if (value != state.temporalStatus) {
      state = state.copyWith(temporalStatus: value);
    }
  }

  void selectKind(BudgetPeriodKind? value) {
    if (value == state.periodKind) return;
    state = value == null
        ? state.copyWith(clearPeriodKind: true)
        : state.copyWith(periodKind: value);
  }
}

final budgetReferenceDayProvider = Provider<int>((ref) {
  return dateTimeToCivilDay(ref.watch(currentDateProvider));
});

final budgetListQueryProvider = Provider.autoDispose<BudgetListFilter>((ref) {
  final selection = ref.watch(budgetFilterProvider);
  return BudgetListFilter(
    temporalStatus: selection.temporalStatus,
    periodKind: selection.periodKind,
    referenceDay: ref.watch(budgetReferenceDayProvider),
  );
});

final budgetSnapshotProvider = StreamProvider.autoDispose
    .family<BudgetListSnapshot, BudgetListFilter>((ref, filter) {
      return ref.watch(budgetRepositoryProvider).watchBudgets(filter);
    });

final filteredBudgetListProvider =
    Provider.autoDispose<AsyncValue<BudgetListSnapshot>>((ref) {
      return ref.watch(
        budgetSnapshotProvider(ref.watch(budgetListQueryProvider)),
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
          return ref.watch(budgetSnapshotProvider(filter)).whenData((snapshot) {
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

enum BudgetOperation { create, update, delete }

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
