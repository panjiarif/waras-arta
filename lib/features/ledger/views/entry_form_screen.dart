import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../../categories/view_models/category_view_model.dart';
import '../view_models/ledger_view_model.dart';
import 'category_selection_field.dart';
import 'form_widgets.dart';

class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen({super.key, this.initialEntry, this.initialDate});

  final FinanceEntry? initialEntry;
  final DateTime? initialDate;

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _totalSectionKey = GlobalKey();
  late final TextEditingController _transferAmount;
  late final TextEditingController _note;
  late final List<_AllocationInput> _allocations;
  late EntryKind _kind;
  late EntryKind _allocationKind;
  late int? _accountId;
  late int? _destinationId;
  late DateTime _date;
  int _nextAllocationId = 0;
  bool _updatingControllers = false;
  bool _dirty = false;
  bool _allowPop = false;
  bool _confirmingDiscard = false;

  bool get _isEditing => widget.initialEntry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _transferAmount = TextEditingController(
      text: entry?.kind == EntryKind.transfer ? entry!.amount.toString() : '',
    );
    _note = TextEditingController(text: entry?.note ?? '');
    _kind = entry?.kind ?? EntryKind.expense;
    _allocationKind = switch (_kind) {
      EntryKind.income => EntryKind.income,
      _ => EntryKind.expense,
    };
    _accountId = entry?.accountId;
    _destinationId = entry?.destinationAccountId;
    _allocations = [
      if (entry != null && entry.allocations.isNotEmpty)
        for (final allocation in entry.allocations)
          _createAllocation(
            amount: allocation.amount.toString(),
            categoryId: allocation.categoryId,
            originalCategoryId: allocation.categoryId,
          )
      else
        _createAllocation(),
    ];
    _date = dateOnly(entry?.occurredAt ?? widget.initialDate ?? DateTime.now());
    _transferAmount.addListener(_handleAmountChanged);
    _note.addListener(_markDirty);
  }

  @override
  void dispose() {
    _transferAmount.removeListener(_handleAmountChanged);
    _note.removeListener(_markDirty);
    _transferAmount.dispose();
    _note.dispose();
    for (final allocation in _allocations) {
      _disposeAllocation(allocation);
    }
    super.dispose();
  }

  _AllocationInput _createAllocation({
    String amount = '',
    int? categoryId,
    int? originalCategoryId,
  }) {
    final input = _AllocationInput(
      id: _nextAllocationId++,
      amount: TextEditingController(text: amount),
      categoryId: categoryId,
      originalCategoryId: originalCategoryId,
    );
    input.amount.addListener(_handleAmountChanged);
    return input;
  }

  void _disposeAllocation(_AllocationInput allocation) {
    allocation.amount.removeListener(_handleAmountChanged);
    allocation.dispose();
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  void _handleAmountChanged() {
    if (!_updatingControllers && mounted) {
      setState(() => _dirty = true);
    }
  }

  void _replaceControllerText(TextEditingController controller, String text) {
    _updatingControllers = true;
    controller.text = text;
    controller.selection = TextSelection.collapsed(offset: text.length);
    _updatingControllers = false;
  }

  int? get _allocationTotal {
    var total = 0;
    for (final allocation in _allocations) {
      final amount = parseRupiah(allocation.amount.text);
      if (amount == null) return null;
      total += amount;
    }
    return total;
  }

  bool _canAddAllocation(Set<int> activeLeafIds) {
    if (_allocations.length >= maxEntryAllocations) return false;
    final selectedActiveCategoryIds = {
      for (final allocation in _allocations)
        if (activeLeafIds.contains(allocation.categoryId))
          allocation.categoryId!,
    };
    final unassignedAllocationCount = _allocations
        .where((allocation) => allocation.categoryId == null)
        .length;
    final unusedActiveCategoryCount =
        activeLeafIds.length - selectedActiveCategoryIds.length;
    return unusedActiveCategoryCount > unassignedAllocationCount;
  }

  Future<void> _addAllocation(Set<int> activeLeafIds) async {
    if (!_canAddAllocation(activeLeafIds)) return;
    final allocation = _createAllocation();
    setState(() {
      _allocations.add(allocation);
      _dirty = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    allocation.amountFocusNode.requestFocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_allocations.contains(allocation)) return;
    final rowContext = allocation.rowKey.currentContext;
    if (rowContext != null && rowContext.mounted) {
      await Scrollable.ensureVisible(
        rowContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: .15,
      );
    }
  }

  void _removeAllocation(_AllocationInput allocation) {
    if (_allocations.length <= 1) return;
    allocation.amount.removeListener(_handleAmountChanged);
    setState(() {
      _allocations.remove(allocation);
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => allocation.dispose());
  }

  void _changeKind(EntryKind value) {
    if (value == _kind) return;
    final previousKind = _kind;

    if (value == EntryKind.transfer && previousKind != EntryKind.transfer) {
      final total = _allocationTotal;
      final transferText = total != null && total > 0 && total <= maxAmount
          ? total.toString()
          : '';
      _replaceControllerText(_transferAmount, transferText);
    } else if (previousKind == EntryKind.transfer) {
      final transferAmount = parseRupiah(_transferAmount.text);
      final everyAllocationEmpty = _allocations.every(
        (allocation) => allocation.amount.text.trim().isEmpty,
      );
      if (everyAllocationEmpty &&
          transferAmount != null &&
          transferAmount > 0) {
        _replaceControllerText(
          _allocations.first.amount,
          transferAmount.toString(),
        );
      }
    }

    setState(() {
      _kind = value;
      _dirty = true;
      if (value != EntryKind.transfer && value != _allocationKind) {
        _allocationKind = value;
        for (final allocation in _allocations) {
          allocation.categoryId = null;
        }
      }
    });
  }

  String? _validateAllocationCategory(
    int? categoryId,
    _AllocationInput current,
  ) {
    if (categoryId != null &&
        _allocations.any(
          (allocation) =>
              allocation != current && allocation.categoryId == categoryId,
        )) {
      return 'Subkategori ini sudah dipakai pada rincian lain.';
    }
    return null;
  }

  bool _canRetainArchivedCategory(_AllocationInput allocation) =>
      _isEditing &&
      widget.initialEntry!.kind == _kind &&
      allocation.categoryId != null &&
      allocation.originalCategoryId == allocation.categoryId;

  Future<void> _save(List<FinanceAccount> accounts) async {
    if (!_formKey.currentState!.validate()) {
      await _revealFirstInvalidField();
      return;
    }
    FocusScope.of(context).unfocus();
    final account = _accountId ?? accounts.first.id;
    final destination = _kind == EntryKind.transfer
        ? (_destinationId ??
              accounts.firstWhere((item) => item.id != account).id)
        : null;
    late final EntryDraft draft;
    if (_kind == EntryKind.transfer) {
      final amount = parseRupiah(_transferAmount.text);
      if (amount == null || amount == 0) return;
      draft = EntryDraft.transfer(
        accountId: account,
        destinationAccountId: destination!,
        amount: amount,
        note: _note.text,
        occurredAt: _date,
      );
    } else {
      final allocationDrafts = <EntryAllocationDraft>[];
      for (final allocation in _allocations) {
        final categoryId = allocation.categoryId;
        final amount = parseRupiah(allocation.amount.text);
        if (categoryId == null || amount == null || amount == 0) {
          await _revealFirstInvalidField();
          return;
        }
        allocationDrafts.add(
          EntryAllocationDraft(categoryId: categoryId, amount: amount),
        );
      }
      draft = EntryDraft.withAllocations(
        kind: _kind,
        accountId: account,
        allocations: allocationDrafts,
        note: _note.text,
        occurredAt: _date,
      );
    }
    final actions = ref.read(financeActionsProvider.notifier);
    final saved = _isEditing
        ? await actions.updateEntry(widget.initialEntry!.id, draft)
        : await actions.addEntry(draft);
    if (saved && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      setState(() {
        _dirty = false;
        _allowPop = true;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      router.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Perubahan transaksi tersimpan.'
                : 'Transaksi tersimpan di perangkat.',
          ),
        ),
      );
    }
  }

  Future<void> _revealFirstInvalidField() async {
    _AllocationInput? invalidAllocation;
    final usedCategoryIds = <int>{};
    for (final allocation in _allocations) {
      final categoryId = allocation.categoryId;
      if (validateRupiah(allocation.amount.text) != null ||
          categoryId == null ||
          !usedCategoryIds.add(categoryId)) {
        invalidAllocation = allocation;
        break;
      }
    }

    final total = _allocationTotal;
    final invalidTotal = total != null && total > maxAmount;
    final targetContext =
        invalidAllocation?.rowKey.currentContext ??
        (invalidTotal ? _totalSectionKey.currentContext : null) ??
        _allocations.firstOrNull?.rowKey.currentContext;
    if (targetContext == null || !targetContext.mounted) return;

    if (invalidAllocation != null &&
        validateRupiah(invalidAllocation.amount.text) != null) {
      invalidAllocation.amountFocusNode.requestFocus();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !targetContext.mounted) return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: .12,
    );
  }

  Future<void> _confirmDiscard() async {
    if (_confirmingDiscard) return;
    _confirmingDiscard = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Buang perubahan?'),
        content: Text(
          _isEditing
              ? 'Perubahan pada transaksi ini belum disimpan.'
              : 'Data transaksi yang sudah diisi belum disimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Tetap di sini'),
          ),
          FilledButton(
            key: const Key('discard-entry-changes'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Buang perubahan'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _confirmingDiscard = false;
    if (discard != true) return;
    final router = GoRouter.of(context);
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(financeSnapshotProvider);
    final save = ref.watch(financeActionsProvider);
    return PopScope(
      canPop: _allowPop || (!save.isSaving && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !save.isSaving && !_allowPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit transaksi' : 'Catat transaksi'),
        ),
        body: snapshot.when(
          data: (data) {
            final accounts = _accountsForForm(data.accounts);
            return accounts.isEmpty
                ? const FormBody(
                    child: FormMessage(
                      'Belum ada rekening aktif. Tambahkan atau pulihkan rekening melalui tab Rekening.',
                    ),
                  )
                : _form(accounts, save);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => FormBody(
            child: Column(
              children: [
                const FormMessage(
                  'Rekening belum dapat dimuat.',
                  isError: true,
                ),
                TextButton(
                  onPressed: () => ref.invalidate(financeSnapshotProvider),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<FinanceAccount> _accountsForForm(List<FinanceAccount> accounts) {
    final retainedIds = _isEditing
        ? {
            widget.initialEntry!.accountId,
            if (widget.initialEntry!.destinationAccountId != null)
              widget.initialEntry!.destinationAccountId!,
          }
        : const <int>{};
    return accounts
        .where(
          (account) => !account.isArchived || retainedIds.contains(account.id),
        )
        .toList(growable: false);
  }

  Widget _form(List<FinanceAccount> accounts, SaveState save) {
    final accountId = _accountId ?? accounts.first.id;
    final destinations = accounts
        .where((account) => account.id != accountId)
        .toList();
    final transfer = _kind == EntryKind.transfer;
    final canTransfer = !transfer || destinations.isNotEmpty;
    final categoryKind = _kind == EntryKind.income
        ? CategoryKind.income
        : CategoryKind.expense;
    final categoryQuery = (kind: categoryKind, includeArchived: true);
    final categoryTree = transfer
        ? null
        : ref.watch(categoryTreeProvider(categoryQuery));
    final categoriesReady =
        transfer || (categoryTree!.hasValue && !categoryTree.hasError);
    return FormBody(
      child: AbsorbPointer(
        absorbing: save.isSaving,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? 'Perbarui catatan dengan teliti.'
                    : 'Sedikit catatan, lebih terarah.',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_isEditing &&
                  accounts.any(
                    (account) =>
                        account.isArchived &&
                        (account.id == widget.initialEntry!.accountId ||
                            account.id ==
                                widget.initialEntry!.destinationAccountId),
                  )) ...[
                const SizedBox(height: 16),
                const FormMessage(
                  'Transaksi ini memakai rekening yang diarsipkan. Pulihkan rekening tersebut sebelum mengubah transaksi.',
                ),
              ],
              const SizedBox(height: 24),
              DropdownButtonFormField<EntryKind>(
                key: const Key('entry-kind'),
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Jenis transaksi'),
                items: [
                  for (final kind in [
                    EntryKind.expense,
                    EntryKind.income,
                    EntryKind.transfer,
                  ])
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (value) {
                  if (value != null) _changeKind(value);
                },
              ),
              if (transfer) ...[
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('entry-amount'),
                  controller: _transferAmount,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nominal transfer',
                    prefixText: 'Rp ',
                    hintText: '25000',
                    helperText: 'Rupiah bulat, tanpa titik/koma.',
                    errorMaxLines: 3,
                  ),
                  validator: validateRupiah,
                ),
              ],
              const SizedBox(height: 20),
              DropdownButtonFormField<int>(
                key: const Key('source-account'),
                initialValue: accountId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _kind == EntryKind.income
                      ? 'Ke rekening'
                      : 'Dari rekening',
                ),
                items: [
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account.id,
                      enabled: !account.isArchived,
                      child: Text(
                        account.isArchived
                            ? '${account.name} • Diarsipkan'
                            : account.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _accountId = id;
                  _destinationId = null;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'Saldo saat ini: ${formatRupiah(accounts.firstWhere((account) => account.id == accountId).balance)}',
              ),
              const SizedBox(height: 20),
              if (transfer && canTransfer) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey('destination-$accountId'),
                  initialValue: _destinationId ?? destinations.first.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ke rekening'),
                  items: [
                    for (final account in destinations)
                      DropdownMenuItem(
                        value: account.id,
                        enabled: !account.isArchived,
                        child: Text(
                          account.isArchived
                              ? '${account.name} • Diarsipkan'
                              : account.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() {
                    _destinationId = id;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 20),
                const FormMessage(
                  'Transfer hanya memindahkan uang milikmu. Tidak dihitung sebagai pemasukan atau pengeluaran. Biaya admin dapat dicatat sebagai pengeluaran terpisah.',
                ),
                const SizedBox(height: 20),
              ] else if (transfer) ...[
                const FormMessage(
                  'Transfer perlu dua rekening berbeda. Tambahkan rekening kedua dari menu Rekening.',
                ),
                const SizedBox(height: 20),
              ] else ...[
                categoryTree!.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: Text('Memuat rincian dan kategori…')),
                        ],
                      ),
                    ),
                  ),
                  error: (_, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FormMessage(
                        'Kategori belum dapat dimuat.',
                        isError: true,
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            ref.invalidate(categoryTreeProvider(categoryQuery)),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                  data: (groups) =>
                      _allocationSection(groups, categoryKind: categoryKind),
                ),
                const SizedBox(height: 20),
              ],
              EntryDateField(
                date: _date,
                onChanged: (date) {
                  if (mounted) {
                    setState(() {
                      _date = date;
                      _dirty = true;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              const Text('Lupa mencatat kemarin? Pilih tanggal kejadiannya.'),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('entry-note'),
                controller: _note,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  hintText: 'Contoh: Makan siang',
                ),
              ),
              if (save.error != null) ...[
                const SizedBox(height: 16),
                FormMessage(save.error!, isError: true),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('save-entry'),
                onPressed: save.isSaving || !canTransfer || !categoriesReady
                    ? null
                    : () => _save(accounts),
                child: Text(
                  save.isSaving
                      ? 'Menyimpan…'
                      : _isEditing
                      ? 'Simpan perubahan'
                      : 'Simpan transaksi',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _allocationSection(
    List<CategoryGroup> groups, {
    required CategoryKind categoryKind,
  }) {
    final activeLeafIds = {
      for (final group in groups)
        if (!group.parent.isArchived)
          for (final child in group.children)
            if (!child.isArchived) child.id,
    };
    final hasActiveLeaf = activeLeafIds.isNotEmpty;
    final canAddAllocation = _canAddAllocation(activeLeafIds);
    final total = _allocationTotal;

    void manageCategories() {
      ref.read(categoryActionsProvider.notifier).clearError();
      context.push('/categories?kind=${categoryKind.name}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Rincian transaksi',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${_allocations.length}/$maxEntryAllocations',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Pisahkan nominal berdasarkan subkategori bila satu pembayaran memiliki beberapa kebutuhan.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < _allocations.length; index++) ...[
          _allocationCard(
            groups,
            allocation: _allocations[index],
            index: index,
            onManage: manageCategories,
          ),
          if (index != _allocations.length - 1) const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('add-entry-allocation'),
          onPressed: canAddAllocation
              ? () => _addAllocation(activeLeafIds)
              : null,
          icon: const Icon(Icons.add),
          label: const Text('Tambah rincian'),
        ),
        if (_allocations.length >= maxEntryAllocations) ...[
          const SizedBox(height: 8),
          const Text(
            'Maksimal 50 rincian dalam satu transaksi.',
            textAlign: TextAlign.center,
          ),
        ] else if (hasActiveLeaf && !canAddAllocation) ...[
          const SizedBox(height: 8),
          const Text(
            'Tidak ada subkategori aktif lain untuk rincian baru.',
            textAlign: TextAlign.center,
          ),
          TextButton.icon(
            onPressed: manageCategories,
            icon: const Icon(Icons.tune),
            label: const Text('Kelola kategori'),
          ),
        ],
        if (_allocations.length > 1) ...[
          const SizedBox(height: 12),
          FormField<void>(
            key: const Key('entry-allocation-total-validator'),
            autovalidateMode: AutovalidateMode.always,
            validator: (_) {
              final currentTotal = _allocationTotal;
              return currentTotal != null && currentTotal > maxAmount
                  ? 'Total transaksi melebihi Rp999.999.999.999.'
                  : null;
            },
            builder: (field) => Container(
              key: _totalSectionKey,
              child: Container(
                key: const Key('entry-allocation-total'),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                  border: field.hasError
                      ? Border.all(color: Theme.of(context).colorScheme.error)
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final totalLabel = const Text(
                          'Total transaksi',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        );
                        final totalValue = Text(
                          total == null ? 'Belum lengkap' : formatRupiah(total),
                          key: const Key('entry-allocation-total-value'),
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                        final compact =
                            constraints.maxWidth < 300 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.4;
                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              totalLabel,
                              const SizedBox(height: 6),
                              totalValue,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: totalLabel),
                            const SizedBox(width: 12),
                            Flexible(child: totalValue),
                          ],
                        );
                      },
                    ),
                    if (field.errorText != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          field.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
        if (!hasActiveLeaf) ...[
          const SizedBox(height: 12),
          const FormMessage(
            'Belum ada subkategori aktif untuk jenis transaksi ini.',
          ),
          TextButton.icon(
            onPressed: manageCategories,
            icon: const Icon(Icons.tune),
            label: const Text('Kelola kategori'),
          ),
        ],
      ],
    );
  }

  Widget _allocationCard(
    List<CategoryGroup> groups, {
    required _AllocationInput allocation,
    required int index,
    required VoidCallback onManage,
  }) {
    final multiple = _allocations.length > 1;
    final selectedElsewhere = {
      for (final other in _allocations)
        if (other != allocation && other.categoryId != null) other.categoryId!,
    };
    return Container(
      key: allocation.rowKey,
      child: Card(
        key: ValueKey('entry-allocation-row-${allocation.id}'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      multiple ? 'Rincian ${index + 1}' : 'Rincian utama',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (multiple)
                    IconButton(
                      key: ValueKey('remove-entry-allocation-${allocation.id}'),
                      tooltip: 'Hapus rincian ${index + 1}',
                      onPressed: () => _removeAllocation(allocation),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: index == 0
                    ? const Key('entry-amount')
                    : ValueKey('entry-allocation-amount-${allocation.id}'),
                controller: allocation.amount,
                focusNode: allocation.amountFocusNode,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: multiple
                      ? 'Nominal rincian ${index + 1}'
                      : 'Nominal',
                  prefixText: 'Rp ',
                  hintText: '25000',
                  helperText: 'Rupiah bulat, tanpa titik/koma.',
                  errorMaxLines: 3,
                ),
                validator: validateRupiah,
              ),
              const SizedBox(height: 16),
              CategorySelectionField(
                key: ValueKey('entry-allocation-category-${allocation.id}'),
                groups: groups,
                value: allocation.categoryId,
                allowArchivedValue: _canRetainArchivedCategory(allocation),
                controlKey: index == 0
                    ? const Key('entry-category')
                    : ValueKey('entry-category-${allocation.id}'),
                identity: allocation.id,
                disabledValues: selectedElsewhere,
                label: multiple
                    ? 'Subkategori rincian ${index + 1}'
                    : 'Subkategori',
                additionalValidator: (categoryId) =>
                    _validateAllocationCategory(categoryId, allocation),
                onChanged: (value) {
                  setState(() {
                    allocation.categoryId = value;
                    _dirty = true;
                  });
                },
                onManage: onManage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllocationInput {
  _AllocationInput({
    required this.id,
    required this.amount,
    required this.categoryId,
    required this.originalCategoryId,
  });

  final int id;
  final TextEditingController amount;
  final FocusNode amountFocusNode = FocusNode();
  final GlobalKey rowKey = GlobalKey();
  int? categoryId;
  final int? originalCategoryId;

  void dispose() {
    amount.dispose();
    amountFocusNode.dispose();
  }
}
