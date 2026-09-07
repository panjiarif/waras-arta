import 'finance.dart';

const warasArtaBackupFormat = 'waras-arta-backup';
const oldestSupportedBackupVersion = 1;
const currentBackupVersion = 1;
const maxBackupAccountRecords = 2000;
const maxBackupCategoryRecords = 20000;
const maxBackupLedgerRecords = 100000;
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
  }) : createdAtUtc = createdAtUtc.toUtc(),
       accounts = List.unmodifiable(accounts),
       categories = List.unmodifiable(categories),
       ledgerEntries = List.unmodifiable(ledgerEntries);

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
    final document = BackupDocument(
      format: format,
      backupVersion: backupVersion,
      databaseSchemaVersion: _readInt(
        json,
        'databaseSchemaVersion',
        'databaseSchemaVersion',
      ),
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
      ledgerEntries: _readObjectList(
        data,
        'ledgerEntries',
        'data.ledgerEntries',
        BackupLedgerEntry.fromJson,
        maximumLength: maxBackupLedgerRecords,
      ),
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

  BackupSummary get summary => BackupSummary(
    createdAtUtc: createdAtUtc,
    accountCount: accounts.length,
    archivedAccountCount: accounts.where((item) => item.isArchived).length,
    categoryCount: categories.length,
    archivedCategoryCount: categories.where((item) => item.isArchived).length,
    ledgerEntryCount: ledgerEntries.length,
  );

  Map<String, Object?> toJson() => {
    'format': format,
    'backupVersion': backupVersion,
    'databaseSchemaVersion': databaseSchemaVersion,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'sequences': sequences.toJson(),
    'data': {
      'accounts': accounts.map((item) => item.toJson()).toList(),
      'categories': categories.map((item) => item.toJson()).toList(),
      'ledgerEntries': ledgerEntries.map((item) => item.toJson()).toList(),
    },
  };
}

class BackupSummary {
  const BackupSummary({
    required this.createdAtUtc,
    required this.accountCount,
    required this.archivedAccountCount,
    required this.categoryCount,
    required this.archivedCategoryCount,
    required this.ledgerEntryCount,
  });

  final DateTime createdAtUtc;
  final int accountCount;
  final int archivedAccountCount;
  final int categoryCount;
  final int archivedCategoryCount;
  final int ledgerEntryCount;
}

class BackupSequences {
  const BackupSequences({
    required this.accounts,
    required this.categories,
    required this.ledgerEntries,
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
    );
  }

  final int accounts;
  final int categories;
  final int ledgerEntries;

  Map<String, Object?> toJson() => {
    'accounts': accounts,
    'categories': categories,
    'ledgerEntries': ledgerEntries,
  };
}

class BackupAccount {
  const BackupAccount({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.type,
    required this.isArchived,
    required this.createdAtUtc,
  });

  factory BackupAccount.fromJson(Map<String, Object?> json) {
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
      isArchived: _readBool(json, 'isArchived', 'account.isArchived'),
      createdAtUtc: _readDateTime(json, 'createdAtUtc', 'account.createdAtUtc'),
    );
  }

  final int id;
  final String name;
  final String normalizedName;
  final AccountType type;
  final bool isArchived;
  final DateTime createdAtUtc;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'normalizedName': normalizedName,
    'type': type.name,
    'isArchived': isArchived,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
  };
}

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
  const BackupLedgerEntry({
    required this.id,
    required this.kind,
    required this.accountId,
    required this.destinationAccountId,
    required this.amount,
    required this.categoryId,
    required this.note,
    required this.occurredDay,
    required this.createdAtUtc,
  });

  factory BackupLedgerEntry.fromJson(Map<String, Object?> json) {
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
      categoryId: _readNullableInt(
        json,
        'categoryId',
        'ledgerEntry.categoryId',
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

  final int id;
  final EntryKind kind;
  final int accountId;
  final int? destinationAccountId;
  final int amount;
  final int? categoryId;
  final String note;
  final int occurredDay;
  final DateTime createdAtUtc;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'accountId': accountId,
    'destinationAccountId': destinationAccountId,
    'amount': amount,
    'categoryId': categoryId,
    'note': note,
    'occurredDay': occurredDay,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
  };
}

void validateBackupDocument(
  BackupDocument document, {
  bool requireSequenceHeadroom = true,
}) {
  if (document.format != warasArtaBackupFormat) {
    _invalid('File bukan backup Waras Arta.');
  }
  if (document.backupVersion < oldestSupportedBackupVersion ||
      document.backupVersion > currentBackupVersion) {
    _invalid('Versi backup belum didukung oleh aplikasi ini.');
  }
  if (document.databaseSchemaVersion < 1) {
    _invalid('Versi database pada backup tidak valid.');
  }
  if (!document.createdAtUtc.isUtc) {
    _invalid('Waktu pembuatan backup harus menggunakan UTC.');
  }
  if (document.accounts.length > maxBackupAccountRecords ||
      document.categories.length > maxBackupCategoryRecords ||
      document.ledgerEntries.length > maxBackupLedgerRecords) {
    _invalid('Jumlah data pada backup melebihi batas versi aplikasi ini.');
  }

  final accountIds = <int>{};
  final normalizedAccountNames = <String>{};
  for (final account in document.accounts) {
    _positiveId(account.id, 'ID rekening');
    if (!accountIds.add(account.id)) _invalid('ID rekening duplikat.');
    _canonicalName(account.name, account.normalizedName, 'Nama rekening');
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
        if (entry.destinationAccountId != null || entry.categoryId == null) {
          _invalid('Relasi transaksi pemasukan/pengeluaran tidak valid.');
        }
        final category = categoriesById[entry.categoryId];
        final expectedKind = entry.kind == EntryKind.income
            ? CategoryKind.income
            : CategoryKind.expense;
        if (category == null ||
            category.parentId == null ||
            category.kind != expectedKind) {
          _invalid('Subkategori transaksi tidak valid.');
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
            entry.categoryId != null) {
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
        if (entry.destinationAccountId != null || entry.categoryId != null) {
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
  final value = json[key];
  if (value is! List) {
    throw BackupFormatException('Field $path tidak valid.');
  }
  if (value.length > maximumLength) {
    throw BackupFormatException(
      'Jumlah data pada $path melebihi batas versi aplikasi ini.',
    );
  }
  return [
    for (var index = 0; index < value.length; index++)
      decode(_asObject(value[index], '$path[$index]')),
  ];
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
