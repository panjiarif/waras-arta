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
  const EntryFormScreen({super.key, this.initialEntry});

  final FinanceEntry? initialEntry;

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late EntryKind _kind;
  late int? _accountId;
  late int? _destinationId;
  late int? _categoryId;
  late DateTime _date;
  bool _dirty = false;
  bool _allowPop = false;
  bool _confirmingDiscard = false;

  bool get _isEditing => widget.initialEntry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _amount = TextEditingController(text: entry?.amount.toString() ?? '');
    _note = TextEditingController(text: entry?.note ?? '');
    _kind = entry?.kind ?? EntryKind.expense;
    _accountId = entry?.accountId;
    _destinationId = entry?.destinationAccountId;
    _categoryId = entry?.categoryId;
    _date = entry?.occurredAt ?? dateOnly(DateTime.now());
    _amount.addListener(_markDirty);
    _note.addListener(_markDirty);
  }

  @override
  void dispose() {
    _amount.removeListener(_markDirty);
    _note.removeListener(_markDirty);
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<void> _save(List<FinanceAccount> accounts) async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final account = _accountId ?? accounts.first.id;
    final destination = _kind == EntryKind.transfer
        ? (_destinationId ??
              accounts.firstWhere((item) => item.id != account).id)
        : null;
    final draft = EntryDraft(
      kind: _kind,
      accountId: account,
      destinationAccountId: destination,
      amount: parseRupiah(_amount.text)!,
      categoryId: _kind == EntryKind.transfer ? null : _categoryId,
      note: _note.text,
      occurredAt: _date,
    );
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
    final categoriesReady = transfer || categoryTree!.hasValue;
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
                  if (value != null && value != _kind) {
                    setState(() {
                      _kind = value;
                      _dirty = true;
                      _categoryId = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('entry-amount'),
                controller: _amount,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nominal',
                  prefixText: 'Rp ',
                  hintText: '25000',
                  helperText: 'Rupiah bulat, tanpa titik/koma.',
                  errorMaxLines: 3,
                ),
                validator: validateRupiah,
              ),
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
                  loading: () => const InputDecorator(
                    decoration: InputDecoration(labelText: 'Subkategori'),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Memuat kategori…'),
                      ],
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
                  data: (groups) {
                    final hasActiveLeaf = groups.any(
                      (group) =>
                          !group.parent.isArchived &&
                          group.children.any((child) => !child.isArchived),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CategorySelectionField(
                          groups: groups,
                          value: _categoryId,
                          allowArchivedValue:
                              _isEditing &&
                              widget.initialEntry!.kind == _kind &&
                              widget.initialEntry!.categoryId == _categoryId,
                          onChanged: (value) {
                            setState(() {
                              _categoryId = value;
                              _dirty = true;
                            });
                          },
                          onManage: () {
                            ref
                                .read(categoryActionsProvider.notifier)
                                .clearError();
                            context.push(
                              '/categories?kind=${categoryKind.name}',
                            );
                          },
                        ),
                        if (!hasActiveLeaf) ...[
                          const SizedBox(height: 8),
                          const FormMessage(
                            'Belum ada subkategori aktif untuk jenis transaksi ini.',
                          ),
                          TextButton.icon(
                            onPressed: () => context.push(
                              '/categories?kind=${categoryKind.name}',
                            ),
                            icon: const Icon(Icons.tune),
                            label: const Text('Kelola kategori'),
                          ),
                        ],
                      ],
                    );
                  },
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
}
