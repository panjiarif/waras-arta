import 'package:flutter/material.dart';

import '../../../core/category_icons.dart';
import '../../../domain/budget.dart';
import '../../../domain/finance.dart';
import 'budget_widgets.dart';

class BudgetCategoryPickerSheet extends StatefulWidget {
  const BudgetCategoryPickerSheet({
    super.key,
    required this.groups,
    required this.conflicts,
    required this.initialIds,
  });

  final List<CategoryGroup> groups;
  final Map<int, List<BudgetConflict>> conflicts;
  final Set<int> initialIds;

  @override
  State<BudgetCategoryPickerSheet> createState() =>
      _BudgetCategoryPickerSheetState();
}

class _BudgetCategoryPickerSheetState extends State<BudgetCategoryPickerSheet> {
  late final Set<int> _selected = Set.of(widget.initialIds);
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _canAdd(CategoryGroup group, FinanceCategory category) =>
      !group.parent.isArchived &&
      !category.isArchived &&
      (widget.conflicts[category.id]?.isEmpty ?? true);

  List<FinanceCategory> _visibleChildren(CategoryGroup group) =>
      group.parent.name.toLowerCase().contains(_query)
      ? group.children
      : group.children
            .where((child) => child.name.toLowerCase().contains(_query))
            .toList();

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final group in widget.groups)
        if (_visibleChildren(group).isNotEmpty)
          (group, _visibleChildren(group)),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CustomScrollView(
                  key: const Key('budget-category-options'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Pilih subkategori',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ),
                                IconButton(
                                  key: const Key('budget-categories-cancel'),
                                  tooltip: 'Batal',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: TextField(
                              key: const Key('budget-category-search'),
                              controller: _search,
                              decoration: InputDecoration(
                                hintText: 'Cari kategori atau subkategori',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Hapus pencarian',
                                        onPressed: () {
                                          _search.clear();
                                          setState(() => _query = '');
                                        },
                                        icon: const Icon(Icons.close),
                                      ),
                              ),
                              onChanged: (value) => setState(
                                () => _query = value.trim().toLowerCase(),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                    visible.isEmpty
                        ? const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Tidak ada subkategori yang cocok.',
                                ),
                              ),
                            ),
                          )
                        : SliverList.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final (group, children) = visible[index];
                              final selectedCount = children
                                  .where(
                                    (child) => _selected.contains(child.id),
                                  )
                                  .length;
                              final selectable = children
                                  .where((child) => _canAdd(group, child))
                                  .toList();
                              final allSelected =
                                  selectable.isNotEmpty &&
                                  selectable.every(
                                    (child) => _selected.contains(child.id),
                                  );
                              final hasSelected = selectedCount > 0;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  CheckboxListTile(
                                    key: ValueKey(
                                      'budget-category-group-${group.parent.id}',
                                    ),
                                    value: hasSelected
                                        ? (allSelected ? true : null)
                                        : false,
                                    tristate: true,
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    title: Text(
                                      group.parent.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '$selectedCount dari ${children.length} dipilih',
                                    ),
                                    secondary: Icon(
                                      categoryIconFor(group.parent.iconKey),
                                    ),
                                    onChanged:
                                        hasSelected || selectable.isNotEmpty
                                        ? (_) => setState(() {
                                            if (allSelected ||
                                                (hasSelected &&
                                                    selectable.isEmpty)) {
                                              _selected.removeAll(
                                                children.map(
                                                  (child) => child.id,
                                                ),
                                              );
                                            } else {
                                              _selected.addAll(
                                                selectable.map(
                                                  (child) => child.id,
                                                ),
                                              );
                                            }
                                          })
                                        : null,
                                  ),
                                  for (final category in children)
                                    _categoryTile(group, category),
                                ],
                              );
                            },
                          ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${_selected.length} subkategori dipilih',
                      key: const Key('budget-picker-selected-count'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      key: const Key('budget-categories-done'),
                      onPressed: () =>
                          Navigator.pop(context, Set.of(_selected)),
                      child: const Text('Gunakan pilihan'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryTile(CategoryGroup group, FinanceCategory category) {
    final selected = _selected.contains(category.id);
    final archived = group.parent.isArchived || category.isArchived;
    final conflicts = widget.conflicts[category.id] ?? const <BudgetConflict>[];
    final subtitle = archived
        ? 'Diarsipkan · pilihan lama hanya dapat dilepas'
        : conflicts.isNotEmpty
        ? _conflictLabel(conflicts)
        : null;
    return CheckboxListTile(
      key: ValueKey('budget-category-${category.id}'),
      value: selected,
      controlAffinity: ListTileControlAffinity.trailing,
      dense: true,
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      secondary: Icon(categoryIconFor(category.iconKey), size: 22),
      title: Text(category.name),
      subtitle: subtitle == null ? null : Text(subtitle),
      onChanged: selected || _canAdd(group, category)
          ? (_) => setState(() {
              if (!_selected.remove(category.id)) _selected.add(category.id);
            })
          : null,
    );
  }

  String _conflictLabel(List<BudgetConflict> conflicts) {
    final examples = conflicts
        .take(2)
        .map((item) => '${item.budgetName} (${budgetPeriodLabel(item.period)})')
        .join(', ');
    final remaining = conflicts.length - 2;
    return remaining > 0
        ? 'Dipakai $examples +$remaining anggaran lain'
        : 'Dipakai $examples';
  }
}
