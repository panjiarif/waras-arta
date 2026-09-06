import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/finance.dart';
import '../../../domain/finance_repository.dart';
import '../../ledger/view_models/ledger_view_model.dart';

typedef CategoryTreeQuery = ({CategoryKind kind, bool includeArchived});

class CategoryFilter {
  const CategoryFilter({
    this.kind = CategoryKind.expense,
    this.includeArchived = false,
  });

  final CategoryKind kind;
  final bool includeArchived;

  CategoryFilter copyWith({CategoryKind? kind, bool? includeArchived}) =>
      CategoryFilter(
        kind: kind ?? this.kind,
        includeArchived: includeArchived ?? this.includeArchived,
      );
}

final categoryFilterProvider =
    NotifierProvider<CategoryFilterViewModel, CategoryFilter>(
      CategoryFilterViewModel.new,
    );

class CategoryFilterViewModel extends Notifier<CategoryFilter> {
  @override
  CategoryFilter build() => const CategoryFilter();

  void selectKind(CategoryKind kind) {
    if (state.kind != kind) state = state.copyWith(kind: kind);
  }

  void setIncludeArchived(bool value) {
    if (state.includeArchived != value) {
      state = state.copyWith(includeArchived: value);
    }
  }
}

final categoryTreeProvider = StreamProvider.autoDispose
    .family<List<CategoryGroup>, CategoryTreeQuery>((ref, query) {
      return ref
          .watch(financeRepositoryProvider)
          .watchCategoryTree(
            query.kind,
            includeArchived: query.includeArchived,
          );
    });

enum CategoryOperation { create, update, archive, restore }

class CategoryActionState {
  const CategoryActionState({this.operation, this.targetId, this.error});

  final CategoryOperation? operation;
  final int? targetId;
  final String? error;

  bool get isSaving => operation != null;
}

final categoryActionsProvider =
    NotifierProvider<CategoryActions, CategoryActionState>(CategoryActions.new);

class CategoryActions extends Notifier<CategoryActionState> {
  @override
  CategoryActionState build() => const CategoryActionState();

  Future<bool> createGroup(CategoryGroupDraft draft) => _run(
    operation: CategoryOperation.create,
    action: (repository) async {
      await repository.createCategoryGroup(draft);
    },
  );

  Future<bool> createSubcategory(CategoryDraft draft) => _run(
    operation: CategoryOperation.create,
    targetId: draft.parentId,
    action: (repository) async {
      await repository.createSubcategory(draft);
    },
  );

  Future<bool> updateCategory(int categoryId, CategoryDraft draft) => _run(
    operation: CategoryOperation.update,
    targetId: categoryId,
    action: (repository) => repository.updateCategory(categoryId, draft),
  );

  Future<bool> setArchived(int categoryId, bool archived) => _run(
    operation: archived ? CategoryOperation.archive : CategoryOperation.restore,
    targetId: categoryId,
    action: (repository) =>
        repository.setCategoryArchived(categoryId, archived),
  );

  void clearError() {
    if (!state.isSaving && state.error != null) {
      state = const CategoryActionState();
    }
  }

  Future<bool> _run({
    required CategoryOperation operation,
    int? targetId,
    required Future<void> Function(FinanceRepository repository) action,
  }) async {
    if (state.isSaving) return false;
    state = CategoryActionState(operation: operation, targetId: targetId);
    try {
      await action(ref.read(financeRepositoryProvider));
      if (ref.mounted) state = const CategoryActionState();
      return true;
    } on FinanceValidationException catch (error) {
      if (ref.mounted) state = CategoryActionState(error: error.message);
    } catch (_) {
      if (ref.mounted) {
        state = const CategoryActionState(
          error: 'Kategori belum diubah. Coba lagi beberapa saat lagi.',
        );
      }
    }
    return false;
  }
}

String categoryKindLabel(CategoryKind kind) =>
    kind == CategoryKind.income ? 'Pemasukan' : 'Pengeluaran';
