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

enum CategoryKind { income, expense }

extension CategoryKindLabel on CategoryKind {
  String get label => switch (this) {
    CategoryKind.income => 'Pemasukan',
    CategoryKind.expense => 'Pengeluaran',
  };
}

/// Stable semantic keys. The UI maps these to Material icons.
const categoryIconKeys = [
  'payments',
  'work',
  'storefront',
  'redeem',
  'restaurant',
  'directions_car',
  'shopping_bag',
  'receipt_long',
  'medical_services',
  'movie',
  'subscriptions',
  'home',
  'school',
  'flight',
  'savings',
  'family_restroom',
  'pets',
  'checkroom',
  'local_grocery_store',
  'sports_esports',
  'volunteer_activism',
  'account_balance',
  'category',
  'more_horiz',
];

class FinanceCategory {
  const FinanceCategory({
    required this.id,
    required this.parentId,
    required this.kind,
    required this.name,
    required this.iconKey,
    required this.isArchived,
    required this.sortOrder,
    required this.systemKey,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int? parentId;
  final CategoryKind kind;
  final String name;
  final String iconKey;
  final bool isArchived;
  final int sortOrder;
  final String? systemKey;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isGroup => parentId == null;
  bool get isBuiltIn => systemKey != null;
}

class CategoryGroup {
  CategoryGroup({required this.parent, required List<FinanceCategory> children})
    : children = List.unmodifiable(children);

  final FinanceCategory parent;
  final List<FinanceCategory> children;
}

class CategoryGroupDraft {
  const CategoryGroupDraft({
    required this.kind,
    required this.parentName,
    required this.parentIconKey,
    required this.firstChildName,
    required this.firstChildIconKey,
    this.parentSortOrder = 0,
    this.firstChildSortOrder = 0,
  });

  final CategoryKind kind;
  final String parentName;
  final String parentIconKey;
  final String firstChildName;
  final String firstChildIconKey;
  final int parentSortOrder;
  final int firstChildSortOrder;
}

class CategoryDraft {
  const CategoryDraft({
    required this.parentId,
    required this.name,
    required this.iconKey,
    this.sortOrder = 0,
  });

  /// Null identifies a root group. Updating cannot change this value.
  final int? parentId;
  final String name;
  final String iconKey;
  final int sortOrder;
}

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
    this.categoryId,
    this.categoryName,
    this.parentCategoryName,
    this.categoryIconKey,
    this.categoryArchived = false,
    required this.note,
    required this.occurredAt,
    required this.createdAt,
  });

  final int id;
  final EntryKind kind;
  final int accountId;
  final int? destinationAccountId;
  final int amount;
  final int? categoryId;
  final String? categoryName;
  final String? parentCategoryName;
  final String? categoryIconKey;
  final bool categoryArchived;
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
    this.categoryId,
    this.note = '',
    required this.occurredAt,
  });

  final EntryKind kind;
  final int accountId;
  final int? destinationAccountId;
  final int amount;
  final int? categoryId;
  final String note;
  final DateTime occurredAt;
}

class FinanceValidationException implements Exception {
  const FinanceValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
