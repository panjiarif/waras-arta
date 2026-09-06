import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../view_models/ledger_view_model.dart';
import 'form_widgets.dart';

class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key});

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _balance = TextEditingController(text: '0');
  AccountType _type = AccountType.cash;
  DateTime _date = dateOnly(DateTime.now());

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final saved = await ref
        .read(financeActionsProvider.notifier)
        .createAccount(
          AccountDraft(
            name: _name.text,
            type: _type,
            openingBalance: parseRupiah(_balance.text)!,
            openedAt: _date,
          ),
        );
    if (saved && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Rekening tersimpan di perangkat.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final save = ref.watch(financeActionsProvider);
    return PopScope(
      canPop: !save.isSaving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Tambah rekening')),
        body: FormBody(
          child: AbsorbPointer(
            absorbing: save.isSaving,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Di mana uangmu disimpan?',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tambahkan bank, dompet tunai, atau e-wallet milikmu.',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('account-name'),
                    controller: _name,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nama rekening',
                      hintText: 'Contoh: Dompet harian',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Isi nama rekening.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AccountType>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Jenis rekening',
                    ),
                    items: [
                      for (final type in AccountType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _type = value);
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('opening-balance'),
                    controller: _balance,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Saldo awal',
                      prefixText: 'Rp ',
                      helperText:
                          'Tanpa titik/koma. Isi 0 jika mulai dari kosong.',
                      helperMaxLines: 2,
                      errorMaxLines: 3,
                    ),
                    validator: (value) =>
                        validateRupiah(value, allowZero: true),
                  ),
                  const SizedBox(height: 20),
                  EntryDateField(
                    date: _date,
                    label: 'Tanggal saldo awal',
                    onChanged: (date) {
                      if (mounted) setState(() => _date = date);
                    },
                  ),
                  const SizedBox(height: 16),
                  const FormMessage(
                    'Saldo awal bukan pemasukan. Masukkan saldo pada awal pencatatan agar transaksi berikutnya tidak terhitung dua kali.',
                  ),
                  if (save.error != null) ...[
                    const SizedBox(height: 16),
                    FormMessage(save.error!, isError: true),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('save-account'),
                    onPressed: save.isSaving ? null : _save,
                    child: Text(
                      save.isSaving ? 'Menyimpan…' : 'Simpan rekening',
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
