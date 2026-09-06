import 'finance.dart';

abstract interface class FinanceRepository {
  Stream<List<CategoryGroup>> watchCategoryTree(
    CategoryKind kind, {
    bool includeArchived = false,
  });
  Stream<List<FinanceAccount>> watchAccounts({bool includeArchived = false});
  Stream<AccountDetails?> watchAccountDetails(int id);
  Stream<FinanceSnapshot> watchMonth(DateTime month, {int limit = 50});
  Stream<CalendarMonthSnapshot> watchCalendarMonth(DateTime month);
  Stream<List<FinanceEntry>> watchDay(DateTime day);
  Stream<FinanceEntry?> watchEntry(int id);
  Future<AccountDetails?> getAccountDetails(int id);
  Future<FinanceSnapshot> loadMonth(DateTime month, {int limit = 50});
  Future<int> createAccount(AccountDraft draft);
  Future<void> updateAccount(int id, AccountUpdateDraft draft);
  Future<void> setAccountArchived(int id, bool archived);
  Future<void> deleteAccount(int id);
  Future<int> adjustAccountBalance(int id, AccountBalanceAdjustmentDraft draft);
  Future<int> addEntry(EntryDraft draft);
  Future<void> updateEntry(int id, EntryDraft draft);
  Future<void> deleteEntry(int id);
  Future<int> createCategoryGroup(CategoryGroupDraft draft);
  Future<int> createSubcategory(CategoryDraft draft);
  Future<void> updateCategory(int categoryId, CategoryDraft draft);
  Future<void> setCategoryArchived(int categoryId, bool archived);
}
