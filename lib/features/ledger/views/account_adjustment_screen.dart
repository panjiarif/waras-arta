import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../view_models/account_view_model.dart';
import 'account_widgets.dart';
import 'form_widgets.dart';

class AccountBalanceAdjustmentScreen extends ConsumerWidget {
  const AccountBalanceAdjustmentScreen({super.key, required this.accountId});

  final int accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(accountDetailsProvider(accountId));
    return details.when(
      loading: () => const AccountAsyncScreen.loading(title: 'Sesuaikan saldo'),
      error: (_, _) => AccountAsyncScreen.error(
        title: 'Sesuaikan saldo',
        onRetry: () => ref.invalidate(accountDetailsProvider(accountId)),
      ),
      data: (value) {
        if (value == null) {
          return const AccountAsyncScreen.notFound(
            title: 'Rekening tidak ditemukan',
          );
        }
        if (value.account.isArchived) {
          return const AccountAsyncScreen(
            title: 'Sesuaikan saldo',
            icon: Icons.archive_outlined,
            message: 'Pulihkan rekening terlebih dahulu sebelum menyesuaikan saldonya.',
          );
        }
        return _AccountBalanceAdjustmentForm(
          key: ValueKey('account-adjustment-${value.account.id}'),
          account: value.account,
        );
      },
    );
  }
}

class _AccountBalanceAdjustmentForm extends ConsumerStatefulWidget {
  const _AccountBalanceAdjustmentForm({super.key, required this.account});

  final FinanceAccount account;

  @override
  ConsumerState<_AccountBalanceAdjustmentForm> createState() =>
      _AccountBalanceAdjustmentFormState();
}

class _AccountBalanceAdjustmentFormState
    extends ConsumerState<_AccountBalanceAdjustmentForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _target;
  final _note = TextEditingController();
  DateTime _date = dateOnly(DateTime.now());
  bool _dirty = false;
  bool _allowPop = false;
  bool _confirmingDiscard = false;

  int? get _targetValue => parseSignedRupiah(_target.text);
  int? get _delta {
    final target = _targetValue;
    return target == null ? null : target - widget.account.balance;
  }

  @override
  void initState() {
    super.initState();
    _target = TextEditingController(text: widget.account.balance.toString());
    _target.addListener(_onFieldChanged);
    _note.addListener(_onFieldChanged);
    ref.read(accountActionsProvider.notifier).clearError();
  }

  @override
  void dispose() {
    _target.removeListener(_onFieldChanged);
    _note.removeListener(_onFieldChanged);
    _target.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() => _dirty = true);
  }

  String? _validateTarget(String? value) {
    final error = validateSignedRupiah(value);
    if (error != null) return error;
    final target = parseSignedRupiah(value!)!;
    final delta = target - widget.account.balance;
    if (delta == 0) return 'Saldo baru masih sama dengan saldo saat ini.';
    if (delta.abs() > maxAmount) {
      return 'Selisih penyesuaian terlalu besar.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final saved = await ref
        .read(accountActionsProvider.notifier)
        .adjustBalance(
          widget.account.id,
          AccountBalanceAdjustmentDraft(
            targetBalance: _targetValue!,
            occurredAt: _date,
            note: _note.text,
          ),
        );
    if (!saved || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() {
      _dirty = false;
      _allowPop = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    router.pop(true);
    messenger.showSnackBar(
      const SnackBar(content: Text('Penyesuaian saldo dicatat.')),
    );
  }

  Future<void> _confirmDiscard() async {
    if (_confirmingDiscard) return;
    _confirmingDiscard = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Buang penyesuaian saldo?'),
        content: const Text(
          'Saldo, tanggal, atau catatan yang diubah belum disimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Tetap di sini'),
          ),
          FilledButton(
            key: const Key('discard-balance-adjustment'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Buang perubahan'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _confirmingDiscard = false;
    if (discard != true) return;
    ref.read(accountActionsProvider.notifier).clearError();
    final router = GoRouter.of(context);
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(accountActionsProvider);
    final delta = _delta;
    return PopScope(
      canPop: _allowPop || (!action.isSaving && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !action.isSaving && !_allowPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Sesuaikan saldo')),
        body: FormBody(
          child: AbsorbPointer(
            absorbing: action.isSaving,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.account.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Saldo tercatat: ${formatRupiah(widget.account.balance)}',
                  ),
                  const SizedBox(height: 20),
                  const FormMessage(
                    'Masukkan saldo aktual yang terlihat sekarang. Selisihnya dicatat sebagai penyesuaian dan tidak dihitung sebagai pemasukan atau pengeluaran.',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('target-account-balance'),
                    controller: _target,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Saldo aktual sekarang',
                      prefixText: 'Rp ',
                      helperText:
                          'Boleh nol atau negatif; tulis tanpa titik/koma.',
                      errorMaxLines: 3,
                    ),
                    validator: _validateTarget,
                  ),
                  const SizedBox(height: 12),
                  _AdjustmentPreview(delta: delta),
                  const SizedBox(height: 20),
                  EntryDateField(
                    date: _date,
                    label: 'Tanggal penyesuaian',
                    onChanged: (date) {
                      setState(() {
                        _date = date;
                        _dirty = true;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('balance-adjustment-note'),
                    controller: _note,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Catatan (opsional)',
                      hintText: 'Contoh: Koreksi setelah cek mutasi bank',
                    ),
                  ),
                  if (action.error != null) ...[
                    const SizedBox(height: 16),
                    FormMessage(action.error!, isError: true),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('save-balance-adjustment'),
                    onPressed: action.isSaving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      action.isSaving ? 'Menyimpan…' : 'Catat penyesuaian',
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
}

class _AdjustmentPreview extends StatelessWidget {
  const _AdjustmentPreview({required this.delta});

  final int? delta;

  @override
  Widget build(BuildContext context) {
    final value = delta;
    final color = value == null || value == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : value > 0
        ? forest
        : Theme.of(context).colorScheme.error;
    final text = value == null
        ? 'Masukkan saldo dengan format yang benar.'
        : value == 0
        ? 'Saldo baru sama dengan saldo tercatat.'
        : value > 0
        ? 'Penyesuaian menambah ${formatRupiah(value)}.'
        : 'Penyesuaian mengurangi ${formatRupiah(value.abs())}.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.compare_arrows, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                key: const Key('balance-adjustment-preview'),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
