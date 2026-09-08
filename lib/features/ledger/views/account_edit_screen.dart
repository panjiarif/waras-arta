import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/finance.dart';
import '../view_models/account_view_model.dart';
import 'account_widgets.dart';
import 'form_widgets.dart';

class AccountEditScreen extends ConsumerWidget {
  const AccountEditScreen({super.key, required this.accountId});

  final int accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(accountDetailsProvider(accountId));
    return details.when(
      loading: () => const AccountAsyncScreen.loading(title: 'Edit rekening'),
      error: (_, _) => AccountAsyncScreen.error(
        title: 'Edit rekening',
        onRetry: () => ref.invalidate(accountDetailsProvider(accountId)),
      ),
      data: (value) => value == null
          ? const AccountAsyncScreen.notFound(title: 'Rekening tidak ditemukan')
          : _AccountEditForm(
              key: ValueKey('account-editor-${value.account.id}'),
              account: value.account,
            ),
    );
  }
}

class _AccountEditForm extends ConsumerStatefulWidget {
  const _AccountEditForm({super.key, required this.account});

  final FinanceAccount account;

  @override
  ConsumerState<_AccountEditForm> createState() => _AccountEditFormState();
}

class _AccountEditFormState extends ConsumerState<_AccountEditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late AccountType _type;
  late AccountBalanceGroup _balanceGroup;
  bool _dirty = false;
  bool _allowPop = false;
  bool _confirmingDiscard = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.account.name);
    _type = widget.account.type;
    _balanceGroup = widget.account.balanceGroup;
    _name.addListener(_markDirty);
    ref.read(accountActionsProvider.notifier).clearError();
  }

  @override
  void dispose() {
    _name.removeListener(_markDirty);
    _name.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final saved = await ref
        .read(accountActionsProvider.notifier)
        .updateAccount(
          widget.account.id,
          AccountUpdateDraft(
            name: _name.text,
            type: _type,
            balanceGroup: _balanceGroup,
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
      const SnackBar(content: Text('Perubahan rekening tersimpan.')),
    );
  }

  Future<void> _confirmDiscard() async {
    if (_confirmingDiscard) return;
    _confirmingDiscard = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Buang perubahan rekening?'),
        content: const Text('Nama, jenis, atau kelompok saldo belum disimpan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Tetap di sini'),
          ),
          FilledButton(
            key: const Key('discard-account-changes'),
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
    return PopScope(
      canPop: _allowPop || (!action.isSaving && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !action.isSaving && !_allowPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit rekening')),
        body: FormBody(
          child: AbsorbPointer(
            absorbing: action.isSaving,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Identitas rekening',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Perubahan identitas dan kelompok langsung digunakan pada seluruh riwayat tanpa mengubah saldo.',
                  ),
                  if (widget.account.isArchived) ...[
                    const SizedBox(height: 16),
                    const FormMessage(
                      'Rekening ini sedang diarsipkan. Identitasnya tetap dapat diperbaiki.',
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('account-edit-name'),
                    controller: _name,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nama rekening',
                      hintText: 'Contoh: Bank utama',
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AccountType>(
                    key: const Key('account-edit-type'),
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Jenis'),
                    items: [
                      for (final type in AccountType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: (value) {
                      if (value != null && value != _type) {
                        setState(() {
                          _type = value;
                          _dirty = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<AccountBalanceGroup>(
                    key: const Key('account-edit-balance-group'),
                    initialValue: _balanceGroup,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Kelompok saldo',
                      helperText: widget.account.isArchived
                          ? 'Rekening akan kembali ke kelompok ini saat dipulihkan.'
                          : _balanceGroup.description,
                      helperMaxLines: 4,
                    ),
                    items: [
                      for (final group in AccountBalanceGroup.values)
                        DropdownMenuItem(
                          value: group,
                          child: Text(group.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null && value != _balanceGroup) {
                        setState(() {
                          _balanceGroup = value;
                          _dirty = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const FormMessage(
                    'Pengelompokan tidak memindahkan uang. Buat rekening terpisah hanya jika tempat uangnya memang berbeda.',
                  ),
                  if (action.error != null) ...[
                    const SizedBox(height: 20),
                    FormMessage(action.error!, isError: true),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('save-account-edit'),
                    onPressed: action.isSaving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      action.isSaving ? 'Menyimpan…' : 'Simpan perubahan',
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

String? _validateName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Nama rekening wajib diisi.';
  if (name.length > 80) return 'Nama maksimal 80 karakter.';
  return null;
}
