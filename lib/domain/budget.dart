import 'dart:collection';

enum BudgetPeriodKind { monthly, yearly, custom }

extension BudgetPeriodKindLabel on BudgetPeriodKind {
  String get label => switch (this) {
    BudgetPeriodKind.monthly => 'Bulanan',
    BudgetPeriodKind.yearly => 'Tahunan',
    BudgetPeriodKind.custom => 'Kustom',
  };
}

enum BudgetTemporalStatus { active, upcoming, history }

extension BudgetTemporalStatusLabel on BudgetTemporalStatus {
  String get label => switch (this) {
    BudgetTemporalStatus.active => 'Aktif',
    BudgetTemporalStatus.upcoming => 'Mendatang',
    BudgetTemporalStatus.history => 'Riwayat',
  };
}

enum BudgetUsageStatus { normal, nearLimit, exhausted, exceeded }

extension BudgetUsageStatusLabel on BudgetUsageStatus {
  String get label => switch (this) {
    BudgetUsageStatus.normal => 'Dalam batas',
    BudgetUsageStatus.nearLimit => 'Hampir habis',
    BudgetUsageStatus.exhausted => 'Anggaran habis',
    BudgetUsageStatus.exceeded => 'Melebihi batas',
  };
}

class BudgetPeriod {
  factory BudgetPeriod({
    required BudgetPeriodKind kind,
    required int startDay,
    required int endDay,
  }) {
    if (!isValidCivilDay(startDay) || !isValidCivilDay(endDay)) {
      throw const BudgetValidationException('Tanggal anggaran tidak valid.');
    }
    if (startDay > endDay) {
      throw const BudgetValidationException(
        'Tanggal mulai tidak boleh setelah tanggal selesai.',
      );
    }
    switch (kind) {
      case BudgetPeriodKind.monthly:
        final start = civilDayToDateTime(startDay);
        final expectedEnd = DateTime(start.year, start.month + 1, 0);
        if (start.day != 1 || endDay != dateTimeToCivilDay(expectedEnd)) {
          throw const BudgetValidationException(
            'Periode bulanan harus mencakup satu bulan kalender penuh.',
          );
        }
      case BudgetPeriodKind.yearly:
        final start = civilDayToDateTime(startDay);
        if (start.month != 1 ||
            start.day != 1 ||
            endDay != start.year * 10000 + 1231) {
          throw const BudgetValidationException(
            'Periode tahunan harus mencakup satu tahun kalender penuh.',
          );
        }
      case BudgetPeriodKind.custom:
        break;
    }
    return BudgetPeriod._(kind: kind, startDay: startDay, endDay: endDay);
  }

  factory BudgetPeriod.monthly(int year, int month) {
    if (year < 2000 || year > 9999 || month < 1 || month > 12) {
      throw const BudgetValidationException('Bulan anggaran tidak valid.');
    }
    return BudgetPeriod(
      kind: BudgetPeriodKind.monthly,
      startDay: year * 10000 + month * 100 + 1,
      endDay: dateTimeToCivilDay(DateTime(year, month + 1, 0)),
    );
  }

  factory BudgetPeriod.yearly(int year) {
    if (year < 2000 || year > 9999) {
      throw const BudgetValidationException('Tahun anggaran tidak valid.');
    }
    return BudgetPeriod(
      kind: BudgetPeriodKind.yearly,
      startDay: year * 10000 + 101,
      endDay: year * 10000 + 1231,
    );
  }

  factory BudgetPeriod.custom(int startDay, int endDay) => BudgetPeriod(
    kind: BudgetPeriodKind.custom,
    startDay: startDay,
    endDay: endDay,
  );

  const BudgetPeriod._({
    required this.kind,
    required this.startDay,
    required this.endDay,
  });

  final BudgetPeriodKind kind;
  final int startDay;
  final int endDay;

  bool contains(int day) => startDay <= day && day <= endDay;

  bool overlaps(BudgetPeriod other) =>
      startDay <= other.endDay && other.startDay <= endDay;

  BudgetTemporalStatus statusAt(int referenceDay) {
    if (!isValidCivilDay(referenceDay)) {
      throw const BudgetValidationException('Tanggal acuan tidak valid.');
    }
    if (endDay < referenceDay) return BudgetTemporalStatus.history;
    if (startDay > referenceDay) return BudgetTemporalStatus.upcoming;
    return BudgetTemporalStatus.active;
  }

  @override
  bool operator ==(Object other) =>
      other is BudgetPeriod &&
      kind == other.kind &&
      startDay == other.startDay &&
      endDay == other.endDay;

  @override
  int get hashCode => Object.hash(kind, startDay, endDay);
}

class Budget {
  const Budget({
    required this.id,
    required this.period,
    required this.name,
    required this.normalizedName,
    required this.limitAmount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final BudgetPeriod period;
  final String name;
  final String normalizedName;
  final int limitAmount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class BudgetCategoryRef {
  const BudgetCategoryRef({
    required this.id,
    required this.name,
    required this.parentName,
    required this.iconKey,
    required this.isArchived,
    required this.parentIsArchived,
  });

  final int id;
  final String name;
  final String parentName;
  final String iconKey;
  final bool isArchived;
  final bool parentIsArchived;

  bool get effectiveIsArchived => isArchived || parentIsArchived;

  String get displayName => '$parentName · $name';
}

class BudgetDetails {
  BudgetDetails({
    required this.budget,
    required Iterable<BudgetCategoryRef> categories,
  }) : categories = List.unmodifiable(categories);

  final Budget budget;
  final List<BudgetCategoryRef> categories;
}

class BudgetProgress extends BudgetDetails {
  BudgetProgress({
    required super.budget,
    required super.categories,
    required this.spentAmount,
  });

  final int spentAmount;

  int get remainingAmount {
    final value = budget.limitAmount - spentAmount;
    return value > 0 ? value : 0;
  }

  int get exceededAmount {
    final value = spentAmount - budget.limitAmount;
    return value > 0 ? value : 0;
  }

  double get actualRatio => spentAmount / budget.limitAmount;

  double get visualRatio => actualRatio.clamp(0.0, 1.0);

  BudgetUsageStatus get usageStatus {
    if (spentAmount > budget.limitAmount) return BudgetUsageStatus.exceeded;
    if (spentAmount == budget.limitAmount) return BudgetUsageStatus.exhausted;
    if (spentAmount * 5 >= budget.limitAmount * 4) {
      return BudgetUsageStatus.nearLimit;
    }
    return BudgetUsageStatus.normal;
  }
}

class BudgetConflict {
  const BudgetConflict({
    required this.categoryId,
    required this.budgetId,
    required this.budgetName,
    required this.period,
  });

  final int categoryId;
  final int budgetId;
  final String budgetName;
  final BudgetPeriod period;
}

class BudgetListFilter {
  const BudgetListFilter({
    required this.temporalStatus,
    required this.referenceDay,
    this.periodKind,
  });

  final BudgetTemporalStatus temporalStatus;
  final BudgetPeriodKind? periodKind;
  final int referenceDay;

  BudgetListFilter copyWith({
    BudgetTemporalStatus? temporalStatus,
    BudgetPeriodKind? periodKind,
    bool clearPeriodKind = false,
    int? referenceDay,
  }) => BudgetListFilter(
    temporalStatus: temporalStatus ?? this.temporalStatus,
    periodKind: clearPeriodKind ? null : periodKind ?? this.periodKind,
    referenceDay: referenceDay ?? this.referenceDay,
  );

  @override
  bool operator ==(Object other) =>
      other is BudgetListFilter &&
      temporalStatus == other.temporalStatus &&
      periodKind == other.periodKind &&
      referenceDay == other.referenceDay;

  @override
  int get hashCode => Object.hash(temporalStatus, periodKind, referenceDay);
}

class BudgetRangeGroup {
  BudgetRangeGroup({
    required this.startDay,
    required this.endDay,
    required Iterable<BudgetProgress> items,
  }) : items = List.unmodifiable(items);

  final int startDay;
  final int endDay;
  final List<BudgetProgress> items;

  int get totalLimit =>
      items.fold(0, (total, item) => total + item.budget.limitAmount);
  int get totalSpent =>
      items.fold(0, (total, item) => total + item.spentAmount);
  int get remainingAmount {
    final value = totalLimit - totalSpent;
    return value > 0 ? value : 0;
  }

  int get exceededAmount {
    final value = totalSpent - totalLimit;
    return value > 0 ? value : 0;
  }

  int countForStatus(BudgetUsageStatus status) =>
      items.where((item) => item.usageStatus == status).length;
}

class BudgetListSnapshot {
  BudgetListSnapshot({
    required Iterable<BudgetProgress> items,
    required Iterable<BudgetRangeGroup> groups,
  }) : items = List.unmodifiable(items),
       groups = List.unmodifiable(groups);

  factory BudgetListSnapshot.fromItems(Iterable<BudgetProgress> source) {
    final items = List<BudgetProgress>.unmodifiable(source);
    final grouped = <(int, int), List<BudgetProgress>>{};
    for (final item in items) {
      final period = item.budget.period;
      grouped.putIfAbsent((period.startDay, period.endDay), () => []).add(item);
    }
    return BudgetListSnapshot(
      items: items,
      groups: grouped.entries.map(
        (entry) => BudgetRangeGroup(
          startDay: entry.key.$1,
          endDay: entry.key.$2,
          items: entry.value,
        ),
      ),
    );
  }

  final List<BudgetProgress> items;
  final List<BudgetRangeGroup> groups;
}

class BudgetDraft {
  BudgetDraft({
    required this.period,
    required this.name,
    required this.limitAmount,
    required Iterable<int> categoryIds,
  }) : categoryIds = UnmodifiableSetView(Set.of(categoryIds));

  final BudgetPeriod period;
  final String name;
  final int limitAmount;
  final Set<int> categoryIds;
}

class BudgetUpdateDraft {
  BudgetUpdateDraft({
    required this.name,
    required this.limitAmount,
    required Iterable<int> categoryIds,
  }) : categoryIds = UnmodifiableSetView(Set.of(categoryIds));

  final String name;
  final int limitAmount;
  final Set<int> categoryIds;
}

String canonicalizeBudgetName(String value) {
  final canonical = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (canonical.isEmpty || canonical.length > 80) {
    throw const BudgetValidationException(
      'Nama anggaran wajib diisi maksimal 80 karakter.',
    );
  }
  return canonical;
}

String normalizeBudgetName(String value) =>
    canonicalizeBudgetName(value).toLowerCase();

int dateTimeToCivilDay(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;

DateTime civilDayToDateTime(int value) {
  if (!isValidCivilDay(value)) {
    throw const BudgetValidationException('Tanggal anggaran tidak valid.');
  }
  return DateTime(value ~/ 10000, value ~/ 100 % 100, value % 100);
}

bool isValidCivilDay(int value) {
  if (value < 20000101 || value > 99991231) return false;
  final year = value ~/ 10000;
  final month = value ~/ 100 % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1) return false;
  final days = switch (month) {
    2 => _isLeapYear(year) ? 29 : 28,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };
  return day <= days;
}

bool _isLeapYear(int year) =>
    year % 400 == 0 || (year % 4 == 0 && year % 100 != 0);

class BudgetValidationException implements Exception {
  const BudgetValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
