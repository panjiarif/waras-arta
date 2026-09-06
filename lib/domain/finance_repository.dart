import 'finance.dart';

abstract interface class FinanceRepository {
  Stream<FinanceSnapshot> watchMonth(DateTime month, {int limit = 50});
  Stream<FinanceEntry?> watchEntry(int id);
  Future<FinanceSnapshot> loadMonth(DateTime month, {int limit = 50});
  Future<int> createAccount(AccountDraft draft);
  Future<int> addEntry(EntryDraft draft);
  Future<void> updateEntry(int id, EntryDraft draft);
  Future<void> deleteEntry(int id);
}
