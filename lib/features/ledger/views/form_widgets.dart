import 'package:flutter/material.dart';

import '../../../core/formatters.dart';

class EntryDateField extends StatelessWidget {
  const EntryDateField({
    super.key,
    required this.date,
    required this.onChanged,
    this.label = 'Tanggal transaksi',
  });

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.centerLeft,
      ),
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text('$label: ${formatDate(date)}'),
      onPressed: () async {
        final selected = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: dateOnly(DateTime.now()),
          helpText: label,
        );
        if (selected != null) onChanged(selected);
      },
    );
  }
}

class FormMessage extends StatelessWidget {
  const FormMessage(this.message, {super.key, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: isError,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isError ? colors.errorContainer : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isError ? colors.onErrorContainer : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class FormBody extends StatelessWidget {
  const FormBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: child,
          ),
        ),
      ),
    );
  }
}
