import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/domain/budget.dart';

void main() {
  final validationError = isA<BudgetValidationException>();

  group('civil day validation', () {
    test('accepts Gregorian leap dates and supported boundaries', () {
      for (final day in [
        20000101,
        20000229,
        20001231,
        20040229,
        24000229,
        99991231,
      ]) {
        expect(isValidCivilDay(day), isTrue, reason: '$day should be valid');
      }

      final first = civilDayToDateTime(20000101);
      final last = civilDayToDateTime(99991231);
      expect((first.year, first.month, first.day), (2000, 1, 1));
      expect((last.year, last.month, last.day), (9999, 12, 31));
      expect(dateTimeToCivilDay(DateTime.utc(2000, 2, 29, 23, 59)), 20000229);
    });

    test(
      'rejects non-Gregorian dates and values outside 2000 through 9999',
      () {
        for (final day in [
          19991231,
          100000000,
          20000001,
          20001301,
          20000100,
          20010229,
          20250229,
          21000229,
          20260431,
        ]) {
          expect(
            isValidCivilDay(day),
            isFalse,
            reason: '$day should be invalid',
          );
          expect(() => civilDayToDateTime(day), throwsA(validationError));
        }
      },
    );
  });

  group('canonical periods', () {
    test('monthly covers exactly one full calendar month', () {
      final leapFebruary = BudgetPeriod.monthly(2000, 2);
      final lastSupportedMonth = BudgetPeriod.monthly(9999, 12);

      expect(leapFebruary.kind, BudgetPeriodKind.monthly);
      expect(leapFebruary.startDay, 20000201);
      expect(leapFebruary.endDay, 20000229);
      expect(lastSupportedMonth.startDay, 99991201);
      expect(lastSupportedMonth.endDay, 99991231);
      expect(
        BudgetPeriod(
          kind: BudgetPeriodKind.monthly,
          startDay: 20240901,
          endDay: 20240930,
        ),
        BudgetPeriod.monthly(2024, 9),
      );

      for (final create in <BudgetPeriod Function()>[
        () => BudgetPeriod(
          kind: BudgetPeriodKind.monthly,
          startDay: 20240902,
          endDay: 20240930,
        ),
        () => BudgetPeriod(
          kind: BudgetPeriodKind.monthly,
          startDay: 20240901,
          endDay: 20241001,
        ),
        () => BudgetPeriod(
          kind: BudgetPeriodKind.monthly,
          startDay: 20240201,
          endDay: 20240228,
        ),
        () => BudgetPeriod.monthly(1999, 12),
        () => BudgetPeriod.monthly(10000, 1),
        () => BudgetPeriod.monthly(2024, 0),
        () => BudgetPeriod.monthly(2024, 13),
      ]) {
        expect(create, throwsA(validationError));
      }
    });

    test('yearly covers exactly January 1 through December 31', () {
      final first = BudgetPeriod.yearly(2000);
      final last = BudgetPeriod.yearly(9999);

      expect(first.kind, BudgetPeriodKind.yearly);
      expect((first.startDay, first.endDay), (20000101, 20001231));
      expect((last.startDay, last.endDay), (99990101, 99991231));
      expect(
        BudgetPeriod(
          kind: BudgetPeriodKind.yearly,
          startDay: 20240101,
          endDay: 20241231,
        ),
        BudgetPeriod.yearly(2024),
      );

      for (final create in <BudgetPeriod Function()>[
        () => BudgetPeriod(
          kind: BudgetPeriodKind.yearly,
          startDay: 20240102,
          endDay: 20241231,
        ),
        () => BudgetPeriod(
          kind: BudgetPeriodKind.yearly,
          startDay: 20240101,
          endDay: 20251231,
        ),
        () => BudgetPeriod.yearly(1999),
        () => BudgetPeriod.yearly(10000),
      ]) {
        expect(create, throwsA(validationError));
      }
    });

    test('custom supports one day, cross-year, and full supported range', () {
      final oneDay = BudgetPeriod.custom(20240229, 20240229);
      final crossYear = BudgetPeriod.custom(20241230, 20250102);
      final fullRange = BudgetPeriod.custom(20000101, 99991231);

      expect(oneDay.kind, BudgetPeriodKind.custom);
      expect((oneDay.startDay, oneDay.endDay), (20240229, 20240229));
      expect((crossYear.startDay, crossYear.endDay), (20241230, 20250102));
      expect((fullRange.startDay, fullRange.endDay), (20000101, 99991231));
      expect(
        () => BudgetPeriod.custom(20250102, 20241230),
        throwsA(validationError),
      );
      expect(
        () => BudgetPeriod.custom(20250229, 20250301),
        throwsA(validationError),
      );
    });
  });

  test('overlap, containment, and temporal status include both endpoints', () {
    final period = BudgetPeriod.custom(20240110, 20240120);

    expect(period.contains(20240110), isTrue);
    expect(period.contains(20240120), isTrue);
    expect(period.contains(20240109), isFalse);
    expect(period.overlaps(BudgetPeriod.custom(20240101, 20240110)), isTrue);
    expect(period.overlaps(BudgetPeriod.custom(20240120, 20240201)), isTrue);
    expect(period.overlaps(BudgetPeriod.custom(20240101, 20240109)), isFalse);
    expect(period.overlaps(BudgetPeriod.custom(20240121, 20240201)), isFalse);

    expect(period.statusAt(20240109), BudgetTemporalStatus.upcoming);
    expect(period.statusAt(20240110), BudgetTemporalStatus.active);
    expect(period.statusAt(20240120), BudgetTemporalStatus.active);
    expect(period.statusAt(20240121), BudgetTemporalStatus.history);
    expect(() => period.statusAt(20240230), throwsA(validationError));
  });

  test('usage status changes at 80, 100, and over 100 percent', () {
    final at79 = _progress(id: 1, limit: 100, spent: 79);
    final at80 = _progress(id: 2, limit: 100, spent: 80);
    final at100 = _progress(id: 3, limit: 100, spent: 100);
    final over100 = _progress(id: 4, limit: 100, spent: 125);

    expect(at79.usageStatus, BudgetUsageStatus.normal);
    expect(at79.remainingAmount, 21);
    expect(at79.exceededAmount, 0);
    expect(at79.actualRatio, closeTo(.79, .000001));
    expect(at79.visualRatio, closeTo(.79, .000001));

    expect(at80.usageStatus, BudgetUsageStatus.nearLimit);
    expect(at80.remainingAmount, 20);
    expect(at80.visualRatio, closeTo(.8, .000001));

    expect(at100.usageStatus, BudgetUsageStatus.exhausted);
    expect(at100.remainingAmount, 0);
    expect(at100.exceededAmount, 0);
    expect(at100.actualRatio, 1);
    expect(at100.visualRatio, 1);

    expect(over100.usageStatus, BudgetUsageStatus.exceeded);
    expect(over100.remainingAmount, 0);
    expect(over100.exceededAmount, 25);
    expect(over100.actualRatio, 1.25);
    expect(over100.visualRatio, 1);
  });

  test('collections are immutable and range groups aggregate exact values', () {
    const category = BudgetCategoryRef(
      id: 10,
      name: 'Umum',
      parentName: 'Makan',
      iconKey: 'restaurant',
      isArchived: false,
      parentIsArchived: false,
    );
    final categorySource = <BudgetCategoryRef>[category];
    final details = BudgetDetails(
      budget: _budget(id: 1, limit: 100),
      categories: categorySource,
    );
    categorySource.clear();
    expect(details.categories, [category]);
    expect(() => details.categories.add(category), throwsUnsupportedError);

    final selectedIds = <int>[10, 11, 10];
    final draft = BudgetDraft(
      period: BudgetPeriod.monthly(2024, 1),
      name: 'Makan',
      limitAmount: 100,
      categoryIds: selectedIds,
    );
    final update = BudgetUpdateDraft(
      name: 'Makan',
      limitAmount: 100,
      categoryIds: selectedIds,
    );
    selectedIds.add(12);
    expect(draft.categoryIds, {10, 11});
    expect(update.categoryIds, {10, 11});
    expect(() => draft.categoryIds.add(12), throwsUnsupportedError);
    expect(() => update.categoryIds.clear(), throwsUnsupportedError);

    final first = _progress(id: 1, limit: 100, spent: 80);
    final second = _progress(
      id: 2,
      limit: 50,
      spent: 80,
      period: BudgetPeriod.custom(20240101, 20240131),
    );
    final nextMonth = _progress(
      id: 3,
      limit: 200,
      spent: 20,
      period: BudgetPeriod.monthly(2024, 2),
    );
    final source = <BudgetProgress>[first, second, nextMonth];
    final snapshot = BudgetListSnapshot.fromItems(source);
    source.clear();

    expect(snapshot.items, hasLength(3));
    expect(snapshot.groups, hasLength(2));
    final january = snapshot.groups.first;
    expect((january.startDay, january.endDay), (20240101, 20240131));
    expect(january.items.map((item) => item.budget.id), [1, 2]);
    expect(january.totalLimit, 150);
    expect(january.totalSpent, 160);
    expect(january.remainingAmount, 0);
    expect(january.exceededAmount, 10);
    expect(january.countForStatus(BudgetUsageStatus.nearLimit), 1);
    expect(january.countForStatus(BudgetUsageStatus.exceeded), 1);
    expect(snapshot.groups.last.remainingAmount, 180);
    expect(() => snapshot.items.clear(), throwsUnsupportedError);
    expect(() => snapshot.groups.clear(), throwsUnsupportedError);
    expect(() => january.items.clear(), throwsUnsupportedError);
  });

  test('filter equality, hash, and copyWith include every field', () {
    const first = BudgetListFilter(
      temporalStatus: BudgetTemporalStatus.active,
      periodKind: BudgetPeriodKind.monthly,
      referenceDay: 20240115,
    );
    const same = BudgetListFilter(
      temporalStatus: BudgetTemporalStatus.active,
      periodKind: BudgetPeriodKind.monthly,
      referenceDay: 20240115,
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    final filters = <BudgetListFilter>{first};
    filters.add(same);
    expect(filters, hasLength(1));
    expect(first.copyWith(), same);
    expect(
      first.copyWith(temporalStatus: BudgetTemporalStatus.history),
      isNot(same),
    );
    expect(first.copyWith(periodKind: BudgetPeriodKind.yearly), isNot(same));
    expect(first.copyWith(referenceDay: 20240116), isNot(same));
    expect(first.copyWith(clearPeriodKind: true).periodKind, isNull);
  });

  test('budget names are canonicalized and normalized consistently', () {
    expect(canonicalizeBudgetName('  Dana\n  darurat  '), 'Dana darurat');
    expect(normalizeBudgetName('  Dana\n  DARURAT  '), 'dana darurat');
    expect(() => canonicalizeBudgetName('   '), throwsA(validationError));
    expect(() => canonicalizeBudgetName('a' * 81), throwsA(validationError));
  });
}

Budget _budget({required int id, required int limit, BudgetPeriod? period}) =>
    Budget(
      id: id,
      period: period ?? BudgetPeriod.monthly(2024, 1),
      name: 'Anggaran $id',
      normalizedName: 'anggaran $id',
      limitAmount: limit,
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

BudgetProgress _progress({
  required int id,
  required int limit,
  required int spent,
  BudgetPeriod? period,
}) => BudgetProgress(
  budget: _budget(id: id, limit: limit, period: period),
  categories: const [],
  spentAmount: spent,
);
