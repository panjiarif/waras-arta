import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/category_icons.dart';
import '../../../domain/finance.dart';
import '../../ledger/views/form_widgets.dart';
import '../view_models/category_view_model.dart';

class CategoryListScreen extends ConsumerStatefulWidget {
  const CategoryListScreen({super.key, this.initialKind});

  final CategoryKind? initialKind;

  @override
  ConsumerState<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends ConsumerState<CategoryListScreen> {
  @override
  void initState() {
    super.initState();
    final initialKind = widget.initialKind;
    if (initialKind != null) {
      ref.read(categoryFilterProvider.notifier).selectKind(initialKind);
    }
  }

  @override
  void didUpdateWidget(covariant CategoryListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final initialKind = widget.initialKind;
    if (initialKind != null && initialKind != oldWidget.initialKind) {
      ref.read(categoryFilterProvider.notifier).selectKind(initialKind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(categoryFilterProvider);
    final actions = ref.watch(categoryActionsProvider);
    final stackKindSelector =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final query = (kind: filter.kind, includeArchived: filter.includeArchived);
    final categories = ref.watch(categoryTreeProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text('Kelola kategori')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-category-group'),
        onPressed: actions.isSaving
            ? null
            : () async {
                ref.read(categoryActionsProvider.notifier).clearError();
                await context.push('/categories/new?kind=${filter.kind.name}');
                if (mounted) {
                  ref.read(categoryActionsProvider.notifier).clearError();
                }
              },
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Tambah kelompok'),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<CategoryKind>(
                        direction: stackKindSelector
                            ? Axis.vertical
                            : Axis.horizontal,
                        expandedInsets: EdgeInsets.zero,
                        segments: const [
                          ButtonSegment(
                            value: CategoryKind.expense,
                            label: Text('Pengeluaran'),
                            icon: Icon(Icons.north_east),
                          ),
                          ButtonSegment(
                            value: CategoryKind.income,
                            label: Text('Pemasukan'),
                            icon: Icon(Icons.south_west),
                          ),
                        ],
                        selected: {filter.kind},
                        showSelectedIcon: false,
                        onSelectionChanged: actions.isSaving
                            ? null
                            : (selection) {
                                ref
                                    .read(categoryActionsProvider.notifier)
                                    .clearError();
                                ref
                                    .read(categoryFilterProvider.notifier)
                                    .selectKind(selection.single);
                              },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tampilkan yang diarsipkan'),
                        subtitle: const Text(
                          'Kategori lama tetap tersimpan pada riwayat.',
                        ),
                        value: filter.includeArchived,
                        onChanged: actions.isSaving
                            ? null
                            : (value) => ref
                                  .read(categoryFilterProvider.notifier)
                                  .setIncludeArchived(value),
                      ),
                      if (actions.error != null) ...[
                        const SizedBox(height: 8),
                        FormMessage(actions.error!, isError: true),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: categories.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => _CategoryLoadError(query: query),
                    data: (groups) => _CategoryTreeList(
                      groups: groups,
                      kind: filter.kind,
                      busy: actions.isSaving,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryLoadError extends ConsumerWidget {
  const _CategoryLoadError({required this.query});

  final CategoryTreeQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const FormMessage(
          'Kategori belum dapat dimuat. Data di perangkat tidak diubah.',
          isError: true,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => ref.invalidate(categoryTreeProvider(query)),
          icon: const Icon(Icons.refresh),
          label: const Text('Coba lagi'),
        ),
      ],
    ),
  );
}

class _CategoryTreeList extends StatelessWidget {
  const _CategoryTreeList({
    required this.groups,
    required this.kind,
    required this.busy,
  });

  final List<CategoryGroup> groups;
  final CategoryKind kind;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 120),
        children: [
          Icon(
            Icons.category_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Belum ada kategori ${categoryKindLabel(kind).toLowerCase()}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Buat satu kelompok beserta subkategori pertamanya. Transaksi memilih subkategori, bukan kelompok.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.separated(
      key: PageStorageKey('category-list-${kind.name}'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _CategoryGroupSection(group: groups[index], busy: busy);
      },
    );
  }
}

class _CategoryGroupSection extends StatelessWidget {
  const _CategoryGroupSection({required this.group, required this.busy});

  final CategoryGroup group;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('category-group-${group.parent.id}'),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        _CategoryTile(
          category: group.parent,
          childCount: group.children.length,
          busy: busy,
        ),
        for (var index = 0; index < group.children.length; index++) ...[
          Divider(height: 1, indent: index == 0 ? 16 : 76, endIndent: 12),
          _CategoryTile(
            category: group.children[index],
            parent: group.parent,
            busy: busy,
          ),
        ],
      ],
    ),
  );
}

enum _CategoryMenuAction { addChild, edit, toggleArchive, delete }

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({
    required this.category,
    this.parent,
    this.childCount,
    required this.busy,
  });

  final FinanceCategory category;
  final FinanceCategory? parent;
  final int? childCount;
  final bool busy;

  bool get isChild => parent != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectivelyArchived =
        category.isArchived || (parent?.isArchived ?? false);
    return Opacity(
      opacity: effectivelyArchived ? .62 : 1,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isChild ? 28 : 16,
          isChild ? 9 : 12,
          8,
          isChild ? 9 : 12,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: isChild ? 18 : 21,
              backgroundColor: isChild
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: forest,
              child: Icon(
                categoryIconFor(category.iconKey),
                size: isChild ? 20 : 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isChild ? FontWeight.w600 : FontWeight.w700,
                      fontSize: isChild ? 15 : 17,
                    ),
                  ),
                  if (!isChild) ...[
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '$childCount subkategori',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (category.isArchived) const _ArchivedBadge(),
                      ],
                    ),
                  ] else if (category.isArchived) ...[
                    const SizedBox(height: 4),
                    const _ArchivedBadge(),
                  ],
                ],
              ),
            ),
            PopupMenuButton<_CategoryMenuAction>(
              key: ValueKey('category-menu-${category.id}'),
              enabled: !busy,
              tooltip: 'Tindakan untuk ${category.name}',
              onSelected: (action) => _handleAction(context, ref, action),
              itemBuilder: (context) => [
                if (!isChild)
                  PopupMenuItem(
                    value: _CategoryMenuAction.addChild,
                    enabled: !category.isArchived,
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.add),
                      title: Text('Tambah subkategori'),
                    ),
                  ),
                const PopupMenuItem(
                  value: _CategoryMenuAction.edit,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                  ),
                ),
                PopupMenuItem(
                  value: _CategoryMenuAction.toggleArchive,
                  enabled: parent?.isArchived != true || category.isArchived,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      category.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                    ),
                    title: Text(category.isArchived ? 'Pulihkan' : 'Arsipkan'),
                  ),
                ),
                if (!category.isBuiltIn) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    key: ValueKey('delete-category-${category.id}'),
                    value: _CategoryMenuAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        'Hapus permanen',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _CategoryMenuAction action,
  ) async {
    ref.read(categoryActionsProvider.notifier).clearError();
    final kindQuery = 'kind=${category.kind.name}';
    switch (action) {
      case _CategoryMenuAction.addChild:
        await context.push(
          '/categories/${category.id}/children/new?$kindQuery',
        );
        if (context.mounted) {
          ref.read(categoryActionsProvider.notifier).clearError();
        }
        return;
      case _CategoryMenuAction.edit:
        await context.push('/categories/${category.id}/edit?$kindQuery');
        if (context.mounted) {
          ref.read(categoryActionsProvider.notifier).clearError();
        }
        return;
      case _CategoryMenuAction.toggleArchive:
        await _toggleArchived(context, ref);
        return;
      case _CategoryMenuAction.delete:
        await _deleteCategory(context, ref);
        return;
    }
  }

  Future<void> _deleteCategory(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(categoryActionsProvider.notifier);
    final impact = await actions.inspectDeletion(category.id);
    if (!context.mounted || impact == null) return;

    if (!impact.canDelete) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('category-delete-blocked'),
          scrollable: true,
          title: const Text('Kategori tidak dapat dihapus'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final reason in _categoryDeletionBlockReasons(impact))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•'),
                      const SizedBox(width: 8),
                      Expanded(child: Text(reason)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                impact.category.isArchived
                    ? 'Kategori tetap aman di arsip dan riwayat tidak berubah.'
                    : 'Arsipkan kategori bila tidak ingin menampilkannya pada transaksi baru; riwayat tetap tersimpan.',
              ),
            ],
          ),
          actions: [
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(
          impact.isGroup
              ? 'Hapus kelompok ${category.name}?'
              : 'Hapus ${category.name}?',
        ),
        content: Text(
          impact.isGroup
              ? 'Kelompok dan ${impact.childCount} subkategori akan dihapus permanen. Tindakan ini tidak dapat dibatalkan.'
              : 'Subkategori ini akan dihapus permanen. Tindakan ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('confirm-delete-category'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus permanen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final deleted = await actions.deleteCategory(category.id);
    if (!context.mounted || !deleted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Kategori dihapus permanen.')));
  }

  Future<void> _toggleArchived(BuildContext context, WidgetRef ref) async {
    final willArchive = !category.isArchived;
    if (willArchive) {
      final explanation = isChild
          ? 'Subkategori tidak dapat dipilih untuk transaksi baru. Riwayat lama tetap tersimpan.'
          : 'Kelompok dan subkategorinya tidak dapat dipilih untuk transaksi baru. Riwayat lama tetap tersimpan.';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Arsipkan ${category.name}?'),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              key: const Key('confirm-archive-category'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Arsipkan'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    final saved = await ref
        .read(categoryActionsProvider.notifier)
        .setArchived(category.id, willArchive);
    if (!context.mounted || !saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          willArchive ? 'Kategori diarsipkan.' : 'Kategori dipulihkan.',
        ),
      ),
    );
  }
}

List<String> _categoryDeletionBlockReasons(CategoryDeletionImpact impact) => [
  if (impact.containsBuiltInCategory) 'Kategori bawaan tidak dapat dihapus.',
  if (impact.referencedEntryCount > 0)
    'Digunakan pada ${impact.referencedEntryCount} transaksi.',
  if (impact.referencedBudgetCount > 0)
    'Digunakan pada ${impact.referencedBudgetCount} anggaran.',
  if (impact.wouldLeaveParentWithoutChildren)
    'Kelompok harus memiliki minimal satu subkategori.',
  if (impact.wouldRemoveLastEffectiveLeaf)
    'Harus tersisa minimal satu subkategori aktif untuk jenis transaksi ini.',
];

class _ArchivedBadge extends StatelessWidget {
  const _ArchivedBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text('Arsip', style: TextStyle(fontSize: 11)),
    ),
  );
}
