const maxAmount = 999999999999;

enum AccountType { cash, bank, eWallet, other }

extension AccountTypeLabel on AccountType {
  String get label => switch (this) {
    AccountType.cash => 'Tunai',
    AccountType.bank => 'Bank',
    AccountType.eWallet => 'E-wallet',
    AccountType.other => 'Lainnya',
  };
}

enum EntryKind { income, expense, transfer, adjustment }

extension EntryKindLabel on EntryKind {
  String get label => switch (this) {
    EntryKind.income => 'Pemasukan',
    EntryKind.expense => 'Pengeluaran',
    EntryKind.transfer => 'Transfer',
    EntryKind.adjustment => 'Saldo awal',
  };
}

const incomeCategories = ['Gaji', 'Usaha', 'Hadiah', 'Lainnya'];
const expenseCategories = [
  'Makan & minum',
  'Transportasi',
  'Belanja',
  'Tagihan',
  'Kesehatan',
  'Hiburan',
  'Lainnya',
];

class FinanceAccount {
  const FinanceAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
  });

  final int id;
  final String name;
  final AccountType type;
  final int balance;
}

class FinanceEntry {
  const FinanceEntry({
    required this.id,
    required this.kind,
    required this.accountId,
    this.destinationAccountId,
    required this.amount,
    this.category,
    required this.note,
    required this.occurredAt,
    required this.createdAt,
  });

  final int id;
  final EntryKind kind;
  final int accountId;
  final int? destinationAccountId;
  final int amount;
  final String? category;
  final String note;

  /// A civil date (year/month/day), independent of entry creation time.
  final DateTime occurredAt;
  final DateTime createdAt;
}

class FinanceSnapshot {
  FinanceSnapshot({
    required List<FinanceAccount> accounts,
    required List<FinanceEntry> entries,
    required this.income,
    required this.expense,
    required this.totalEntries,
  }) : accounts = List.unmodifiable(accounts),
       entries = List.unmodifiable(entries);

  final List<FinanceAccount> accounts;
  final List<FinanceEntry> entries;
  final int income;
  final int expense;
  final int totalEntries;

  int get totalBalance =>
      accounts.fold(0, (sum, account) => sum + account.balance);
  int get net => income - expense;
  bool get hasMore => entries.length < totalEntries;
}

class AccountDraft {
  const AccountDraft({
    required this.name,
    required this.type,
    required this.openingBalance,
    required this.openedAt,
  });

  final String name;
  final AccountType type;
  final int openingBalance;
  final DateTime openedAt;
}

class EntryDraft {
  const EntryDraft({
    required this.kind,
    required this.accountId,
    this.destinationAccountId,
    required this.amount,
    this.category,
    this.note = '',
    required this.occurredAt,
  });

  final EntryKind kind;
  final int accountId;
  final int? destinationAccountId;
  final int amount;
  final String? category;
  final String note;
  final DateTime occurredAt;
}

class FinanceValidationException implements Exception {
  const FinanceValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
