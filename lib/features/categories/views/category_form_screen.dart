import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/category_icons.dart';
import '../../../domain/finance.dart';
import '../../ledger/views/form_widgets.dart';
import '../view_models/category_view_model.dart';
import 'category_widgets.dart';

class CategoryGroupFormScreen extends ConsumerStatefulWidget {
  const CategoryGroupFormScreen({
    super.key,
    this.initialKind = CategoryKind.expense,
  });

  final CategoryKind initialKind;

  @override
  ConsumerState<CategoryGroupFormScreen> createState() =>
      _CategoryGroupFormScreenState();
}

class _CategoryGroupFormScreenState
    extends ConsumerState<CategoryGroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _parentName = TextEditingController();
  final _childName = TextEditingController();
  late CategoryKind _kind;
  late String _parentIcon;
  String _childIcon = 'more_horiz';
  bool _dirty = false;
  bool _allowPop = false;
  bool _confirmingDiscard = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _parentIcon = defaultCategoryIconKey(_kind);
    _parentName.addListener(_markDirty);
    _childName.addListener(_markDirty);
    ref.read(categoryActionsProvider.notifier).clearError();
  }

  @override
  void dispose() {
    _parentName.removeListener(_markDirty);
    _childName.removeListener(_markDirty);
    _parentName.dispose();
    _childName.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final saved = await ref
        .read(categoryActionsProvider.notifier)
        .createGroup(
          CategoryGroupDraft(
            kind: _kind,
            parentName: _parentName.text,
            parentIconKey: _parentIcon,
            firstChildName: _childName.text,
            firstChildIconKey: _childIcon,
          ),
        );
    if (!saved || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    ref.read(categoryFilterProvider.notifier).selectKind(_kind);
    setState(() {
      _dirty = false;
      _allowPop = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    router.pop(true);
    messenger.showSnackBar(
      const SnackBar(content: Text('Kelompok kategori dibuat.')),
    );
  }

  Future<void> _confirmDiscard() async {
    if (_confirmingDiscard) return;
    _confirmingDiscard = true;
    final discard = await _showDiscardCategoryDialog(context);
    if (!mounted) return;
    _confirmingDiscard = false;
    if (!discard) return;
    ref.read(categoryActionsProvider.notifier).clearError();
    final router = GoRouter.of(context);
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(categoryActionsProvider);
    final stackKindSelector =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    return PopScope(
      canPop: _allowPop || (!action.isSaving && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !action.isSaving && !_allowPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Tambah kelompok')),
        body: FormBody(
          child: AbsorbPointer(
            absorbing: action.isSaving,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Kelompok baru',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Setiap kelompok dibuat bersama satu subkategori agar langsung dapat digunakan saat mencatat transaksi.',
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<CategoryKind>(
                    direction: stackKindSelector
                        ? Axis.vertical
                        : Axis.horizontal,
                    expandedInsets: EdgeInsets.zero,
                    segments: const [
                      ButtonSegment(
                        value: CategoryKind.expense,
                        label: Text('Pengeluaran'),
                      ),
                      ButtonSegment(
                        value: CategoryKind.income,
                        label: Text('Pemasukan'),
                      ),
                    ],
                    selected: {_kind},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      final next = selection.single;
                      if (next == _kind) return;
                      setState(() {
                        _kind = next;
                        _parentIcon = defaultCategoryIconKey(next);
                        _dirty = true;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    icon: Icons.folder_outlined,
                    title: 'Kelompok ${categoryKindLabel(_kind).toLowerCase()}',
                    description:
                        'Kelompok mengatur beberapa subkategori sejenis.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('category-parent-name'),
                    controller: _parentName,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nama kelompok',
                      hintText: 'Contoh: Kebutuhan harian',
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 12),
                  CategoryIconField(
                    key: const Key('category-parent-icon'),
                    value: _parentIcon,
                    label: 'Ikon kelompok',
                    onChanged: (value) => setState(() {
                      _parentIcon = value;
                      _dirty = true;
                    }),
                  ),
                  const SizedBox(height: 30),
                  const Divider(),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    icon: Icons.subdirectory_arrow_right,
                    title: 'Subkategori pertama',
                    description: 'Transaksi akan memilih subkategori ini, bukan kelompoknya.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('category-first-child-name'),
                    controller: _childName,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Nama subkategori',
                      hintText: 'Contoh: Belanja dapur',
                    ),
                    validator: _validateName,
                    onFieldSubmitted: (_) async {
                      if (!action.isSaving) await _save();
                    },
                  ),
                  const SizedBox(height: 12),
                  CategoryIconField(
                    key: const Key('category-first-child-icon'),
                    value: _childIcon,
                    label: 'Ikon subkategori',
                    onChanged: (value) => setState(() {
                      _childIcon = value;
                      _dirty = true;
                    }),
                  ),
                  if (action.error != null) ...[
                    const SizedBox(height: 20),
                    FormMessage(action.error!, isError: true),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('save-category-group'),
                    onPressed: action.isSaving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      action.isSaving ? 'Menyimpan…' : 'Simpan kelompok',
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

class CategorySubcategoryFormScreen extends ConsumerWidget {
  const CategorySubcategoryFormScreen({
    super.key,
    required this.parentId,
    required this.kind,
  });

  final int parentId;
  final CategoryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (kind: kind, includeArchived: true);
    final tree = ref.watch(categoryTreeProvider(query));
    return tree.when(
      loading: () =>
          const CategoryAsyncScreen.loading(title: 'Tambah subkategori'),
      error: (_, _) => CategoryAsyncScreen.error(
        title: 'Tambah subkategori',
        onRetry: () => ref.invalidate(categoryTreeProvider(query)),
      ),
      data: (groups) {
        final group = _findGroup(groups, parentId);
        if (group == null) {
          return const CategoryAsyncScreen.notFound(
            title: 'Tambah subkategori',
          );
        }
        return _SingleCategoryForm(parent: group.parent);
      },
    );
  }
}

class CategoryEditScreen extends ConsumerWidget {
  const CategoryEditScreen({
    super.key,
    required this.categoryId,
    required this.kind,
  });

  final int categoryId;
  final CategoryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (kind: kind, includeArchived: true);
    final tree = ref.watch(categoryTreeProvider(query));
    return tree.when(
      loading: () => const CategoryAsyncScreen.loading(title: 'Edit kategori'),
      error: (_, _) => CategoryAsyncScreen.error(
        title: 'Edit kategori',
        onRetry: () => ref.invalidate(categoryTreeProvider(query)),
      ),
      data: (groups) {
        final match = _findCategory(groups, categoryId);
        if (match == null) {
          return const CategoryAsyncScreen.notFound(title: 'Edit kategori');
        }
        return _SingleCategoryForm(
          key: ValueKey('category-editor-${match.category.id}'),
          parent: match.parent,
          initialCategory: match.category,
        );
      },
    );
  }
}

class _SingleCategoryForm extends ConsumerStatefulWidget {
  const _SingleCategoryForm({super.key, this.parent, this.initialCategory})
    : assert(parent != null || initialCategory != null);

  final FinanceCategory? parent;
  final FinanceCategory? initialCategory;

  @override
  ConsumerState<_SingleCategoryForm> createState() =>
      _SingleCategoryFormState();
}

class _SingleCategoryFormState extends ConsumerState<_SingleCategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _iconKey;
  bool _dirty = false;
  bool _allowPop = false;
  bool _confirmingDiscard = false;

  bool get _isEditing => widget.initialCategory != null;
  bool get _isChild => widget.initialCategory?.parentId != null || !_isEditing;
  CategoryKind get _kind => widget.initialCategory?.kind ?? widget.parent!.kind;

  @override
  void initState() {
    super.initState();
    final category = widget.initialCategory;
    _name = TextEditingController(text: category?.name ?? '');
    _iconKey = category?.iconKey ?? widget.parent?.iconKey ?? 'more_horiz';
    _name.addListener(_markDirty);
    ref.read(categoryActionsProvider.notifier).clearError();
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
    final draft = CategoryDraft(
      parentId: widget.initialCategory?.parentId ?? widget.parent?.id,
      name: _name.text,
      iconKey: _iconKey,
      sortOrder: widget.initialCategory?.sortOrder ?? 0,
    );
    final actions = ref.read(categoryActionsProvider.notifier);
    final saved = _isEditing
        ? await actions.updateCategory(widget.initialCategory!.id, draft)
        : await actions.createSubcategory(draft);
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
      SnackBar(
        content: Text(
          _isEditing ? 'Perubahan kategori tersimpan.' : 'Subkategori dibuat.',
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    if (_confirmingDiscard) return;
    _confirmingDiscard = true;
    final discard = await _showDiscardCategoryDialog(context);
    if (!mounted) return;
    _confirmingDiscard = false;
    if (!discard) return;
    ref.read(categoryActionsProvider.notifier).clearError();
    final router = GoRouter.of(context);
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(categoryActionsProvider);
    final category = widget.initialCategory;
    final title = _isEditing
        ? (_isChild ? 'Edit subkategori' : 'Edit kelompok')
        : 'Tambah subkategori';
    return PopScope(
      canPop: _allowPop || (!action.isSaving && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !action.isSaving && !_allowPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: FormBody(
          child: AbsorbPointer(
            absorbing: action.isSaving,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    '${categoryKindLabel(_kind)} • Nama dan ikon dapat diubah.',
                  ),
                  if (_isChild && widget.parent != null) ...[
                    const SizedBox(height: 20),
                    _ParentCard(parent: widget.parent!),
                  ],
                  if (category?.isArchived ?? false) ...[
                    const SizedBox(height: 16),
                    const FormMessage(
                      'Kategori ini sedang diarsipkan. Perubahan nama dan ikon tetap berlaku pada riwayat lama.',
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('category-name'),
                    controller: _name,
                    autofocus: !_isEditing,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: _isChild
                          ? 'Nama subkategori'
                          : 'Nama kelompok',
                      hintText: _isChild
                          ? 'Contoh: Belanja dapur'
                          : 'Contoh: Kebutuhan harian',
                    ),
                    validator: _validateName,
                    onFieldSubmitted: (_) async {
                      if (!action.isSaving) await _save();
                    },
                  ),
                  const SizedBox(height: 12),
                  CategoryIconField(
                    value: _iconKey,
                    label: _isChild ? 'Ikon subkategori' : 'Ikon kelompok',
                    onChanged: (value) => setState(() {
                      _iconKey = value;
                      _dirty = true;
                    }),
                  ),
                  if (action.error != null) ...[
                    const SizedBox(height: 20),
                    FormMessage(action.error!, isError: true),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('save-category'),
                    onPressed: action.isSaving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      action.isSaving ? 'Menyimpan…' : 'Simpan kategori',
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(description),
          ],
        ),
      ),
    ],
  );
}

class _ParentCard extends StatelessWidget {
  const _ParentCard({required this.parent});

  final FinanceCategory parent;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(categoryIconFor(parent.iconKey)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parent.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Text('Kelompok induk'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

CategoryGroup? _findGroup(List<CategoryGroup> groups, int parentId) {
  for (final group in groups) {
    if (group.parent.id == parentId) return group;
  }
  return null;
}

_CategoryMatch? _findCategory(List<CategoryGroup> groups, int categoryId) {
  for (final group in groups) {
    if (group.parent.id == categoryId) {
      return _CategoryMatch(category: group.parent);
    }
    for (final child in group.children) {
      if (child.id == categoryId) {
        return _CategoryMatch(category: child, parent: group.parent);
      }
    }
  }
  return null;
}

class _CategoryMatch {
  const _CategoryMatch({required this.category, this.parent});

  final FinanceCategory category;
  final FinanceCategory? parent;
}

String? _validateName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Nama wajib diisi.';
  if (name.length > 80) return 'Nama maksimal 80 karakter.';
  return null;
}

Future<bool> _showDiscardCategoryDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Buang perubahan kategori?'),
        content: const Text(
          'Nama, ikon, atau jenis kategori yang diubah belum disimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Tetap di sini'),
          ),
          FilledButton(
            key: const Key('discard-category-changes'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Buang perubahan'),
          ),
        ],
      ),
    ) ??
    false;
