import 'budget.dart';

abstract interface class BudgetRepository {
  Stream<BudgetListSnapshot> watchBudgets(BudgetListFilter filter);
  Future<BudgetListSnapshot> loadBudgets(BudgetListFilter filter);
  Stream<BudgetDetails?> watchBudget(int id);
  Future<BudgetDetails?> getBudget(int id);
  Stream<Map<int, List<BudgetConflict>>> watchCategoryConflicts(
    BudgetPeriod period, {
    int? excludingBudgetId,
  });
  Future<int> createBudget(BudgetDraft draft);
  Future<void> updateBudget(int id, BudgetUpdateDraft draft);
  Future<void> deleteBudget(int id);
}
