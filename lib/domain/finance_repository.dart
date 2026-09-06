import 'finance.dart';

abstract interface class FinanceRepository {
  Stream<List<CategoryGroup>> watchCategoryTree(
    CategoryKind kind, {
    bool includeArchived = false,
  });
  Stream<FinanceSnapshot> watchMonth(DateTime month, {int limit = 50});
  Stream<FinanceEntry?> watchEntry(int id);
  Future<FinanceSnapshot> loadMonth(DateTime month, {int limit = 50});
  Future<int> createAccount(AccountDraft draft);
  Future<int> addEntry(EntryDraft draft);
  Future<void> updateEntry(int id, EntryDraft draft);
  Future<void> deleteEntry(int id);
  Future<int> createCategoryGroup(CategoryGroupDraft draft);
  Future<int> createSubcategory(CategoryDraft draft);
  Future<void> updateCategory(int categoryId, CategoryDraft draft);
  Future<void> setCategoryArchived(int categoryId, bool archived);
}
