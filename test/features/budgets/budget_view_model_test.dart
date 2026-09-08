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
        fakeBudgetProgress(id: 2, period: BudgetPeriod.yearly(2027)),
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

  test(
    'uses the local civil day and applies temporal and kind filters',
    () async {
      final subscription = container.listen(
        filteredBudgetListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      expect(container.read(budgetReferenceDayProvider), 20260210);

      var filter = container.read(budgetListQueryProvider);
      var snapshot = await container.read(
        budgetSnapshotProvider(filter).future,
      );
      expect(snapshot.items.map((item) => item.budget.id), [1]);

      container
          .read(budgetFilterProvider.notifier)
          .selectStatus(BudgetTemporalStatus.upcoming);
      filter = container.read(budgetListQueryProvider);
      snapshot = await container.read(budgetSnapshotProvider(filter).future);
      expect(snapshot.items.map((item) => item.budget.id), [2]);

      container
          .read(budgetFilterProvider.notifier)
          .selectKind(BudgetPeriodKind.monthly);
      filter = container.read(budgetListQueryProvider);
      snapshot = await container.read(budgetSnapshotProvider(filter).future);
      expect(snapshot.items, isEmpty);
    },
  );

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

    expect(id, 3);
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
}
