import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../domain/finance.dart';
import 'form_widgets.dart';

IconData accountIconFor(AccountType type) => switch (type) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.bank => Icons.account_balance_outlined,
  AccountType.eWallet => Icons.phone_android_outlined,
  AccountType.other => Icons.savings_outlined,
};

class AccountStatusBadge extends StatelessWidget {
  const AccountStatusBadge({super.key, required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: archived
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Text(
        archived ? 'Diarsipkan' : 'Aktif',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class AccountDetailRow extends StatelessWidget {
  const AccountDetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 124,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class AccountAsyncScreen extends StatelessWidget {
  const AccountAsyncScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    this.onRetry,
    this.loading = false,
  });

  const AccountAsyncScreen.loading({super.key, required this.title})
    : icon = Icons.account_balance_wallet_outlined,
      message = '',
      onRetry = null,
      loading = true;

  const AccountAsyncScreen.notFound({super.key, required this.title})
    : icon = Icons.search_off,
      message =
          'Rekening ini mungkin sudah dihapus atau alamatnya tidak valid.',
      onRetry = null,
      loading = false;

  factory AccountAsyncScreen.error({
    Key? key,
    required String title,
    required VoidCallback onRetry,
  }) => AccountAsyncScreen(
    key: key,
    title: title,
    icon: Icons.error_outline,
    message: 'Rekening belum dapat dimuat. Coba kembali beberapa saat lagi.',
    onRetry: onRetry,
  );

  final String title;
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FormBody(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(icon, size: 48, color: forest),
                const SizedBox(height: 16),
                FormMessage(message, isError: onRetry != null),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba lagi'),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Kembali'),
                ),
              ],
            ),
    ),
  );
}
