import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../domain/budget.dart';
import '../../../domain/finance.dart';
import '../../calendar/view_models/calendar_view_model.dart';
import '../../ledger/views/form_widgets.dart';
import '../view_models/budget_view_model.dart';
import 'budget_widgets.dart';

class BudgetFormScreen extends ConsumerStatefulWidget {
  const BudgetFormScreen({super.key, this.initial});

  final BudgetDetails? initial;

  @override
  ConsumerState<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class BudgetEditScreen extends ConsumerWidget {
  const BudgetEditScreen({super.key, required this.budgetId});

  final int budgetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(budgetDetailsProvider(budgetId));
    return details.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Edit anggaran')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Edit anggaran')),
        body: BudgetLoadState(
          message: 'Anggaran belum dapat dimuat.',
          onRetry: () => ref.invalidate(budgetDetailsProvider(budgetId)),
        ),
      ),
      data: (value) => value == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Edit anggaran')),
              body: const BudgetLoadState(
                message: 'Anggaran tidak ditemukan atau sudah dihapus.',
                icon: Icons.search_off,
              ),
            )
          : BudgetFormScreen(
              key: ValueKey('budget-editor-$budgetId'),
              initial: value,
            ),
    );
  }
}

class _BudgetFormScreenState extends ConsumerState<BudgetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _limit;
  late BudgetPeriodKind _kind;
  late DateTime _month;
  late int _year;
  DateTimeRange? _customRange;
  late Set<int> _categoryIds;
  bool _dirty = false;
  bool _allowPop = false;
  String? _localError;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final today = dateOnly(ref.read(currentDateProvider));
    _name = TextEditingController(text: initial?.budget.name ?? '');
    _limit = TextEditingController(
      text: initial?.budget.limitAmount.toString() ?? '',
    );
    _kind = initial?.budget.period.kind ?? BudgetPeriodKind.monthly;
    final start = initial == null
        ? today
        : civilDayToDateTime(initial.budget.period.startDay);
    final end = initial == null
        ? today
        : civilDayToDateTime(initial.budget.period.endDay);
    _month = DateTime(start.year, start.month);
    _year = start.year;
    _customRange = initial?.budget.period.kind == BudgetPeriodKind.custom
        ? DateTimeRange(start: start, end: end)
        : null;
    _categoryIds = {
      for (final category in initial?.categories ?? const <BudgetCategoryRef>[])
        category.id,
    };
    _name.addListener(_markDirty);
    _limit.addListener(_markDirty);
    ref.read(budgetActionsProvider.notifier).clearError();
  }

  @override
  void dispose() {
    _name
      ..removeListener(_markDirty)
      ..dispose();
    _limit
      ..removeListener(_markDirty)
      ..dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  BudgetPeriod? get _period {
    try {
      return switch (_kind) {
        BudgetPeriodKind.monthly => BudgetPeriod.monthly(
          _month.year,
          _month.month,
        ),
        BudgetPeriodKind.yearly => BudgetPeriod.yearly(_year),
        BudgetPeriodKind.custom when _customRange != null =>
          BudgetPeriod.custom(
            dateTimeToCivilDay(_customRange!.start),
            dateTimeToCivilDay(_customRange!.end),
          ),
        BudgetPeriodKind.custom => null,
      };
    } on BudgetValidationException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(budgetActionsProvider);
    final categories = ref.watch(budgetExpenseCategoriesProvider);
    final period = _period;
    final BudgetConflictQuery? conflictQuery = period == null
        ? null
        : (period: period, excludingBudgetId: widget.initial?.budget.id);
    final conflicts = conflictQuery == null
        ? const AsyncValue<Map<int, List<BudgetConflict>>>.data({})
        : ref.watch(budgetConflictsProvider(conflictQuery));
    final stackedSelector =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;

    return PopScope(
      canPop: _allowPop || (!action.isSaving && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !action.isSaving && !_allowPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? 'Edit anggaran' : 'Tambah anggaran'),
        ),
        body: FormBody(
          child: AbsorbPointer(
            absorbing: action.isSaving,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _editing ? 'Perbarui batasmu' : 'Rencanakan batas belanja',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Anggaran membantu memantau batas pengeluaran, tetapi tidak memindahkan uang atau mengubah saldo rekening.',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('budget-name'),
                    controller: _name,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nama anggaran',
                      hintText: 'Contoh: Makan di luar',
                    ),
                    validator: (value) {
                      final canonical = value?.trim() ?? '';
                      if (canonical.isEmpty) return 'Isi nama anggaran.';
                      if (canonical.length > 80) {
                        return 'Nama maksimal 80 karakter.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('budget-limit'),
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Batas anggaran',
                      prefixText: 'Rp ',
                      helperText: 'Berlaku untuk seluruh periode, tidak dibagi otomatis per bulan.',
                      helperMaxLines: 3,
                    ),
                    validator: (value) => validateRupiah(value),
                  ),
                  const SizedBox(height: 20),
                  if (_editing) ...[
                    Text(
                      'Periode',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      key: const Key('budget-period-read-only'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${widget.initial!.budget.period.kind.label} · '
                        '${budgetPeriodLabel(widget.initial!.budget.period)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Jenis dan tanggal periode tidak dapat diubah. Buat ulang anggaran jika periodenya keliru.',
                    ),
                  ] else ...[
                    Text(
                      'Jenis periode',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<BudgetPeriodKind>(
                      key: const Key('budget-period-kind'),
                      direction: stackedSelector
                          ? Axis.vertical
                          : Axis.horizontal,
                      expandedInsets: stackedSelector ? null : EdgeInsets.zero,
                      segments: [
                        for (final kind in BudgetPeriodKind.values)
                          ButtonSegment(
                            value: kind,
                            label: Text(
                              kind.label,
                              key: ValueKey('budget-period-${kind.name}'),
                            ),
                          ),
                      ],
                      selected: {_kind},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        setState(() {
                          _kind = selection.single;
                          _dirty = true;
                          _localError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _PeriodField(
                      kind: _kind,
                      month: _month,
                      year: _year,
                      customRange: _customRange,
                      onTap: _pickPeriod,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Kategori pengeluaran',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _BudgetCategoryField(
                    categories: categories,
                    conflicts: conflicts,
                    selectedIds: _categoryIds,
                    onRetryConflicts: conflictQuery == null
                        ? null
                        : () {
                            setState(() => _localError = null);
                            ref.invalidate(
                              budgetConflictsProvider(conflictQuery),
                            );
                          },
                    onChanged: (value) {
                      setState(() {
                        _categoryIds = value;
                        _dirty = true;
                        _localError = null;
                      });
                    },
                  ),
                  if (_selectedConflictCount(conflicts) > 0) ...[
                    const SizedBox(height: 10),
                    FormMessage(
                      '${_selectedConflictCount(conflicts)} kategori bertabrakan '
                      'dengan anggaran lain. Lepaskan kategori tersebut sebelum menyimpan.',
                      isError: true,
                    ),
                  ],
                  if (_localError != null) ...[
                    const SizedBox(height: 14),
                    FormMessage(_localError!, isError: true),
                  ],
                  if (action.error != null) ...[
                    const SizedBox(height: 14),
                    FormMessage(action.error!, isError: true),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('save-budget'),
                    onPressed: action.isSaving ? null : () => _save(conflicts),
                    icon: action.isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      action.isSaving
                          ? 'Menyimpan…'
                          : _editing
                          ? 'Simpan perubahan'
                          : 'Simpan anggaran',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _selectedConflictCount(
    AsyncValue<Map<int, List<BudgetConflict>>> conflicts,
  ) {
    final values = conflicts.asData?.value ?? const {};
    return _categoryIds.where((id) => values[id]?.isNotEmpty ?? false).length;
  }

  Future<void> _pickPeriod() async {
    switch (_kind) {
      case BudgetPeriodKind.monthly:
        final selected = await showDatePicker(
          context: context,
          helpText: 'Pilih tanggal dalam bulan anggaran',
          initialDate: _month,
          firstDate: DateTime(2000),
          lastDate: DateTime(9999, 12, 31),
        );
        if (selected != null && mounted) {
          setState(() {
            _month = DateTime(selected.year, selected.month);
            _dirty = true;
            _localError = null;
          });
        }
        return;
      case BudgetPeriodKind.yearly:
        final selected = await showDialog<int>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pilih tahun'),
            content: SizedBox(
              width: 320,
              height: 360,
              child: YearPicker(
                firstDate: DateTime(2000),
                lastDate: DateTime(9999, 12, 31),
                selectedDate: DateTime(_year),
                currentDate: dateOnly(ref.read(currentDateProvider)),
                onChanged: (value) => Navigator.pop(context, value.year),
              ),
            ),
          ),
        );
        if (selected != null && mounted) {
          setState(() {
            _year = selected;
            _dirty = true;
            _localError = null;
          });
        }
        return;
      case BudgetPeriodKind.custom:
        final selected = await showDateRangePicker(
          context: context,
          helpText: 'Pilih rentang anggaran',
          firstDate: DateTime(2000),
          lastDate: DateTime(9999, 12, 31),
          initialDateRange: _customRange,
        );
        if (selected != null && mounted) {
          setState(() {
            _customRange = selected;
            _dirty = true;
            _localError = null;
          });
        }
        return;
    }
  }

  Future<void> _save(
    AsyncValue<Map<int, List<BudgetConflict>>> conflicts,
  ) async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final period = _period;
    if (period == null) {
      setState(() => _localError = 'Pilih rentang tanggal anggaran.');
      return;
    }
    if (_categoryIds.isEmpty) {
      setState(
        () => _localError = 'Pilih minimal satu subkategori pengeluaran.',
      );
      return;
    }
    final conflictMap = conflicts.asData?.value;
    if (conflictMap == null) {
      setState(
        () => _localError = 'Konflik kategori belum dapat diperiksa. Coba lagi setelah data termuat.',
      );
      return;
    }
    if (_categoryIds.any((id) => conflictMap[id]?.isNotEmpty ?? false)) {
      setState(
        () => _localError =
            'Lepaskan kategori yang bertabrakan sebelum menyimpan.',
      );
      return;
    }

    final amount = parseRupiah(_limit.text)!;
    final actions = ref.read(budgetActionsProvider.notifier);
    final initial = widget.initial;
    int? saved;
    if (initial == null) {
      saved = await actions.createBudget(
        BudgetDraft(
          period: period,
          name: _name.text,
          limitAmount: amount,
          categoryIds: _categoryIds,
        ),
      );
    } else {
      final updated = await actions.updateBudget(
        initial.budget.id,
        BudgetUpdateDraft(
          name: _name.text,
          limitAmount: amount,
          categoryIds: _categoryIds,
        ),
      );
      saved = updated ? initial.budget.id : null;
    }
    if (saved == null || !mounted) return;
    _allowPop = true;
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          initial == null ? 'Anggaran tersimpan.' : 'Anggaran diperbarui.',
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buang perubahan?'),
        content: const Text(
          'Perubahan anggaran yang belum disimpan akan hilang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tetap di sini'),
          ),
          FilledButton(
            key: const Key('discard-budget-changes'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Buang'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _allowPop = true);
      context.pop();
    }
  }
}

class _PeriodField extends StatelessWidget {
  const _PeriodField({
    required this.kind,
    required this.month,
    required this.year,
    required this.customRange,
    required this.onTap,
  });

  final BudgetPeriodKind kind;
  final DateTime month;
  final int year;
  final DateTimeRange? customRange;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      BudgetPeriodKind.monthly => formatMonth(month),
      BudgetPeriodKind.yearly => 'Tahun $year',
      BudgetPeriodKind.custom when customRange != null =>
        '${formatDate(customRange!.start)} – ${formatDate(customRange!.end)}',
      BudgetPeriodKind.custom => 'Pilih tanggal mulai dan selesai',
    };
    final key = switch (kind) {
      BudgetPeriodKind.monthly => const Key('budget-month'),
      BudgetPeriodKind.yearly => const Key('budget-year'),
      BudgetPeriodKind.custom => const Key('budget-custom-range'),
    };
    return OutlinedButton(
      key: key,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.all(16),
        alignment: Alignment.centerLeft,
      ),
      onPressed: onTap,
      child: Row(
        children: [
          const Icon(Icons.date_range_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          const Icon(Icons.expand_more),
        ],
      ),
    );
  }
}

class _BudgetCategoryField extends StatelessWidget {
  const _BudgetCategoryField({
    required this.categories,
    required this.conflicts,
    required this.selectedIds,
    required this.onRetryConflicts,
    required this.onChanged,
  });

  final AsyncValue<List<CategoryGroup>> categories;
  final AsyncValue<Map<int, List<BudgetConflict>>> conflicts;
  final Set<int> selectedIds;
  final VoidCallback? onRetryConflicts;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final groups = categories.asData?.value;
    final conflictMap = conflicts.asData?.value;
    if (categories.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormMessage(
            'Kategori pengeluaran belum dapat dimuat.',
            isError: true,
          ),
          const SizedBox(height: 8),
          Consumer(
            builder: (context, ref, _) => OutlinedButton.icon(
              onPressed: () => ref.invalidate(budgetExpenseCategoriesProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
          ),
        ],
      );
    }
    final conflictFailed = conflicts.hasError;
    final loading = groups == null || conflictMap == null;
    final picker = OutlinedButton(
      key: const Key('budget-category-picker'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        padding: const EdgeInsets.all(16),
        alignment: Alignment.centerLeft,
      ),
      onPressed: loading || conflictFailed
          ? null
          : () async {
              final selected = await showModalBottomSheet<Set<int>>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                useSafeArea: true,
                builder: (context) => _BudgetCategoryPickerSheet(
                  groups: groups,
                  conflicts: conflictMap,
                  initialIds: selectedIds,
                ),
              );
              if (selected != null) onChanged(selected);
            },
      child: Row(
        children: [
          conflictFailed
              ? const Icon(Icons.error_outline)
              : loading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.category_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Subkategori'),
                const SizedBox(height: 2),
                Text(
                  conflictFailed
                      ? 'Tidak tersedia sampai pemeriksaan konflik berhasil'
                      : loading
                      ? 'Memuat pilihan…'
                      : selectedIds.isEmpty
                      ? 'Belum ada yang dipilih'
                      : '${selectedIds.length} dipilih',
                  key: const Key('budget-category-count'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Icon(Icons.expand_more),
        ],
      ),
    );
    if (!conflictFailed) return picker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormMessage(
          'Konflik kategori belum dapat diperiksa. Data belum diubah.',
          key: Key('budget-conflicts-error'),
          isError: true,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('retry-budget-conflicts'),
          onPressed: onRetryConflicts,
          icon: const Icon(Icons.refresh),
          label: const Text('Periksa konflik lagi'),
        ),
        const SizedBox(height: 8),
        picker,
      ],
    );
  }
}

class _BudgetCategoryPickerSheet extends StatefulWidget {
  const _BudgetCategoryPickerSheet({
    required this.groups,
    required this.conflicts,
    required this.initialIds,
  });

  final List<CategoryGroup> groups;
  final Map<int, List<BudgetConflict>> conflicts;
  final Set<int> initialIds;

  @override
  State<_BudgetCategoryPickerSheet> createState() =>
      _BudgetCategoryPickerSheetState();
}

class _BudgetCategoryPickerSheetState
    extends State<_BudgetCategoryPickerSheet> {
  late final Set<int> _selected = Set.of(widget.initialIds);
  String? _selectionMessage;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SizedBox(
      height: (height * .88).clamp(420.0, 760.0).toDouble(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Pilih subkategori pengeluaran',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (_selectionMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(_selectionMessage!),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              key: const Key('budget-category-options'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              itemCount: widget.groups.length,
              itemBuilder: (context, index) {
                final group = widget.groups[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                group.parent.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Wrap(
                                spacing: 4,
                                children: [
                                  TextButton(
                                    key: ValueKey(
                                      'budget-select-all-${group.parent.id}',
                                    ),
                                    onPressed: () => _selectAll(group),
                                    child: const Text('Pilih semua'),
                                  ),
                                  TextButton(
                                    key: ValueKey(
                                      'budget-clear-all-${group.parent.id}',
                                    ),
                                    onPressed: () => _clearAll(group),
                                    child: const Text('Hapus semua'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        for (final category in group.children)
                          _categoryTile(group, category),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const Key('budget-categories-done'),
              onPressed: () => Navigator.pop(context, Set.of(_selected)),
              child: Text('Selesai (${_selected.length})'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTile(CategoryGroup group, FinanceCategory category) {
    final selected = _selected.contains(category.id);
    final archived = group.parent.isArchived || category.isArchived;
    final conflicts = widget.conflicts[category.id] ?? const [];
    final canAdd = !archived && conflicts.isEmpty;
    final subtitle = archived
        ? 'Diarsipkan · pilihan lama hanya dapat dilepas'
        : conflicts.isNotEmpty
        ? _conflictLabel(conflicts)
        : null;
    return CheckboxListTile(
      key: ValueKey('budget-category-${category.id}'),
      value: selected,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(category.name),
      subtitle: subtitle == null ? null : Text(subtitle),
      onChanged: selected
          ? (_) => setState(() => _selected.remove(category.id))
          : canAdd
          ? (_) => setState(() => _selected.add(category.id))
          : null,
    );
  }

  void _selectAll(CategoryGroup group) {
    var added = 0;
    var skipped = 0;
    setState(() {
      for (final category in group.children) {
        final blocked =
            group.parent.isArchived ||
            category.isArchived ||
            (widget.conflicts[category.id]?.isNotEmpty ?? false);
        if (blocked) {
          skipped++;
        } else if (_selected.add(category.id)) {
          added++;
        }
      }
      _selectionMessage =
          '$added dipilih dari ${group.parent.name}; '
          '$skipped dilewati karena arsip atau konflik.';
    });
  }

  void _clearAll(CategoryGroup group) {
    setState(() {
      for (final category in group.children) {
        _selected.remove(category.id);
      }
      _selectionMessage = 'Semua pilihan dari ${group.parent.name} dilepas.';
    });
  }

  String _conflictLabel(List<BudgetConflict> conflicts) {
    final examples = conflicts
        .take(2)
        .map((item) => '${item.budgetName} (${budgetPeriodLabel(item.period)})')
        .join(', ');
    final remaining = conflicts.length - 2;
    return remaining > 0
        ? 'Dipakai $examples +$remaining anggaran lain'
        : 'Dipakai $examples';
  }
}
