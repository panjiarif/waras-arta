import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/category_icons.dart';
import '../../ledger/views/form_widgets.dart';

class CategoryIconField extends StatelessWidget {
  const CategoryIconField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Ikon',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const Key('category-icon-field'),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(58),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      alignment: Alignment.centerLeft,
    ),
    onPressed: () async {
      final selected = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => CategoryIconPicker(selectedKey: value),
      );
      if (selected != null) onChanged(selected);
    },
    child: Row(
      children: [
        Icon(categoryIconFor(value), color: forest),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(
                categoryIconLabelFor(value),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const Icon(Icons.expand_more),
      ],
    ),
  );
}

class CategoryIconPicker extends StatelessWidget {
  const CategoryIconPicker({super.key, required this.selectedKey});

  final String selectedKey;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: (height * .72).clamp(360.0, 620.0).toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Pilih ikon',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.maxWidth / 88)
                      .floor()
                      .clamp(3, 6)
                      .toInt();
                  return GridView.builder(
                    key: const Key('category-icon-grid'),
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: .9,
                    ),
                    itemCount: categoryIconOptions.length,
                    itemBuilder: (context, index) {
                      final option = categoryIconOptions[index];
                      final selected = option.key == selectedKey;
                      return Semantics(
                        button: true,
                        selected: selected,
                        label: 'Ikon ${option.label}',
                        child: Material(
                          color: selected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            key: ValueKey('category-icon-${option.key}'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(context, option.key),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(option.icon, size: 28),
                                  const SizedBox(height: 6),
                                  Text(
                                    option.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryAsyncScreen extends StatelessWidget {
  const CategoryAsyncScreen.loading({super.key, required this.title})
    : message = null,
      onRetry = null;

  const CategoryAsyncScreen.error({
    super.key,
    required this.title,
    required this.onRetry,
  }) : message =
           'Kategori belum dapat dimuat. Coba kembali beberapa saat lagi.';

  const CategoryAsyncScreen.notFound({super.key, required this.title})
    : message = 'Kategori tidak ditemukan atau sudah tidak tersedia.',
      onRetry = null;

  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FormBody(
      child: message == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  onRetry == null ? Icons.search_off : Icons.error_outline,
                  size: 48,
                  color: forest,
                ),
                const SizedBox(height: 16),
                FormMessage(message!, isError: onRetry != null),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba lagi'),
                  ),
                ],
              ],
            ),
    ),
  );
}
