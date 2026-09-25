import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/budget.dart';
import '../../ledger/views/form_widgets.dart';
import '../view_models/budget_view_model.dart';
import 'budget_widgets.dart';

class BudgetListScreen extends ConsumerStatefulWidget {
  const BudgetListScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<BudgetListScreen> createState() => _BudgetListScreenState();
}

class _BudgetListScreenState extends ConsumerState<BudgetListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.embedded) {
        ref.read(budgetFilterProvider.notifier).reset();
      }
      ref.read(budgetActionsProvider.notifier).clearError();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(budgetFilterProvider);
    final budgets = ref.watch(filteredBudgetListProvider);
    final upcoming = ref.watch(upcomingBudgetSummaryProvider);
    final actions = ref.watch(budgetActionsProvider);
    final stackStatus =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;

    final content = SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.embedded) ...[
                      Semantics(
                        header: true,
                        child: Text(
                          'Anggaran',
                          key: const Key('budget-tab-heading'),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!stackStatus) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Atur batas pengeluaran dan pantau pemakaiannya.',
                        ),
                        const SizedBox(height: 16),
                      ] else
                        const SizedBox(height: 8),
                    ],
                    SegmentedButton<BudgetTemporalStatus>(
                      key: const Key('budget-status-filter'),
                      direction: stackStatus ? Axis.vertical : Axis.horizontal,
                      expandedInsets: stackStatus ? null : EdgeInsets.zero,
                      segments: [
                        for (final status in BudgetTemporalStatus.values)
                          ButtonSegment(
                            value: status,
                            label: Text(
                              status.label,
                              key: ValueKey('budget-status-${status.name}'),
                            ),
                          ),
                      ],
                      selected: {selection.temporalStatus},
                      showSelectedIcon: false,
                      onSelectionChanged: actions.isSaving
                          ? null
                          : (values) => ref
                                .read(budgetFilterProvider.notifier)
                                .selectStatus(values.single),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: const Key('budget-kind-filter'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: actions.isSaving
                          ? null
                          : () => _showKindFilter(selection.periodKind),
                      child: Row(
                        children: [
                          const Icon(Icons.filter_list),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Jenis: '
                              '${selection.periodKind?.label ?? 'Semua'}',
                            ),
                          ),
                          const Icon(Icons.expand_more),
                        ],
                      ),
                    ),
                    if (actions.error != null) ...[
                      const SizedBox(height: 10),
                      FormMessage(actions.error!, isError: true),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: budgets.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => BudgetLoadState(
                    message: 'Daftar anggaran belum dapat dimuat. Data di perangkat tidak diubah.',
                    onRetry: () => ref.invalidate(
                      budgetSnapshotProvider(ref.read(budgetListQueryProvider)),
                    ),
                  ),
                  data: (snapshot) => snapshot.items.isEmpty
                      ? _BudgetEmptyState(
                          selection: selection,
                          upcoming: upcoming,
                        )
                      : _BudgetGroupList(snapshot: snapshot),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola anggaran')),
      floatingActionButton: const BudgetAddButton(),
      body: content,
    );
  }

  Future<void> _showKindFilter(BudgetPeriodKind? selected) async {
    final option = await showModalBottomSheet<_BudgetKindOption>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Filter jenis anggaran',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final option in _BudgetKindOption.values)
            ListTile(
              key: ValueKey('budget-kind-${option.name}'),
              selected: option.kind == selected,
              leading: Icon(
                option.kind == selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(option.label),
              onTap: () => Navigator.pop(context, option),
            ),
        ],
      ),
    );
    if (option != null && mounted) {
      ref.read(budgetFilterProvider.notifier).selectKind(option.kind);
    }
  }
}

class BudgetAddButton extends ConsumerWidget {
  const BudgetAddButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaving = ref.watch(
      budgetActionsProvider.select((state) => state.isSaving),
    );
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;

    void openForm() {
      ref.read(budgetActionsProvider.notifier).clearError();
      context.push('/budgets/new');
    }

    if (compact) {
      return FloatingActionButton(
        key: const Key('add-budget'),
        tooltip: 'Tambah anggaran',
        onPressed: isSaving ? null : openForm,
        child: const Icon(Icons.add),
      );
    }
    return FloatingActionButton.extended(
      key: const Key('add-budget'),
      onPressed: isSaving ? null : openForm,
      icon: const Icon(Icons.add),
      label: const Text('Tambah anggaran'),
    );
  }
}

enum _BudgetKindOption { all, monthly, yearly, custom }

extension on _BudgetKindOption {
  BudgetPeriodKind? get kind => switch (this) {
    _BudgetKindOption.all => null,
    _BudgetKindOption.monthly => BudgetPeriodKind.monthly,
    _BudgetKindOption.yearly => BudgetPeriodKind.yearly,
    _BudgetKindOption.custom => BudgetPeriodKind.custom,
  };

  String get label => kind?.label ?? 'Semua';
}

class _BudgetGroupList extends StatelessWidget {
  const _BudgetGroupList({required this.snapshot});

  final BudgetListSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final group in snapshot.groups) {
      rows.add(BudgetRangeHeader(group: group));
      rows.add(const SizedBox(height: 8));
      for (final progress in group.items) {
        rows.add(
          BudgetProgressCard(
            progress: progress,
            onTap: () => context.push('/budgets/${progress.budget.id}'),
          ),
        );
        rows.add(const SizedBox(height: 8));
      }
      rows.add(const SizedBox(height: 8));
    }

    return ListView(
      key: const PageStorageKey('budget-list'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
      children: rows,
    );
  }
}

class _BudgetEmptyState extends ConsumerWidget {
  const _BudgetEmptyState({required this.selection, required this.upcoming});

  final BudgetFilterSelection selection;
  final AsyncValue<BudgetListSnapshot> upcoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKindFilter = selection.periodKind != null;
    final upcomingItems =
        upcoming.asData?.value.items ?? const <BudgetProgress>[];
    final nearestUpcoming = upcomingItems.isEmpty ? null : upcomingItems.first;
    final title = hasKindFilter
        ? 'Tidak ada hasil untuk filter ini'
        : switch (selection.temporalStatus) {
            BudgetTemporalStatus.active => 'Belum ada anggaran aktif hari ini',
            BudgetTemporalStatus.upcoming => 'Belum ada anggaran mendatang',
            BudgetTemporalStatus.history => 'Belum ada riwayat anggaran',
          };
    final description = hasKindFilter
        ? 'Coba tampilkan semua jenis anggaran.'
        : selection.temporalStatus == BudgetTemporalStatus.active &&
              nearestUpcoming != null
        ? 'Anggaran terdekat: ${nearestUpcoming.budget.name}, '
              '${budgetPeriodLabel(nearestUpcoming.budget.period)}.'
        : 'Buat anggaran untuk membatasi pengeluaran tanpa mengubah saldo rekening.';

    return ListView(
      key: const PageStorageKey('budget-empty-list'),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
      children: [
        Icon(
          Icons.savings_outlined,
          size: 54,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          key: const Key('budget-empty-title'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(description, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        if (hasKindFilter)
          FilledButton.tonal(
            key: const Key('budget-reset-filters'),
            onPressed: () =>
                ref.read(budgetFilterProvider.notifier).selectKind(null),
            child: const Text('Lihat semua jenis'),
          )
        else if (selection.temporalStatus == BudgetTemporalStatus.active &&
            nearestUpcoming != null)
          FilledButton.tonal(
            key: const Key('view-upcoming-budgets'),
            onPressed: () => ref
                .read(budgetFilterProvider.notifier)
                .selectStatus(BudgetTemporalStatus.upcoming),
            child: const Text('Lihat mendatang'),
          )
        else
          FilledButton.icon(
            key: const Key('create-first-budget'),
            onPressed: () => context.push('/budgets/new'),
            icon: const Icon(Icons.add),
            label: const Text('Buat anggaran'),
          ),
      ],
    );
  }
}
