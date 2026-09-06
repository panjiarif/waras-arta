import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/category_icons.dart';
import '../../../domain/finance.dart';

class CategorySelectionField extends StatelessWidget {
  const CategorySelectionField({
    super.key,
    required this.groups,
    required this.value,
    required this.allowArchivedValue,
    required this.onChanged,
    required this.onManage,
  });

  final List<CategoryGroup> groups;
  final int? value;
  final bool allowArchivedValue;
  final ValueChanged<int> onChanged;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final selected = _findSelection(groups, value);
    final selectedArchived =
        selected != null &&
        (selected.child.isArchived || selected.parent.isArchived);

    return FormField<int>(
      key: ValueKey('entry-category-${value ?? 'none'}'),
      initialValue: value,
      validator: (categoryId) {
        if (categoryId == null) return 'Pilih subkategori.';
        if (selected == null) return 'Subkategori tidak ditemukan.';
        if (selectedArchived && !allowArchivedValue) {
          return 'Subkategori ini sudah diarsipkan. Pilih yang aktif.';
        }
        return null;
      },
      builder: (field) => InkWell(
        key: const Key('entry-category'),
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final activeRows = _activeRows(groups);
          if (activeRows.isEmpty) {
            onManage();
            return;
          }
          final result = await showModalBottomSheet<int>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (sheetContext) =>
                _CategoryPickerSheet(rows: activeRows, selectedId: value),
          );
          if (!context.mounted || result == null) return;
          if (result == _manageCategoriesResult) {
            onManage();
            return;
          }
          field.didChange(result);
          onChanged(result);
        },
        child: InputDecorator(
          isEmpty: selected == null,
          decoration: InputDecoration(
            labelText: 'Subkategori',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            errorText: field.errorText,
            helperText: selectedArchived && allowArchivedValue
                ? 'Kategori lama diarsipkan; tetap boleh dipertahankan.'
                : 'Pilih subkategori, bukan kelompok induknya.',
            prefixIcon: Icon(
              categoryIconFor(selected?.child.iconKey ?? 'category'),
              color: forest,
            ),
            suffixIcon: const Icon(Icons.expand_more),
          ),
          child: selected == null
              ? const Text('Pilih subkategori')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.child.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      selectedArchived
                          ? '${selected.parent.name} • Diarsipkan'
                          : selected.parent.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

const _manageCategoriesResult = -1;

class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({required this.rows, required this.selectedId});

  final List<_CategoryPickerRow> rows;
  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: (height * .76).clamp(380.0, 680.0).toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pilih subkategori',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('manage-categories-from-picker'),
                    onPressed: () =>
                        Navigator.pop(context, _manageCategoriesResult),
                    icon: const Icon(Icons.tune),
                    label: const Text('Kelola'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                key: const Key('entry-category-options'),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  if (row.child == null) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
                      child: Row(
                        children: [
                          Icon(
                            categoryIconFor(row.parent.iconKey),
                            size: 20,
                            color: forest,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              row.parent.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final child = row.child!;
                  return ListTile(
                    key: ValueKey('entry-category-option-${child.id}'),
                    selected: child.id == selectedId,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Icon(categoryIconFor(child.iconKey)),
                    title: Text(child.name),
                    subtitle: Text(row.parent.name),
                    trailing: child.id == selectedId
                        ? const Icon(Icons.check, color: forest)
                        : null,
                    onTap: () => Navigator.pop(context, child.id),
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

class _CategoryPickerRow {
  const _CategoryPickerRow({required this.parent, this.child});

  final FinanceCategory parent;
  final FinanceCategory? child;
}

List<_CategoryPickerRow> _activeRows(List<CategoryGroup> groups) {
  final rows = <_CategoryPickerRow>[];
  for (final group in groups) {
    if (group.parent.isArchived) continue;
    final children = group.children
        .where((child) => !child.isArchived)
        .toList(growable: false);
    if (children.isEmpty) continue;
    rows.add(_CategoryPickerRow(parent: group.parent));
    for (final child in children) {
      rows.add(_CategoryPickerRow(parent: group.parent, child: child));
    }
  }
  return rows;
}

({FinanceCategory parent, FinanceCategory child})? _findSelection(
  List<CategoryGroup> groups,
  int? categoryId,
) {
  if (categoryId == null) return null;
  for (final group in groups) {
    for (final child in group.children) {
      if (child.id == categoryId) {
        return (parent: group.parent, child: child);
      }
    }
  }
  return null;
}
