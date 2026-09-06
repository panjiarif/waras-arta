import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../view_models/ledger_view_model.dart';
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
  late String _category;
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
    _category =
        entry?.category ??
        (_kind == EntryKind.income
            ? incomeCategories.first
            : expenseCategories.first);
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
      category: _kind == EntryKind.transfer ? null : _category,
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
          data: (data) => data.accounts.isEmpty
              ? const FormBody(
                  child: FormMessage(
                    'Tambahkan rekening terlebih dahulu melalui halaman utama.',
                  ),
                )
              : _form(data.accounts, save),
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

  Widget _form(List<FinanceAccount> accounts, SaveState save) {
    final accountId = _accountId ?? accounts.first.id;
    final destinations = accounts
        .where((account) => account.id != accountId)
        .toList();
    final transfer = _kind == EntryKind.transfer;
    final canTransfer = !transfer || destinations.isNotEmpty;
    final categories = _kind == EntryKind.income
        ? incomeCategories
        : expenseCategories;
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
                  if (value != null) {
                    setState(() {
                      _kind = value;
                      _dirty = true;
                      _category =
                          (value == EntryKind.income
                                  ? incomeCategories
                                  : expenseCategories)
                              .first;
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
                      child: Text(
                        account.name,
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
                        child: Text(
                          account.name,
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
                DropdownButtonFormField<String>(
                  key: ValueKey('category-${_kind.name}'),
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(value: category, child: Text(category)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _category = value;
                        _dirty = true;
                      });
                    }
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
                onPressed: save.isSaving || !canTransfer
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
