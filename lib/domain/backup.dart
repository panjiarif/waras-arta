import 'budget.dart';
import 'finance.dart';

const warasArtaBackupFormat = 'waras-arta-backup';
const oldestSupportedBackupVersion = 1;
const currentBackupVersion = 4;
const maxBackupAccountRecords = 2000;
const maxBackupCategoryRecords = 20000;
const maxBackupLedgerRecords = 100000;
const maxBackupLedgerAllocationRecords = 200000;
const maxBackupLedgerAllocationsPerEntry = 50;
const maxBackupBudgetRecords = 10000;
const maxBackupBudgetCategoryRecords = 100000;
const maxBackupCategoriesPerBudget = 20000;
const maxBackupRecordId = 1000000000000;
const minimumRestoredIdHeadroom = 1000000;

class BackupDocument {
  BackupDocument({
    this.format = warasArtaBackupFormat,
    this.backupVersion = currentBackupVersion,
    required this.databaseSchemaVersion,
    required DateTime createdAtUtc,
    required this.sequences,
    required Iterable<BackupAccount> accounts,
    required Iterable<BackupCategory> categories,
    required Iterable<BackupLedgerEntry> ledgerEntries,
    Iterable<BackupBudget> budgets = const [],
  }) : createdAtUtc = createdAtUtc.toUtc(),
       accounts = List.unmodifiable(accounts),
       categories = List.unmodifiable(categories),
       ledgerEntries = List.unmodifiable(ledgerEntries),
       budgets = List.unmodifiable(budgets);

  factory BackupDocument.fromJson(Map<String, Object?> json) {
    final format = _readString(json, 'format', 'format');
    if (format != warasArtaBackupFormat) {
      throw const BackupFormatException('File bukan backup Waras Arta.');
    }
    final backupVersion = _readInt(json, 'backupVersion', 'backupVersion');
    return switch (backupVersion) {
      1 => _readBackupDocumentV1(
        json,
        format: format,
        backupVersion: backupVersion,
      ),
      2 => _readBackupDocumentV2(
        json,
        format: format,
        backupVersion: backupVersion,
      ),
      3 => _readBackupDocumentV3(
        json,
        format: format,
        backupVersion: backupVersion,
      ),
      4 => _readBackupDocumentV4(
        json,
        format: format,
        backupVersion: backupVersion,
      ),
      _ => throw const BackupFormatException(
        'Versi backup belum didukung oleh aplikasi ini.',
      ),
    };
  }

  static BackupDocument _readBackupDocumentV1(
    Map<String, Object?> json, {
    required String format,
    required int backupVersion,
  }) {
    _requireExactKeys(json, const {
      'format',
      'backupVersion',
      'databaseSchemaVersion',
      'createdAtUtc',
      'sequences',
      'data',
    }, 'backup');
    final data = _readObject(json, 'data', 'data');
    _requireExactKeys(data, const {
      'accounts',
      'categories',
      'ledgerEntries',
    }, 'data');
    final databaseSchemaVersion = _readInt(
      json,
      'databaseSchemaVersion',
      'databaseSchemaVersion',
    );
    _requireBackupVersionSchemaPair(backupVersion, databaseSchemaVersion);
    final document = BackupDocument(
      format: format,
      backupVersion: backupVersion,
      databaseSchemaVersion: databaseSchemaVersion,
      createdAtUtc: _readDateTime(json, 'createdAtUtc', 'createdAtUtc'),
      sequences: BackupSequences.fromJson(
        _readObject(json, 'sequences', 'sequences'),
      ),
      accounts: _readObjectList(
        data,
        'accounts',
        'data.accounts',
        _readLegacyBackupAccount,
        maximumLength: maxBackupAccountRecords,
      ),
      categories: _readObjectList(
        data,
        'categories',
        'data.categories',
        BackupCategory.fromJson,
        maximumLength: maxBackupCategoryRecords,
      ),
      ledgerEntries: _readObjectList(
        data,
        'ledgerEntries',
        'data.ledgerEntries',
        _readBackupLedgerEntryV1,
        maximumLength: maxBackupLedgerRecords,
      ),
      budgets: const [],
    );
    validateBackupDocument(document);
    return document;
  }

  static BackupDocument _readBackupDocumentV2(
    Map<String, Object?> json, {
    required String format,
    required int backupVersion,
  }) {
    _requireExactKeys(json, const {
      'format',
      'backupVersion',
      'databaseSchemaVersion',
      'createdAtUtc',
      'sequences',
      'data',
    }, 'backup');
    final data = _readObject(json, 'data', 'data');
    _requireExactKeys(data, const {
      'accounts',
      'categories',
      'ledgerEntries',
    }, 'data');
    final databaseSchemaVersion = _readInt(
      json,
      'databaseSchemaVersion',
      'databaseSchemaVersion',
    );
    _requireBackupVersionSchemaPair(backupVersion, databaseSchemaVersion);
    final document = BackupDocument(
      format: format,
      backupVersion: backupVersion,
      databaseSchemaVersion: databaseSchemaVersion,
      createdAtUtc: _readDateTime(json, 'createdAtUtc', 'createdAtUtc'),
      sequences: BackupSequences.fromJson(
        _readObject(json, 'sequences', 'sequences'),
      ),
      accounts: _readObjectList(
        data,
        'accounts',
        'data.accounts',
        _readLegacyBackupAccount,
        maximumLength: maxBackupAccountRecords,
      ),
      categories: _readObjectList(
        data,
        'categories',
        'data.categories',
        BackupCategory.fromJson,
        maximumLength: maxBackupCategoryRecords,
      ),
      ledgerEntries: _readBackupLedgerEntriesV2(data),
      budgets: const [],
    );
    validateBackupDocument(document);
    return document;
  }

  static BackupDocument _readBackupDocumentV3(
    Map<String, Object?> json, {
    required String format,
    required int backupVersion,
  }) {
    _requireExactKeys(json, const {
      'format',
      'backupVersion',
      'databaseSchemaVersion',
      'createdAtUtc',
      'sequences',
      'data',
    }, 'backup');
    final data = _readObject(json, 'data', 'data');
    _requireExactKeys(data, const {
      'accounts',
      'categories',
      'ledgerEntries',
    }, 'data');
    final databaseSchemaVersion = _readInt(
      json,
      'databaseSchemaVersion',
      'databaseSchemaVersion',
    );
    _requireBackupVersionSchemaPair(backupVersion, databaseSchemaVersion);
    final document = BackupDocument(
      format: format,
      backupVersion: backupVersion,
      databaseSchemaVersion: databaseSchemaVersion,
      createdAtUtc: _readDateTime(json, 'createdAtUtc', 'createdAtUtc'),
      sequences: BackupSequences.fromJson(
        _readObject(json, 'sequences', 'sequences'),
      ),
      accounts: _readObjectList(
        data,
        'accounts',
        'data.accounts',
        BackupAccount.fromJson,
        maximumLength: maxBackupAccountRecords,
      ),
      categories: _readObjectList(
        data,
        'categories',
        'data.categories',
        BackupCategory.fromJson,
        maximumLength: maxBackupCategoryRecords,
      ),
      ledgerEntries: _readBackupLedgerEntriesV2(data),
      budgets: const [],
    );
    validateBackupDocument(document);
    return document;
  }

  static BackupDocument _readBackupDocumentV4(
    Map<String, Object?> json, {
    required String format,
    required int backupVersion,
  }) {
    _requireExactKeys(json, const {
      'format',
      'backupVersion',
      'databaseSchemaVersion',
      'createdAtUtc',
      'sequences',
      'data',
    }, 'backup');
    final data = _readObject(json, 'data', 'data');
    _requireExactKeys(data, const {
      'accounts',
      'categories',
      'ledgerEntries',
      'budgets',
    }, 'data');
    final databaseSchemaVersion = _readInt(
      json,
      'databaseSchemaVersion',
      'databaseSchemaVersion',
    );
    _requireBackupVersionSchemaPair(backupVersion, databaseSchemaVersion);
    final document = BackupDocument(
      format: format,
      backupVersion: backupVersion,
      databaseSchemaVersion: databaseSchemaVersion,
      createdAtUtc: _readDateTime(json, 'createdAtUtc', 'createdAtUtc'),
      sequences: BackupSequences.fromJsonV4(
        _readObject(json, 'sequences', 'sequences'),
      ),
      accounts: _readObjectList(
        data,
        'accounts',
        'data.accounts',
        BackupAccount.fromJson,
        maximumLength: maxBackupAccountRecords,
      ),
      categories: _readObjectList(
        data,
        'categories',
        'data.categories',
        BackupCategory.fromJson,
        maximumLength: maxBackupCategoryRecords,
      ),
      ledgerEntries: _readBackupLedgerEntriesV2(data),
      budgets: _readBackupBudgetsV4(data),
    );
    validateBackupDocument(document);
    return document;
  }

  final String format;
  final int backupVersion;
  final int databaseSchemaVersion;
  final DateTime createdAtUtc;
  final BackupSequences sequences;
  final List<BackupAccount> accounts;
  final List<BackupCategory> categories;
  final List<BackupLedgerEntry> ledgerEntries;
  final List<BackupBudget> budgets;

  BackupSummary get summary => BackupSummary(
    createdAtUtc: createdAtUtc,
    accountCount: accounts.length,
    archivedAccountCount: accounts.where((item) => item.isArchived).length,
    categoryCount: categories.length,
    archivedCategoryCount: categories.where((item) => item.isArchived).length,
    ledgerEntryCount: ledgerEntries.length,
    budgetCount: budgets.length,
  );

  Map<String, Object?> toJson() {
    validateBackupDocument(this, requireSequenceHeadroom: false);
    final Map<String, Object?> Function(BackupLedgerEntry) encodeLedgerEntry =
        switch (backupVersion) {
          1 => _writeBackupLedgerEntryV1,
          2 => _writeBackupLedgerEntryV2,
          3 => _writeBackupLedgerEntryV2,
          4 => _writeBackupLedgerEntryV2,
          _ => throw const BackupFormatException(
            'Versi backup belum didukung oleh aplikasi ini.',
          ),
        };
    final Map<String, Object?> Function(BackupAccount) encodeAccount =
        switch (backupVersion) {
          1 => _writeLegacyBackupAccount,
          2 => _writeLegacyBackupAccount,
          3 => (item) => item.toJson(),
          4 => (item) => item.toJson(),
          _ => throw const BackupFormatException(
            'Versi backup belum didukung oleh aplikasi ini.',
          ),
        };
    return {
      'format': format,
      'backupVersion': backupVersion,
      'databaseSchemaVersion': databaseSchemaVersion,
      'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      'sequences': sequences.toJson(includeBudgets: backupVersion >= 4),
      'data': {
        'accounts': accounts.map(encodeAccount).toList(),
        'categories': categories.map((item) => item.toJson()).toList(),
        'ledgerEntries': ledgerEntries.map(encodeLedgerEntry).toList(),
        if (backupVersion >= 4)
          'budgets': budgets.map((item) => item.toJson()).toList(),
      },
    };
  }
}

bool canRestoreBackupDocumentToSchema(
  BackupDocument document,
  int targetDatabaseSchemaVersion,
) => switch (targetDatabaseSchemaVersion) {
  3 => document.backupVersion == 1 && document.databaseSchemaVersion == 3,
  4 =>
    (document.backupVersion == 1 && document.databaseSchemaVersion == 3) ||
        (document.backupVersion == 2 && document.databaseSchemaVersion == 4),
  5 =>
    (document.backupVersion == 1 && document.databaseSchemaVersion == 3) ||
        (document.backupVersion == 2 && document.databaseSchemaVersion == 4) ||
        (document.backupVersion == 3 && document.databaseSchemaVersion == 5),
  6 =>
    (document.backupVersion == 1 && document.databaseSchemaVersion == 3) ||
        (document.backupVersion == 2 && document.databaseSchemaVersion == 4) ||
        (document.backupVersion == 3 && document.databaseSchemaVersion == 5) ||
        (document.backupVersion == 4 && document.databaseSchemaVersion == 6),
  _ => false,
};

class BackupSummary {
  const BackupSummary({
    required this.createdAtUtc,
    required this.accountCount,
    required this.archivedAccountCount,
    required this.categoryCount,
    required this.archivedCategoryCount,
    required this.ledgerEntryCount,
    this.budgetCount = 0,
  });

  final DateTime createdAtUtc;
  final int accountCount;
  final int archivedAccountCount;
  final int categoryCount;
  final int archivedCategoryCount;
  final int ledgerEntryCount;
  final int budgetCount;
}

class BackupSequences {
  const BackupSequences({
    required this.accounts,
    required this.categories,
    required this.ledgerEntries,
    this.budgets = 0,
  });

  factory BackupSequences.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const {
      'accounts',
      'categories',
      'ledgerEntries',
    }, 'sequences');
    return BackupSequences(
      accounts: _readInt(json, 'accounts', 'sequences.accounts'),
      categories: _readInt(json, 'categories', 'sequences.categories'),
      ledgerEntries: _readInt(json, 'ledgerEntries', 'sequences.ledgerEntries'),
      budgets: 0,
    );
  }

  factory BackupSequences.fromJsonV4(Map<String, Object?> json) {
    _requireExactKeys(json, const {
      'accounts',
      'categories',
      'ledgerEntries',
      'budgets',
    }, 'sequences');
    return BackupSequences(
      accounts: _readInt(json, 'accounts', 'sequences.accounts'),
      categories: _readInt(json, 'categories', 'sequences.categories'),
      ledgerEntries: _readInt(json, 'ledgerEntries', 'sequences.ledgerEntries'),
      budgets: _readInt(json, 'budgets', 'sequences.budgets'),
    );
  }

  final int accounts;
  final int categories;
  final int ledgerEntries;
  final int budgets;

  Map<String, Object?> toJson({bool includeBudgets = true}) => {
    'accounts': accounts,
    'categories': categories,
    'ledgerEntries': ledgerEntries,
    if (includeBudgets) 'budgets': budgets,
  };
}

class BackupBudget {
  BackupBudget({
    required this.id,
    required this.periodKind,
    required this.startDay,
    required this.endDay,
    required this.name,
    required this.normalizedName,
    required this.limitAmount,
    required Iterable<int> categoryIds,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  }) : categoryIds = List.unmodifiable(categoryIds);

  factory BackupBudget.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const {
      'id',
      'periodKind',
      'startDay',
      'endDay',
      'name',
      'normalizedName',
      'limitAmount',
      'categoryIds',
      'createdAtUtc',
      'updatedAtUtc',
    }, 'budget');
    final rawCategoryIds = _readList(
      json,
      'categoryIds',
      'budget.categoryIds',
      maximumLength: maxBackupCategoriesPerBudget,
    );
    return BackupBudget(
      id: _readInt(json, 'id', 'budget.id'),
      periodKind: _readEnum(
        json,
        'periodKind',
        'budget.periodKind',
        BudgetPeriodKind.values,
      ),
      startDay: _readInt(json, 'startDay', 'budget.startDay'),
      endDay: _readInt(json, 'endDay', 'budget.endDay'),
      name: _readString(json, 'name', 'budget.name'),
      normalizedName: _readString(
        json,
        'normalizedName',
        'budget.normalizedName',
      ),
      limitAmount: _readInt(json, 'limitAmount', 'budget.limitAmount'),
      categoryIds: [
        for (var index = 0; index < rawCategoryIds.length; index++)
          _asInt(rawCategoryIds[index], 'budget.categoryIds[$index]'),
      ],
      createdAtUtc: _readDateTime(json, 'createdAtUtc', 'budget.createdAtUtc'),
      updatedAtUtc: _readDateTime(json, 'updatedAtUtc', 'budget.updatedAtUtc'),
    );
  }

  final int id;
  final BudgetPeriodKind periodKind;
  final int startDay;
  final int endDay;
  final String name;
  final String normalizedName;
  final int limitAmount;
  final List<int> categoryIds;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  Map<String, Object?> toJson() => {
    'id': id,
    'periodKind': periodKind.name,
    'startDay': startDay,
    'endDay': endDay,
    'name': name,
    'normalizedName': normalizedName,
    'limitAmount': limitAmount,
    'categoryIds': categoryIds,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
  };
}

class BackupAccount {
  const BackupAccount({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.type,
    this.balanceGroup = AccountBalanceGroup.primary,
    required this.isArchived,
    required this.createdAtUtc,
  });

  factory BackupAccount.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const {
      'id',
      'name',
      'normalizedName',
      'type',
      'balanceGroup',
      'isArchived',
      'createdAtUtc',
    }, 'account');
    return BackupAccount(
      id: _readInt(json, 'id', 'account.id'),
      name: _readString(json, 'name', 'account.name'),
      normalizedName: _readString(
        json,
        'normalizedName',
        'account.normalizedName',
      ),
      type: _readEnum(json, 'type', 'account.type', AccountType.values),
      balanceGroup: _readEnum(
        json,
        'balanceGroup',
        'account.balanceGroup',
        AccountBalanceGroup.values,
      ),
      isArchived: _readBool(json, 'isArchived', 'account.isArchived'),
      createdAtUtc: _readDateTime(json, 'createdAtUtc', 'account.createdAtUtc'),
    );
  }

  final int id;
  final String name;
  final String normalizedName;
  final AccountType type;
  final AccountBalanceGroup balanceGroup;
  final bool isArchived;
  final DateTime createdAtUtc;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'normalizedName': normalizedName,
    'type': type.name,
    'balanceGroup': balanceGroup.name,
    'isArchived': isArchived,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
  };
}

BackupAccount _readLegacyBackupAccount(Map<String, Object?> json) {
  _requireExactKeys(json, const {
    'id',
    'name',
    'normalizedName',
    'type',
    'isArchived',
    'createdAtUtc',
  }, 'account');
  return BackupAccount(
    id: _readInt(json, 'id', 'account.id'),
    name: _readString(json, 'name', 'account.name'),
    normalizedName: _readString(
      json,
      'normalizedName',
      'account.normalizedName',
    ),
    type: _readEnum(json, 'type', 'account.type', AccountType.values),
    balanceGroup: AccountBalanceGroup.primary,
    isArchived: _readBool(json, 'isArchived', 'account.isArchived'),
    createdAtUtc: _readDateTime(json, 'createdAtUtc', 'account.createdAtUtc'),
  );
}

Map<String, Object?> _writeLegacyBackupAccount(BackupAccount account) => {
  'id': account.id,
  'name': account.name,
  'normalizedName': account.normalizedName,
  'type': account.type.name,
  'isArchived': account.isArchived,
  'createdAtUtc': account.createdAtUtc.toUtc().toIso8601String(),
};

class BackupCategory {
  const BackupCategory({
    required this.id,
    required this.parentId,
    required this.kind,
    required this.name,
    required this.normalizedName,
    required this.iconKey,
    required this.isArchived,
    required this.sortOrder,
    required this.systemKey,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  factory BackupCategory.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const {
      'id',
      'parentId',
      'kind',
      'name',
      'normalizedName',
      'iconKey',
      'isArchived',
      'sortOrder',
      'systemKey',
      'createdAtUtc',
      'updatedAtUtc',
    }, 'category');
    return BackupCategory(
      id: _readInt(json, 'id', 'category.id'),
      parentId: _readNullableInt(json, 'parentId', 'category.parentId'),
      kind: _readEnum(json, 'kind', 'category.kind', CategoryKind.values),
      name: _readString(json, 'name', 'category.name'),
      normalizedName: _readString(
        json,
        'normalizedName',
        'category.normalizedName',
      ),
      iconKey: _readString(json, 'iconKey', 'category.iconKey'),
      isArchived: _readBool(json, 'isArchived', 'category.isArchived'),
      sortOrder: _readInt(json, 'sortOrder', 'category.sortOrder'),
      systemKey: _readNullableString(json, 'systemKey', 'category.systemKey'),
      createdAtUtc: _readDateTime(
        json,
        'createdAtUtc',
        'category.createdAtUtc',
      ),
      updatedAtUtc: _readDateTime(
        json,
        'updatedAtUtc',
        'category.updatedAtUtc',
      ),
    );
  }

  final int id;
  final int? parentId;
  final CategoryKind kind;
  final String name;
  final String normalizedName;
  final String iconKey;
  final bool isArchived;
  final int sortOrder;
  final String? systemKey;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  Map<String, Object?> toJson() => {
    'id': id,
    'parentId': parentId,
    'kind': kind.name,
    'name': name,
    'normalizedName': normalizedName,
    'iconKey': iconKey,
    'isArchived': isArchived,
    'sortOrder': sortOrder,
    'systemKey': systemKey,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
  };
}

class BackupLedgerEntry {
  BackupLedgerEntry({
    required this.id,
    required this.kind,
    required this.accountId,
    required this.destinationAccountId,
    required this.amount,
    required Iterable<BackupLedgerAllocation> allocations,
    required this.note,
    required this.occurredDay,
    required this.createdAtUtc,
  }) : allocations = List.unmodifiable(allocations);

  final int id;
  final EntryKind kind;
  final int accountId;
  final int? destinationAccountId;
  final int amount;
  final List<BackupLedgerAllocation> allocations;
  final String note;
  final int occurredDay;
  final DateTime createdAtUtc;
}

class BackupLedgerAllocation {
  const BackupLedgerAllocation({
    required this.position,
    required this.categoryId,
    required this.amount,
  });

  final int position;
  final int categoryId;
  final int amount;

  Map<String, Object?> toJson() => {
    'position': position,
    'categoryId': categoryId,
    'amount': amount,
  };
}

BackupLedgerEntry _readBackupLedgerEntryV1(Map<String, Object?> json) {
  _requireExactKeys(json, const {
    'id',
    'kind',
    'accountId',
    'destinationAccountId',
    'amount',
    'categoryId',
    'note',
    'occurredDay',
    'createdAtUtc',
  }, 'ledgerEntry');
  final amount = _readInt(json, 'amount', 'ledgerEntry.amount');
  final categoryId = _readNullableInt(
    json,
    'categoryId',
    'ledgerEntry.categoryId',
  );
  return BackupLedgerEntry(
    id: _readInt(json, 'id', 'ledgerEntry.id'),
    kind: _readEnum(json, 'kind', 'ledgerEntry.kind', EntryKind.values),
    accountId: _readInt(json, 'accountId', 'ledgerEntry.accountId'),
    destinationAccountId: _readNullableInt(
      json,
      'destinationAccountId',
      'ledgerEntry.destinationAccountId',
    ),
    amount: amount,
    allocations: categoryId == null
        ? const []
        : [
            BackupLedgerAllocation(
              position: 0,
              categoryId: categoryId,
              amount: amount,
            ),
          ],
    note: _readString(json, 'note', 'ledgerEntry.note'),
    occurredDay: _readInt(json, 'occurredDay', 'ledgerEntry.occurredDay'),
    createdAtUtc: _readDateTime(
      json,
      'createdAtUtc',
      'ledgerEntry.createdAtUtc',
    ),
  );
}

BackupLedgerEntry _readBackupLedgerEntryV2(Map<String, Object?> json) {
  _requireExactKeys(json, const {
    'id',
    'kind',
    'accountId',
    'destinationAccountId',
    'amount',
    'allocations',
    'note',
    'occurredDay',
    'createdAtUtc',
  }, 'ledgerEntry');
  return BackupLedgerEntry(
    id: _readInt(json, 'id', 'ledgerEntry.id'),
    kind: _readEnum(json, 'kind', 'ledgerEntry.kind', EntryKind.values),
    accountId: _readInt(json, 'accountId', 'ledgerEntry.accountId'),
    destinationAccountId: _readNullableInt(
      json,
      'destinationAccountId',
      'ledgerEntry.destinationAccountId',
    ),
    amount: _readInt(json, 'amount', 'ledgerEntry.amount'),
    allocations: _readObjectList(
      json,
      'allocations',
      'ledgerEntry.allocations',
      _readBackupLedgerAllocation,
      maximumLength: maxBackupLedgerAllocationsPerEntry,
    ),
    note: _readString(json, 'note', 'ledgerEntry.note'),
    occurredDay: _readInt(json, 'occurredDay', 'ledgerEntry.occurredDay'),
    createdAtUtc: _readDateTime(
      json,
      'createdAtUtc',
      'ledgerEntry.createdAtUtc',
    ),
  );
}

BackupLedgerAllocation _readBackupLedgerAllocation(Map<String, Object?> json) {
  _requireExactKeys(json, const {
    'position',
    'categoryId',
    'amount',
  }, 'allocation');
  return BackupLedgerAllocation(
    position: _readInt(json, 'position', 'allocation.position'),
    categoryId: _readInt(json, 'categoryId', 'allocation.categoryId'),
    amount: _readInt(json, 'amount', 'allocation.amount'),
  );
}

List<BackupLedgerEntry> _readBackupLedgerEntriesV2(Map<String, Object?> data) {
  final values = _readList(
    data,
    'ledgerEntries',
    'data.ledgerEntries',
    maximumLength: maxBackupLedgerRecords,
  );
  final entries = <BackupLedgerEntry>[];
  var allocationCount = 0;
  for (var index = 0; index < values.length; index++) {
    final entry = _readBackupLedgerEntryV2(
      _asObject(values[index], 'data.ledgerEntries[$index]'),
    );
    allocationCount += entry.allocations.length;
    if (allocationCount > maxBackupLedgerAllocationRecords) {
      throw const BackupFormatException(
        'Jumlah allocation pada backup melebihi batas versi aplikasi ini.',
      );
    }
    entries.add(entry);
  }
  return entries;
}

List<BackupBudget> _readBackupBudgetsV4(Map<String, Object?> data) {
  final values = _readList(
    data,
    'budgets',
    'data.budgets',
    maximumLength: maxBackupBudgetRecords,
  );
  final budgets = <BackupBudget>[];
  var categoryCount = 0;
  for (var index = 0; index < values.length; index++) {
    final budget = BackupBudget.fromJson(
      _asObject(values[index], 'data.budgets[$index]'),
    );
    categoryCount += budget.categoryIds.length;
    if (categoryCount > maxBackupBudgetCategoryRecords) {
      throw const BackupFormatException(
        'Jumlah kategori anggaran pada backup melebihi batas versi aplikasi ini.',
      );
    }
    budgets.add(budget);
  }
  return budgets;
}

Map<String, Object?> _writeBackupLedgerEntryV1(BackupLedgerEntry entry) => {
  'id': entry.id,
  'kind': entry.kind.name,
  'accountId': entry.accountId,
  'destinationAccountId': entry.destinationAccountId,
  'amount': entry.amount,
  'categoryId': entry.allocations.isEmpty
      ? null
      : entry.allocations.single.categoryId,
  'note': entry.note,
  'occurredDay': entry.occurredDay,
  'createdAtUtc': entry.createdAtUtc.toUtc().toIso8601String(),
};

Map<String, Object?> _writeBackupLedgerEntryV2(BackupLedgerEntry entry) => {
  'id': entry.id,
  'kind': entry.kind.name,
  'accountId': entry.accountId,
  'destinationAccountId': entry.destinationAccountId,
  'amount': entry.amount,
  'allocations': entry.allocations.map((item) => item.toJson()).toList(),
  'note': entry.note,
  'occurredDay': entry.occurredDay,
  'createdAtUtc': entry.createdAtUtc.toUtc().toIso8601String(),
};

bool _isSupportedBackupVersionSchemaPair(
  int backupVersion,
  int databaseSchemaVersion,
) =>
    (backupVersion == 1 && databaseSchemaVersion == 3) ||
    (backupVersion == 2 && databaseSchemaVersion == 4) ||
    (backupVersion == 3 && databaseSchemaVersion == 5) ||
    (backupVersion == 4 && databaseSchemaVersion == 6);

void _requireBackupVersionSchemaPair(
  int backupVersion,
  int databaseSchemaVersion,
) {
  if (!_isSupportedBackupVersionSchemaPair(
    backupVersion,
    databaseSchemaVersion,
  )) {
    throw const BackupFormatException(
      'Pasangan versi backup dan database tidak didukung.',
    );
  }
}

void validateBackupDocument(
  BackupDocument document, {
  bool requireSequenceHeadroom = true,
}) {
  if (document.format != warasArtaBackupFormat) {
    _invalid('File bukan backup Waras Arta.');
  }
  if (!_isSupportedBackupVersionSchemaPair(
    document.backupVersion,
    document.databaseSchemaVersion,
  )) {
    _invalid('Pasangan versi backup dan database tidak didukung.');
  }
  if (!document.createdAtUtc.isUtc) {
    _invalid('Waktu pembuatan backup harus menggunakan UTC.');
  }
  final allocationCount = document.ledgerEntries.fold<int>(
    0,
    (count, entry) => count + entry.allocations.length,
  );
  final budgetCategoryCount = document.budgets.fold<int>(
    0,
    (count, budget) => count + budget.categoryIds.length,
  );
  if (document.accounts.length > maxBackupAccountRecords ||
      document.categories.length > maxBackupCategoryRecords ||
      document.ledgerEntries.length > maxBackupLedgerRecords ||
      allocationCount > maxBackupLedgerAllocationRecords ||
      document.budgets.length > maxBackupBudgetRecords ||
      budgetCategoryCount > maxBackupBudgetCategoryRecords) {
    _invalid('Jumlah data pada backup melebihi batas versi aplikasi ini.');
  }
  if (document.backupVersion < 4 &&
      (document.budgets.isNotEmpty || document.sequences.budgets != 0)) {
    _invalid('Backup versi lama tidak boleh memuat anggaran.');
  }

  final accountIds = <int>{};
  final normalizedAccountNames = <String>{};
  for (final account in document.accounts) {
    _positiveId(account.id, 'ID rekening');
    if (!accountIds.add(account.id)) _invalid('ID rekening duplikat.');
    _canonicalName(account.name, account.normalizedName, 'Nama rekening');
    if (document.backupVersion < 3 &&
        account.balanceGroup != AccountBalanceGroup.primary) {
      _invalid('Backup versi lama hanya mendukung rekening Saldo utama.');
    }
    if (!normalizedAccountNames.add(account.normalizedName)) {
      _invalid('Nama rekening duplikat.');
    }
    _utcTimestamp(account.createdAtUtc, 'Waktu pembuatan rekening');
  }
  final categoriesById = <int, BackupCategory>{};
  final systemKeys = <String>{};
  final uniqueRootNames = <String>{};
  final uniqueChildNames = <String>{};
  for (final category in document.categories) {
    _positiveId(category.id, 'ID kategori');
    if (categoriesById.containsKey(category.id)) {
      _invalid('ID kategori duplikat.');
    }
    categoriesById[category.id] = category;
    _canonicalName(category.name, category.normalizedName, 'Nama kategori');
    if (!categoryIconKeys.contains(category.iconKey)) {
      _invalid('Ikon kategori tidak dikenal.');
    }
    if (category.sortOrder < 0 || category.sortOrder > 1000000) {
      _invalid('Urutan kategori tidak valid.');
    }
    final systemKey = category.systemKey;
    if (systemKey != null) {
      if (systemKey.trim() != systemKey ||
          systemKey.isEmpty ||
          systemKey.length > 80) {
        _invalid('Identitas kategori bawaan tidak valid.');
      }
      if (!systemKeys.add(systemKey)) {
        _invalid('Identitas kategori bawaan duplikat.');
      }
    }
    _utcTimestamp(category.createdAtUtc, 'Waktu pembuatan kategori');
    _utcTimestamp(category.updatedAtUtc, 'Waktu perubahan kategori');
    final parentId = category.parentId;
    final uniqueKey = parentId == null
        ? '${category.kind.name}|${category.normalizedName}'
        : '$parentId|${category.normalizedName}';
    final added = parentId == null
        ? uniqueRootNames.add(uniqueKey)
        : uniqueChildNames.add(uniqueKey);
    if (!added) _invalid('Nama kategori duplikat pada kelompok yang sama.');
  }

  final childCount = <int, int>{};
  final effectiveLeaves = {for (final kind in CategoryKind.values) kind: 0};
  for (final category in document.categories) {
    final parentId = category.parentId;
    if (parentId == null) continue;
    if (parentId == category.id) {
      _invalid('Kategori tidak boleh menjadi induknya sendiri.');
    }
    final parent = categoriesById[parentId];
    if (parent == null || parent.parentId != null) {
      _invalid('Induk subkategori tidak valid.');
    }
    if (parent.kind != category.kind) {
      _invalid('Jenis subkategori tidak sama dengan kelompoknya.');
    }
    childCount.update(parentId, (value) => value + 1, ifAbsent: () => 1);
    if (!parent.isArchived && !category.isArchived) {
      effectiveLeaves.update(category.kind, (value) => value + 1);
    }
  }
  for (final category in document.categories) {
    if (category.parentId == null && (childCount[category.id] ?? 0) == 0) {
      _invalid('Kelompok kategori harus memiliki subkategori.');
    }
  }
  for (final kind in CategoryKind.values) {
    if ((effectiveLeaves[kind] ?? 0) < 1) {
      _invalid('Backup harus memiliki subkategori ${kind.name} yang aktif.');
    }
  }

  final budgetIds = <int>{};
  final uniqueBudgetNames = <String>{};
  final intervalsByCategory = <int, List<_BackupBudgetInterval>>{};
  for (final budget in document.budgets) {
    _positiveId(budget.id, 'ID anggaran');
    if (!budgetIds.add(budget.id)) _invalid('ID anggaran duplikat.');
    _canonicalName(budget.name, budget.normalizedName, 'Nama anggaran');
    if (budget.limitAmount < 1 || budget.limitAmount > maxAmount) {
      _invalid('Batas anggaran tidak valid.');
    }
    try {
      BudgetPeriod(
        kind: budget.periodKind,
        startDay: budget.startDay,
        endDay: budget.endDay,
      );
    } on BudgetValidationException {
      _invalid('Periode anggaran tidak valid.');
    }
    final uniqueNameKey =
        '${budget.startDay}|${budget.endDay}|${budget.normalizedName}';
    if (!uniqueBudgetNames.add(uniqueNameKey)) {
      _invalid('Nama anggaran duplikat pada periode yang sama.');
    }
    _utcTimestamp(budget.createdAtUtc, 'Waktu pembuatan anggaran');
    _utcTimestamp(budget.updatedAtUtc, 'Waktu perubahan anggaran');
    if (budget.updatedAtUtc.isBefore(budget.createdAtUtc)) {
      _invalid('Waktu perubahan anggaran tidak valid.');
    }
    if (budget.categoryIds.isEmpty ||
        budget.categoryIds.length > maxBackupCategoriesPerBudget) {
      _invalid('Anggaran wajib memiliki subkategori pengeluaran.');
    }
    var previousCategoryId = 0;
    for (final categoryId in budget.categoryIds) {
      if (categoryId <= previousCategoryId) {
        _invalid('Urutan subkategori anggaran tidak valid.');
      }
      previousCategoryId = categoryId;
      final category = categoriesById[categoryId];
      if (category == null ||
          category.parentId == null ||
          category.kind != CategoryKind.expense) {
        _invalid('Subkategori anggaran tidak valid.');
      }
      intervalsByCategory
          .putIfAbsent(categoryId, () => [])
          .add(
            _BackupBudgetInterval(
              budgetId: budget.id,
              startDay: budget.startDay,
              endDay: budget.endDay,
            ),
          );
    }
  }
  for (final intervals in intervalsByCategory.values) {
    intervals.sort((left, right) {
      final start = left.startDay.compareTo(right.startDay);
      if (start != 0) return start;
      final end = left.endDay.compareTo(right.endDay);
      if (end != 0) return end;
      return left.budgetId.compareTo(right.budgetId);
    });
    for (var index = 1; index < intervals.length; index++) {
      if (intervals[index].startDay <= intervals[index - 1].endDay) {
        _invalid('Subkategori berada pada anggaran yang periodenya beririsan.');
      }
    }
  }

  final ledgerIds = <int>{};
  final balances = {for (final account in document.accounts) account.id: 0};
  for (final entry in document.ledgerEntries) {
    _positiveId(entry.id, 'ID transaksi');
    if (!ledgerIds.add(entry.id)) _invalid('ID transaksi duplikat.');
    if (!accountIds.contains(entry.accountId)) {
      _invalid('Rekening transaksi tidak ditemukan.');
    }
    if (entry.note.length > 500) {
      _invalid('Catatan transaksi melebihi 500 karakter.');
    }
    if (!_isValidOccurredDay(entry.occurredDay)) {
      _invalid('Tanggal transaksi tidak valid.');
    }
    _utcTimestamp(entry.createdAtUtc, 'Waktu pembuatan transaksi');

    switch (entry.kind) {
      case EntryKind.income:
      case EntryKind.expense:
        if (entry.amount < 1 || entry.amount > maxAmount) {
          _invalid('Nominal transaksi tidak valid.');
        }
        final allocations = entry.allocations;
        final maximumAllocations = document.backupVersion == 1
            ? 1
            : maxBackupLedgerAllocationsPerEntry;
        if (entry.destinationAccountId != null ||
            allocations.isEmpty ||
            allocations.length > maximumAllocations) {
          _invalid('Relasi transaksi pemasukan/pengeluaran tidak valid.');
        }
        final expectedKind = entry.kind == EntryKind.income
            ? CategoryKind.income
            : CategoryKind.expense;
        final allocationCategoryIds = <int>{};
        var allocationTotal = 0;
        for (var index = 0; index < allocations.length; index++) {
          final allocation = allocations[index];
          if (allocation.position != index) {
            _invalid('Posisi allocation transaksi tidak valid.');
          }
          if (!allocationCategoryIds.add(allocation.categoryId)) {
            _invalid('Subkategori allocation transaksi duplikat.');
          }
          if (allocation.amount < 1 || allocation.amount > maxAmount) {
            _invalid('Nominal allocation transaksi tidak valid.');
          }
          allocationTotal += allocation.amount;
          if (allocationTotal > maxAmount) {
            _invalid('Total allocation transaksi tidak valid.');
          }
          final category = categoriesById[allocation.categoryId];
          if (category == null ||
              category.parentId == null ||
              category.kind != expectedKind) {
            _invalid('Subkategori transaksi tidak valid.');
          }
        }
        if (allocationTotal != entry.amount) {
          _invalid('Total allocation tidak sama dengan nominal transaksi.');
        }
        balances.update(
          entry.accountId,
          (value) =>
              value +
              (entry.kind == EntryKind.income ? entry.amount : -entry.amount),
        );
      case EntryKind.transfer:
        final destinationId = entry.destinationAccountId;
        if (entry.amount < 1 || entry.amount > maxAmount) {
          _invalid('Nominal transfer tidak valid.');
        }
        if (destinationId == null ||
            destinationId == entry.accountId ||
            !accountIds.contains(destinationId) ||
            entry.allocations.isNotEmpty) {
          _invalid('Relasi transfer tidak valid.');
        }
        balances.update(entry.accountId, (value) => value - entry.amount);
        balances.update(destinationId, (value) => value + entry.amount);
      case EntryKind.adjustment:
        if (entry.amount == 0 ||
            entry.amount < -maxAmount ||
            entry.amount > maxAmount) {
          _invalid('Nominal penyesuaian saldo tidak valid.');
        }
        if (entry.destinationAccountId != null ||
            entry.allocations.isNotEmpty) {
          _invalid('Relasi penyesuaian saldo tidak valid.');
        }
        balances.update(entry.accountId, (value) => value + entry.amount);
    }
  }

  for (final account in document.accounts) {
    if (account.isArchived && balances[account.id] != 0) {
      _invalid('Rekening arsip harus memiliki saldo Rp0.');
    }
  }

  _sequence(
    document.sequences.accounts,
    _maxId(accountIds),
    'rekening',
    requireHeadroom: requireSequenceHeadroom,
  );
  _sequence(
    document.sequences.categories,
    _maxId(categoriesById.keys),
    'kategori',
    requireHeadroom: requireSequenceHeadroom,
  );
  _sequence(
    document.sequences.ledgerEntries,
    _maxId(ledgerIds),
    'transaksi',
    requireHeadroom: requireSequenceHeadroom,
  );
  _sequence(
    document.sequences.budgets,
    _maxId(budgetIds),
    'anggaran',
    requireHeadroom: requireSequenceHeadroom,
  );
}

class _BackupBudgetInterval {
  const _BackupBudgetInterval({
    required this.budgetId,
    required this.startDay,
    required this.endDay,
  });

  final int budgetId;
  final int startDay;
  final int endDay;
}

class BackupException implements Exception {
  const BackupException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class BackupFormatException extends BackupException {
  const BackupFormatException(super.message, {super.cause});
}

class BackupValidationException extends BackupException {
  const BackupValidationException(super.message, {super.cause});
}

class BackupPersistenceException extends BackupException {
  const BackupPersistenceException(super.message, {super.cause});
}

Never _invalid(String message) => throw BackupValidationException(message);

void _requireExactKeys(
  Map<String, Object?> json,
  Set<String> expected,
  String path,
) {
  if (json.length != expected.length ||
      !json.keys.toSet().containsAll(expected)) {
    throw BackupFormatException(
      'Struktur $path tidak cocok dengan versi backup ini.',
    );
  }
}

void _positiveId(int value, String field) {
  if (value < 1 || value > maxBackupRecordId) {
    _invalid('$field tidak valid.');
  }
}

void _canonicalName(String name, String normalizedName, String field) {
  final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned != name || cleaned.isEmpty || cleaned.length > 80) {
    _invalid('$field tidak valid.');
  }
  if (normalizedName != cleaned.toLowerCase()) {
    _invalid('Normalisasi $field tidak valid.');
  }
}

void _utcTimestamp(DateTime value, String field) {
  if (!value.isUtc) _invalid('$field harus menggunakan UTC.');
}

void _sequence(
  int sequence,
  int maximumId,
  String label, {
  required bool requireHeadroom,
}) {
  final maximumSequence = requireHeadroom
      ? maxBackupRecordId - minimumRestoredIdHeadroom
      : maxBackupRecordId;
  if (sequence < maximumId || sequence > maximumSequence) {
    _invalid('Urutan ID $label tidak valid.');
  }
}

int _maxId(Iterable<int> values) {
  var result = 0;
  for (final value in values) {
    if (value > result) result = value;
  }
  return result;
}

bool _isValidOccurredDay(int value) {
  if (value < 20000101 || value > 99991231) return false;
  final year = value ~/ 10000;
  final month = value ~/ 100 % 100;
  final day = value % 100;
  final parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}

Map<String, Object?> _readObject(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    try {
      return value.cast<String, Object?>();
    } catch (_) {
      // Report one stable format error below.
    }
  }
  throw BackupFormatException('Field $path tidak valid.');
}

List<T> _readObjectList<T>(
  Map<String, Object?> json,
  String key,
  String path,
  T Function(Map<String, Object?>) decode, {
  required int maximumLength,
}) {
  final value = _readList(json, key, path, maximumLength: maximumLength);
  return [
    for (var index = 0; index < value.length; index++)
      decode(_asObject(value[index], '$path[$index]')),
  ];
}

List<Object?> _readList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maximumLength,
}) {
  final value = json[key];
  if (value is! List) {
    throw BackupFormatException('Field $path tidak valid.');
  }
  if (value.length > maximumLength) {
    throw BackupFormatException(
      'Jumlah data pada $path melebihi batas versi aplikasi ini.',
    );
  }
  return value;
}

Map<String, Object?> _asObject(Object? value, String path) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    try {
      return value.cast<String, Object?>();
    } catch (_) {
      // Report one stable format error below.
    }
  }
  throw BackupFormatException('Field $path tidak valid.');
}

String _readString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is String) return value;
  throw BackupFormatException('Field $path tidak valid.');
}

String? _readNullableString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw BackupFormatException('Field $path tidak valid.');
}

int _readInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is int) return value;
  throw BackupFormatException('Field $path tidak valid.');
}

int _asInt(Object? value, String path) {
  if (value is int) return value;
  throw BackupFormatException('Field $path tidak valid.');
}

int? _readNullableInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null || value is int) return value as int?;
  throw BackupFormatException('Field $path tidak valid.');
}

bool _readBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is bool) return value;
  throw BackupFormatException('Field $path tidak valid.');
}

DateTime _readDateTime(Map<String, Object?> json, String key, String path) {
  final raw = _readString(json, key, path);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw BackupFormatException('Field $path tidak valid.');
  }
  return parsed.toUtc();
}

T _readEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  String path,
  List<T> values,
) {
  final raw = _readString(json, key, path);
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw BackupFormatException('Field $path tidak dikenal.');
}
