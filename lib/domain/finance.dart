const maxAmount = 999999999999;
const maxEntryAllocations = 50;

enum AccountType { cash, bank, eWallet, other }

extension AccountTypeLabel on AccountType {
  String get label => switch (this) {
    AccountType.cash => 'Tunai',
    AccountType.bank => 'Bank',
    AccountType.eWallet => 'E-wallet',
    AccountType.other => 'Lainnya',
  };
}

enum AccountBalanceGroup { primary, savingsInvestment }

extension AccountBalanceGroupLabel on AccountBalanceGroup {
  String get label => switch (this) {
    AccountBalanceGroup.primary => 'Saldo utama',
    AccountBalanceGroup.savingsInvestment => 'Simpanan & investasi',
  };

  String get description => switch (this) {
    AccountBalanceGroup.primary =>
      'Untuk uang yang digunakan dalam kebutuhan rutin.',
    AccountBalanceGroup.savingsInvestment => 'Untuk rekening atau tempat uang yang benar-benar terpisah, bukan alokasi saldo di rekening lain.',
  };
}

enum EntryKind { income, expense, transfer, adjustment }

extension EntryKindLabel on EntryKind {
  String get label => switch (this) {
    EntryKind.income => 'Pemasukan',
    EntryKind.expense => 'Pengeluaran',
    EntryKind.transfer => 'Transfer',
    EntryKind.adjustment => 'Penyesuaian saldo',
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
    this.balanceGroup = AccountBalanceGroup.primary,
    this.isArchived = false,
  });

  final int id;
  final String name;
  final AccountType type;
  final int balance;
  final AccountBalanceGroup balanceGroup;
  final bool isArchived;
}

class AccountDetails {
  const AccountDetails({
    required this.account,
    required this.createdAt,
    required this.ledgerEntryCount,
  });

  final FinanceAccount account;
  final DateTime createdAt;
  final int ledgerEntryCount;

  bool get canDelete => ledgerEntryCount == 0;
}

class FinanceEntryAllocation {
  const FinanceEntryAllocation({
    required this.position,
    required this.categoryId,
    required this.amount,
    required this.categoryName,
    required this.parentCategoryName,
    required this.categoryIconKey,
    required this.categoryArchived,
  });

  final int position;
  final int categoryId;
  final int amount;
  final String categoryName;
  final String parentCategoryName;
  final String categoryIconKey;
  final bool categoryArchived;
}

class FinanceEntry {
  FinanceEntry({
    required this.id,
    required this.kind,
    required this.accountId,
    this.destinationAccountId,
    required this.amount,
    Iterable<FinanceEntryAllocation> allocations = const [],
    required this.note,
    required this.occurredAt,
    required this.createdAt,
  }) : allocations = List.unmodifiable(allocations);

  final int id;
  final EntryKind kind;
  final int accountId;
  final int? destinationAccountId;

  /// The canonical header total. For income and expense entries this equals
  /// the sum of [allocations].
  final int amount;
  final List<FinanceEntryAllocation> allocations;
  final String note;

  /// A civil date (year/month/day), independent of entry creation time.
  final DateTime occurredAt;
  final DateTime createdAt;

  FinanceEntryAllocation? get singleAllocation =>
      allocations.length == 1 ? allocations.single : null;

  // Transitional accessors for the current single-category presentation.
  // They intentionally return null/false for split entries instead of
  // pretending that the first allocation represents the whole transaction.
  int? get categoryId => singleAllocation?.categoryId;
  String? get categoryName => singleAllocation?.categoryName;
  String? get parentCategoryName => singleAllocation?.parentCategoryName;
  String? get categoryIconKey => singleAllocation?.categoryIconKey;
  bool get categoryArchived => singleAllocation?.categoryArchived ?? false;
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

  int get primaryBalance => accounts
      .where(
        (account) =>
            !account.isArchived &&
            account.balanceGroup == AccountBalanceGroup.primary,
      )
      .fold(0, (sum, account) => sum + account.balance);

  int get savingsInvestmentBalance => accounts
      .where(
        (account) =>
            !account.isArchived &&
            account.balanceGroup == AccountBalanceGroup.savingsInvestment,
      )
      .fold(0, (sum, account) => sum + account.balance);

  /// Total seluruh rekening aktif. Ikhtisar memakai [primaryBalance] agar
  /// simpanan dan investasi tidak tampak sebagai uang yang siap digunakan.
  int get totalBalance => primaryBalance + savingsInvestmentBalance;
  int get net => income - expense;
  bool get hasMore => entries.length < totalEntries;
}

class CalendarDaySummary {
  const CalendarDaySummary({
    required this.day,
    required this.income,
    required this.expense,
    required this.transferCount,
    required this.adjustmentCount,
    required this.entryCount,
  });

  /// A normalized civil date (year/month/day).
  final DateTime day;
  final int income;
  final int expense;
  final int transferCount;
  final int adjustmentCount;
  final int entryCount;

  int get net => income - expense;
}

class CalendarMonthSnapshot {
  CalendarMonthSnapshot({
    required this.month,
    required List<CalendarDaySummary> days,
  }) : days = List.unmodifiable(days);

  /// The first day of the represented civil month.
  final DateTime month;

  /// Active days in ascending order. Empty days are intentionally omitted.
  final List<CalendarDaySummary> days;

  int get totalIncome => days.fold(0, (sum, day) => sum + day.income);
  int get totalExpense => days.fold(0, (sum, day) => sum + day.expense);
  int get totalTransferCount =>
      days.fold(0, (sum, day) => sum + day.transferCount);
  int get totalAdjustmentCount =>
      days.fold(0, (sum, day) => sum + day.adjustmentCount);
  int get totalEntryCount => days.fold(0, (sum, day) => sum + day.entryCount);
  int get activeDayCount => days.length;
  int get net => totalIncome - totalExpense;

  CalendarDaySummary? summaryForDay(DateTime value) {
    final key = value.year * 10000 + value.month * 100 + value.day;
    for (final summary in days) {
      final day = summary.day;
      if (day.year * 10000 + day.month * 100 + day.day == key) {
        return summary;
      }
    }
    return null;
  }
}

class AccountDraft {
  const AccountDraft({
    required this.name,
    required this.type,
    required this.openingBalance,
    required this.openedAt,
    this.balanceGroup = AccountBalanceGroup.primary,
  });

  final String name;
  final AccountType type;
  final int openingBalance;
  final DateTime openedAt;
  final AccountBalanceGroup balanceGroup;
}

class AccountUpdateDraft {
  const AccountUpdateDraft({
    required this.name,
    required this.type,
    required this.balanceGroup,
  });

  final String name;
  final AccountType type;
  final AccountBalanceGroup balanceGroup;
}

class AccountBalanceAdjustmentDraft {
  const AccountBalanceAdjustmentDraft({
    required this.targetBalance,
    required this.occurredAt,
    this.note = '',
  });

  final int targetBalance;
  final DateTime occurredAt;
  final String note;
}

class EntryAllocationDraft {
  const EntryAllocationDraft({required this.categoryId, required this.amount});

  final int categoryId;
  final int amount;
}

class EntryDraft {
  EntryDraft._({
    required this.kind,
    required this.accountId,
    required this.destinationAccountId,
    required this.transferAmount,
    required Iterable<EntryAllocationDraft> allocations,
    required this.note,
    required this.occurredAt,
  }) : allocations = List.unmodifiable(allocations);

  factory EntryDraft.singleAllocation({
    required EntryKind kind,
    required int accountId,
    required int amount,
    required int categoryId,
    String note = '',
    required DateTime occurredAt,
  }) => EntryDraft.withAllocations(
    kind: kind,
    accountId: accountId,
    allocations: [EntryAllocationDraft(categoryId: categoryId, amount: amount)],
    note: note,
    occurredAt: occurredAt,
  );

  factory EntryDraft.withAllocations({
    required EntryKind kind,
    required int accountId,
    required Iterable<EntryAllocationDraft> allocations,
    String note = '',
    required DateTime occurredAt,
  }) {
    if (kind != EntryKind.income && kind != EntryKind.expense) {
      throw ArgumentError.value(
        kind,
        'kind',
        'Alokasi hanya berlaku untuk pemasukan atau pengeluaran.',
      );
    }
    return EntryDraft._(
      kind: kind,
      accountId: accountId,
      destinationAccountId: null,
      transferAmount: null,
      allocations: allocations,
      note: note,
      occurredAt: occurredAt,
    );
  }

  factory EntryDraft.transfer({
    required int accountId,
    required int destinationAccountId,
    required int amount,
    String note = '',
    required DateTime occurredAt,
  }) => EntryDraft._(
    kind: EntryKind.transfer,
    accountId: accountId,
    destinationAccountId: destinationAccountId,
    transferAmount: amount,
    allocations: const [],
    note: note,
    occurredAt: occurredAt,
  );

  final EntryKind kind;
  final int accountId;
  final int? destinationAccountId;

  /// Set only for transfers. Income and expense totals are derived from
  /// [allocations], so the draft cannot carry a conflicting header total.
  final int? transferAmount;
  final List<EntryAllocationDraft> allocations;
  final String note;
  final DateTime occurredAt;

  /// Convenience view for presentation and test doubles. The repository still
  /// validates and derives the persisted header total independently.
  int get amount =>
      transferAmount ??
      allocations.fold(0, (total, allocation) => total + allocation.amount);

  int? get categoryId =>
      allocations.length == 1 ? allocations.single.categoryId : null;
}

class FinanceValidationException implements Exception {
  const FinanceValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
