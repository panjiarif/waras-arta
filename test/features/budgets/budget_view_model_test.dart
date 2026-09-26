import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/app/providers.dart';
import 'package:waras_arta/domain/budget.dart';
import 'package:waras_arta/features/budgets/view_models/budget_view_model.dart';
import 'package:waras_arta/features/calendar/view_models/calendar_view_model.dart';

import 'fake_budget_repository.dart';

void main() {
  late FakeBudgetRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(id: 1),
        fakeBudgetProgress(id: 2, period: BudgetPeriod.yearly(2026)),
        fakeBudgetProgress(id: 3, period: BudgetPeriod.monthly(2026, 1)),
      ],
    );
    container = ProviderContainer(
      overrides: [
        budgetRepositoryProvider.overrideWithValue(repository),
        currentDateProvider.overrideWithValue(DateTime(2026, 2, 10, 23, 30)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await repository.dispose();
  });

  test('uses selected month and applies period kind filters', () async {
    final subscription = container.listen(
      filteredBudgetListProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    expect(container.read(budgetReferenceDayProvider), 20260210);

    var filter = container.read(budgetListQueryProvider);
    var snapshot = await container.read(budgetSnapshotProvider(filter).future);
    expect(filter.windowStartDay, 20260201);
    expect(filter.windowEndDay, 20260228);
    expect(filter.usageThroughDay, 20260210);
    expect(snapshot.items.map((item) => item.budget.id), [1, 2]);

    container
        .read(budgetFilterProvider.notifier)
        .selectKind(BudgetPeriodKind.monthly);
    filter = container.read(budgetListQueryProvider);
    snapshot = await container.read(budgetSnapshotProvider(filter).future);
    expect(snapshot.items.map((item) => item.budget.id), [1]);

    container.read(budgetFilterProvider.notifier).showPreviousPeriod();
    filter = container.read(budgetListQueryProvider);
    snapshot = await container.read(budgetSnapshotProvider(filter).future);
    expect(filter.windowStartDay, 20260101);
    expect(filter.usageThroughDay, 20260131);
    expect(snapshot.items.map((item) => item.budget.id), [3]);

    container
        .read(budgetFilterProvider.notifier)
        .selectKind(BudgetPeriodKind.yearly);
    filter = container.read(budgetListQueryProvider);
    snapshot = await container.read(budgetSnapshotProvider(filter).future);
    expect(filter.windowStartDay, 20260101);
    expect(filter.windowEndDay, 20261231);
    expect(filter.periodKind, BudgetPeriodKind.yearly);
    expect(snapshot.items.map((item) => item.budget.id), [2]);
  });

  test('follows date rollover until the user browses history', () {
    final controller = container.read(budgetFilterProvider.notifier);

    controller.refreshToday(today: DateTime(2026, 3, 1));
    expect(container.read(budgetFilterProvider).selectedMonth, 3);
    expect(container.read(budgetFilterProvider).followsCurrentPeriod, isTrue);

    controller.showPreviousPeriod();
    expect(container.read(budgetFilterProvider).selectedMonth, 2);
    controller.refreshToday(today: DateTime(2026, 4, 1));
    expect(container.read(budgetFilterProvider).selectedMonth, 2);
    expect(container.read(budgetFilterProvider).followsCurrentPeriod, isFalse);
  });

  test('actions forward validated drafts and expose a settled state', () async {
    final actions = container.read(budgetActionsProvider.notifier);
    final id = await actions.createBudget(
      BudgetDraft(
        period: BudgetPeriod.monthly(2026, 2),
        name: 'Transportasi',
        limitAmount: 500000,
        categoryIds: {12},
      ),
    );

    expect(id, 4);
    expect(repository.createdDraft?.categoryIds, {12});
    expect(container.read(budgetActionsProvider).isSaving, isFalse);
    expect(container.read(budgetActionsProvider).error, isNull);

    final updated = await actions.updateBudget(
      id!,
      BudgetUpdateDraft(
        name: 'Transportasi rutin',
        limitAmount: 600000,
        categoryIds: {12},
      ),
    );
    expect(updated, isTrue);
    expect(repository.updatedId, id);

    final deleted = await actions.deleteBudget(id);
    expect(deleted, isTrue);
    expect(repository.deletedId, id);
  });

  test('copy action creates independent budgets and settles state', () async {
    repository.items.removeWhere((item) => item.budget.id == 1);
    final actions = container.read(budgetActionsProvider.notifier);

    final copied = await actions.copyMonthlyBudgets(
      source: BudgetPeriod.monthly(2026, 1),
      target: BudgetPeriod.monthly(2026, 2),
    );

    expect(copied, 1);
    expect(repository.copiedSource, BudgetPeriod.monthly(2026, 1));
    expect(repository.copiedTarget, BudgetPeriod.monthly(2026, 2));
    expect(
      repository.items
          .singleWhere(
            (item) => item.budget.period == BudgetPeriod.monthly(2026, 2),
          )
          .budget
          .id,
      4,
    );
    expect(container.read(budgetActionsProvider).isSaving, isFalse);
    expect(container.read(budgetActionsProvider).error, isNull);
  });
}
