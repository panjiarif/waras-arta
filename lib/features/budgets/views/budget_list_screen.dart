import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
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
    final copyAvailability = ref.watch(budgetMonthlyCopyAvailabilityProvider);
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
                    _BudgetPeriodNavigator(
                      selection: selection,
                      enabled: !actions.isSaving,
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
                  data: (snapshot) =>
                      snapshot.items.isEmpty &&
                          copyAvailability.asData?.value == null
                      ? _BudgetEmptyState(selection: selection)
                      : _BudgetGroupList(
                          snapshot: snapshot,
                          selection: selection,
                          usageThroughDay: ref
                              .read(budgetListQueryProvider)
                              .usageThroughDay,
                          copyContext: copyAvailability.asData?.value,
                          copying: actions.isSaving,
                          onCopy: _confirmCopy,
                        ),
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

  Future<void> _confirmCopy(BudgetMonthlyCopyContext copy) async {
    ref.read(budgetActionsProvider.notifier).clearError();
    final sourceLabel = formatMonth(civilDayToDateTime(copy.source.startDay));
    final targetLabel = formatMonth(civilDayToDateTime(copy.target.startDay));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salin anggaran bulanan?'),
        content: Text(
          'Salin ${copy.itemCount} anggaran dari $sourceLabel ke '
          '$targetLabel? Hasil salinan berdiri sendiri sehingga perubahan '
          'setelahnya tidak mengubah bulan lain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('confirm-copy-monthly-budgets'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salin anggaran'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final copied = await ref
        .read(budgetActionsProvider.notifier)
        .copyMonthlyBudgets(source: copy.source, target: copy.target);
    if (!mounted || copied == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$copied anggaran berhasil disalin.')),
    );
  }
}

class _BudgetPeriodNavigator extends ConsumerWidget {
  const _BudgetPeriodNavigator({
    required this.selection,
    required this.enabled,
  });

  final BudgetFilterSelection selection;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = civilDayToDateTime(ref.watch(budgetReferenceDayProvider));
    final yearly = selection.usesYearNavigator;
    final label = yearly
        ? '${selection.selectedYear}'
        : formatMonth(
            DateTime(selection.selectedYear, selection.selectedMonth),
          );
    final canGoPrevious = yearly
        ? selection.selectedYear > 2000
        : selection.selectedYear > 2000 || selection.selectedMonth > 1;
    final canGoNext = yearly
        ? selection.selectedYear < today.year
        : selection.selectedYear * 12 + selection.selectedMonth <
              today.year * 12 + today.month;
    final unit = yearly ? 'tahun' : 'bulan';
    final previousAction = enabled && canGoPrevious
        ? () => ref.read(budgetFilterProvider.notifier).showPreviousPeriod()
        : null;
    final nextAction = enabled && canGoNext
        ? () => ref.read(budgetFilterProvider.notifier).showNextPeriod()
        : null;

    return Semantics(
      key: const Key('budget-period-navigator'),
      container: true,
      explicitChildNodes: true,
      header: true,
      liveRegion: true,
      label: 'Periode anggaran $label',
      child: Row(
        children: [
          Semantics(
            key: const Key('previous-budget-period-semantics'),
            container: true,
            button: true,
            enabled: previousAction != null,
            label: '$unit sebelumnya',
            onTap: previousAction,
            child: ExcludeSemantics(
              child: IconButton(
                key: const Key('previous-budget-period'),
                tooltip: '$unit sebelumnya',
                onPressed: previousAction,
                icon: const Icon(Icons.chevron_left),
              ),
            ),
          ),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                label,
                key: const Key('budget-period-label'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Semantics(
            key: const Key('next-budget-period-semantics'),
            container: true,
            button: true,
            enabled: nextAction != null,
            label: '$unit berikutnya',
            onTap: nextAction,
            child: ExcludeSemantics(
              child: IconButton(
                key: const Key('next-budget-period'),
                tooltip: '$unit berikutnya',
                onPressed: nextAction,
                icon: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _budgetCreateLocation(BudgetFilterSelection selection) {
  final kind = selection.periodKind ?? BudgetPeriodKind.monthly;
  return '/budgets/new?kind=${kind.name}'
      '&year=${selection.selectedYear}'
      '&month=${selection.selectedMonth}';
}

class BudgetAddButton extends ConsumerWidget {
  const BudgetAddButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaving = ref.watch(
      budgetActionsProvider.select((state) => state.isSaving),
    );
    final selection = ref.watch(budgetFilterProvider);
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;

    void openForm() {
      ref.read(budgetActionsProvider.notifier).clearError();
      context.push(_budgetCreateLocation(selection));
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
  const _BudgetGroupList({
    required this.snapshot,
    required this.selection,
    required this.usageThroughDay,
    required this.copyContext,
    required this.copying,
    required this.onCopy,
  });

  final BudgetListSnapshot snapshot;
  final BudgetFilterSelection selection;
  final int usageThroughDay;
  final BudgetMonthlyCopyContext? copyContext;
  final bool copying;
  final ValueChanged<BudgetMonthlyCopyContext> onCopy;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (copyContext != null) {
      rows.add(
        _MonthlyCopySection(
          context: copyContext!,
          copying: copying,
          onCopy: () => onCopy(copyContext!),
        ),
      );
      rows.add(const SizedBox(height: 12));
    }
    for (final group in snapshot.groups) {
      final showCutoff =
          group.periodKind != BudgetPeriodKind.monthly &&
          usageThroughDay >= group.startDay &&
          usageThroughDay < group.endDay;
      rows.add(
        BudgetPeriodSection(
          group: group,
          usageThroughLabel: showCutoff
              ? 'Pemakaian s.d. '
                    '${formatDate(civilDayToDateTime(usageThroughDay))}'
              : null,
          onOpenBudget: (id) => context.push('/budgets/$id'),
        ),
      );
      rows.add(const SizedBox(height: 12));
    }

    final kind = selection.periodKind?.name ?? 'all';
    final period = selection.usesYearNavigator
        ? '${selection.selectedYear}'
        : '${selection.selectedYear}-${selection.selectedMonth}';
    return ListView(
      key: PageStorageKey('budget-list-$kind-$period'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
      children: rows,
    );
  }
}

class _MonthlyCopySection extends StatelessWidget {
  const _MonthlyCopySection({
    required this.context,
    required this.copying,
    required this.onCopy,
  });

  final BudgetMonthlyCopyContext context;
  final bool copying;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext buildContext) {
    final sourceLabel = formatMonth(
      civilDayToDateTime(context.source.startDay),
    );
    final targetLabel = formatMonth(
      civilDayToDateTime(context.target.startDay),
    );
    return Card(
      key: const Key('budget-monthly-copy-section'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'BULANAN · ${targetLabel.toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Belum ada anggaran bulanan. Gunakan ${context.itemCount} '
              'anggaran dari $sourceLabel sebagai titik awal.',
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('copy-previous-month-budgets'),
              onPressed: copying ? null : onCopy,
              icon: const Icon(Icons.content_copy_outlined),
              label: const Text('Salin anggaran bulan sebelumnya'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetEmptyState extends ConsumerWidget {
  const _BudgetEmptyState({required this.selection});

  final BudgetFilterSelection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKindFilter = selection.periodKind != null;
    final periodLabel = selection.usesYearNavigator
        ? '${selection.selectedYear}'
        : formatMonth(
            DateTime(selection.selectedYear, selection.selectedMonth),
          );
    final kindLabel = selection.periodKind?.label.toLowerCase();
    final title = kindLabel == null
        ? 'Belum ada anggaran untuk $periodLabel'
        : 'Belum ada anggaran $kindLabel untuk $periodLabel';

    return ListView(
      key: PageStorageKey(
        'budget-empty-list-${selection.periodKind?.name ?? 'all'}-'
        '${selection.selectedYear}-${selection.selectedMonth}',
      ),
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
        const Text(
          'Buat anggaran untuk membatasi pengeluaran tanpa mengubah saldo rekening.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (hasKindFilter)
          FilledButton.tonal(
            key: const Key('budget-reset-filters'),
            onPressed: () =>
                ref.read(budgetFilterProvider.notifier).selectKind(null),
            child: const Text('Lihat semua jenis'),
          )
        else
          FilledButton.icon(
            key: const Key('create-first-budget'),
            onPressed: () => context.push(_budgetCreateLocation(selection)),
            icon: const Icon(Icons.add),
            label: const Text('Buat anggaran'),
          ),
      ],
    );
  }
}
