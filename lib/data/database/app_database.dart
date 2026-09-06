import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('AccountRow')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get normalizedName => text().unique()();
  IntColumn get type => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK (type BETWEEN 0 AND 3)',
    'CHECK (length(trim(name)) BETWEEN 1 AND 80)',
    'CHECK (length(trim(normalized_name)) > 0)',
  ];
}

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  @ReferenceName('subcategories')
  IntColumn get parentId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get kind => integer()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get normalizedName => text().withLength(min: 1, max: 80)();
  TextColumn get iconKey => text().withLength(min: 1, max: 40)();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get systemKey => text().nullable().unique()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK (kind IN (0, 1))',
    'CHECK (parent_id IS NULL OR parent_id <> id)',
    'CHECK (length(trim(name)) BETWEEN 1 AND 80)',
    'CHECK (length(trim(normalized_name)) BETWEEN 1 AND 80)',
    'CHECK (length(trim(icon_key)) BETWEEN 1 AND 40)',
    'CHECK (sort_order BETWEEN 0 AND 1000000)',
    'CHECK (system_key IS NULL OR length(trim(system_key)) BETWEEN 1 AND 80)',
  ];
}

/// One row is one transaction, including transfers between two accounts.
@DataClassName('LedgerRow')
class LedgerEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get kind => integer()();
  @ReferenceName('sourceEntries')
  IntColumn get accountId => integer().references(Accounts, #id)();
  @ReferenceName('destinationEntries')
  IntColumn get destinationAccountId =>
      integer().nullable().references(Accounts, #id)();
  IntColumn get amount => integer()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// YYYYMMDD civil date. Never converted through a timezone or UTC timestamp.
  IntColumn get occurredDay => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK (kind BETWEEN 0 AND 3)',
    // Keep schema-v1 literals stable; domain changes require a migration.
    'CHECK (amount BETWEEN 1 AND 999999999999)',
    'CHECK (occurred_day BETWEEN 20000101 AND 99991231)',
    'CHECK (length(note) <= 500)',
    '''CHECK (
      (kind IN (0, 1) AND destination_account_id IS NULL AND category_id IS NOT NULL)
      OR (kind = 2 AND destination_account_id IS NOT NULL
        AND destination_account_id <> account_id AND category_id IS NULL)
      OR (kind = 3 AND destination_account_id IS NULL AND category_id IS NULL)
    )''',
  ];
}

@DriftDatabase(tables: [Accounts, Categories, LedgerEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'waras_arta',
              native: DriftNativeOptions(
                databaseDirectory: getApplicationSupportDirectory,
              ),
            ),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _seedDefaultCategories();
      await _createSchemaExtras();
    },
    onUpgrade: (migrator, from, to) async {
      if (from >= 2) return;
      await customStatement('PRAGMA foreign_keys = OFF');
      try {
        await transaction(() async {
          await migrator.createTable(categories);
          await _seedDefaultCategories();
          final unmapped = await customSelect('''
            SELECT COUNT(*) AS amount
            FROM ledger_entries AS l
            WHERE l.kind IN (0, 1) AND NOT EXISTS (
              SELECT 1 FROM categories AS c
              WHERE c.kind = l.kind AND c.parent_id IS NULL
                AND c.name = l.category
            )
          ''').getSingle();
          if (unmapped.read<int>('amount') != 0) {
            throw StateError('Kategori transaksi lama tidak dapat dipetakan.');
          }
          await migrator.alterTable(
            TableMigration(
              ledgerEntries,
              newColumns: [ledgerEntries.categoryId],
              columnTransformer: {
                ledgerEntries.categoryId: const CustomExpression<int>('''
                  (SELECT child.id
                   FROM categories AS parent
                   JOIN categories AS child ON child.parent_id = parent.id
                   WHERE parent.kind = ledger_entries.kind
                     AND parent.name = ledger_entries.category
                     AND child.name = 'Umum')
                '''),
              },
            ),
          );
          await _createSchemaExtras();
          final invalid = await customSelect('''
            SELECT COUNT(*) AS amount
            FROM ledger_entries AS l
            LEFT JOIN categories AS c ON c.id = l.category_id
            WHERE (l.kind IN (0, 1) AND
                    (c.id IS NULL OR c.kind <> l.kind OR c.parent_id IS NULL))
               OR (l.kind IN (2, 3) AND l.category_id IS NOT NULL)
          ''').getSingle();
          if (invalid.read<int>('amount') != 0) {
            throw StateError('Hasil migrasi kategori tidak valid.');
          }
          final foreignKeyErrors = await customSelect(
            'PRAGMA foreign_key_check',
          ).get();
          if (foreignKeyErrors.isNotEmpty) {
            throw StateError('Foreign key tidak valid setelah migrasi.');
          }
        });
      } finally {
        await customStatement('PRAGMA foreign_keys = ON');
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seedDefaultCategories() async {
    final now = DateTime.now();
    for (final seed in _defaultCategorySeeds) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: Value(seed.parentId),
          kind: seed.kind,
          name: seed.name,
          normalizedName: seed.name.toLowerCase(),
          iconKey: seed.iconKey,
          sortOrder: Value(seed.sortOrder),
          systemKey: Value(seed.systemKey),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: Value(seed.childId),
          parentId: Value(seed.parentId),
          kind: seed.kind,
          name: 'Umum',
          normalizedName: 'umum',
          iconKey: seed.iconKey,
          sortOrder: const Value(0),
          systemKey: Value('${seed.systemKey}.general'),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  Future<void> _createSchemaExtras() async {
    const statements = [
      '''CREATE UNIQUE INDEX IF NOT EXISTS categories_unique_root_name
         ON categories (kind, normalized_name) WHERE parent_id IS NULL''',
      '''CREATE UNIQUE INDEX IF NOT EXISTS categories_unique_child_name
         ON categories (parent_id, normalized_name) WHERE parent_id IS NOT NULL''',
      '''CREATE INDEX IF NOT EXISTS categories_tree_order
         ON categories (kind, parent_id, is_archived, sort_order, normalized_name)''',
      '''CREATE INDEX IF NOT EXISTS ledger_entries_occurred_day_id
         ON ledger_entries (occurred_day DESC, id DESC)''',
      '''CREATE INDEX IF NOT EXISTS ledger_entries_account_id
         ON ledger_entries (account_id)''',
      '''CREATE INDEX IF NOT EXISTS ledger_entries_destination_account_id
         ON ledger_entries (destination_account_id)''',
      '''CREATE INDEX IF NOT EXISTS ledger_entries_category_id
         ON ledger_entries (category_id)''',
      '''CREATE TRIGGER IF NOT EXISTS categories_validate_parent_insert
         BEFORE INSERT ON categories
         WHEN NEW.parent_id IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM categories AS parent
           WHERE parent.id = NEW.parent_id AND parent.parent_id IS NULL
             AND parent.kind = NEW.kind)
         BEGIN SELECT RAISE(ABORT, 'invalid category parent'); END''',
      '''CREATE TRIGGER IF NOT EXISTS categories_immutable_structure
         BEFORE UPDATE OF parent_id, kind ON categories
         WHEN NEW.parent_id IS NOT OLD.parent_id OR NEW.kind <> OLD.kind
         BEGIN SELECT RAISE(ABORT, 'immutable category structure'); END''',
      '''CREATE TRIGGER IF NOT EXISTS ledger_validate_category_insert
         BEFORE INSERT ON ledger_entries
         WHEN NEW.kind IN (0, 1) AND NOT EXISTS (
           SELECT 1 FROM categories AS category
           WHERE category.id = NEW.category_id
             AND category.kind = NEW.kind
             AND category.parent_id IS NOT NULL)
         BEGIN SELECT RAISE(ABORT, 'invalid ledger category'); END''',
      '''CREATE TRIGGER IF NOT EXISTS ledger_validate_category_update
         BEFORE UPDATE OF kind, category_id ON ledger_entries
         WHEN NEW.kind IN (0, 1) AND NOT EXISTS (
           SELECT 1 FROM categories AS category
           WHERE category.id = NEW.category_id
             AND category.kind = NEW.kind
             AND category.parent_id IS NOT NULL)
         BEGIN SELECT RAISE(ABORT, 'invalid ledger category'); END''',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }
}

class _DefaultCategorySeed {
  const _DefaultCategorySeed({
    required this.parentId,
    required this.childId,
    required this.kind,
    required this.name,
    required this.iconKey,
    required this.systemKey,
    required this.sortOrder,
  });

  final int parentId;
  final int childId;
  final int kind;
  final String name;
  final String iconKey;
  final String systemKey;
  final int sortOrder;
}

const _defaultCategorySeeds = [
  _DefaultCategorySeed(
    parentId: 1,
    childId: 2,
    kind: 0,
    name: 'Gaji',
    iconKey: 'work',
    systemKey: 'income.salary',
    sortOrder: 0,
  ),
  _DefaultCategorySeed(
    parentId: 3,
    childId: 4,
    kind: 0,
    name: 'Usaha',
    iconKey: 'storefront',
    systemKey: 'income.business',
    sortOrder: 1,
  ),
  _DefaultCategorySeed(
    parentId: 5,
    childId: 6,
    kind: 0,
    name: 'Hadiah',
    iconKey: 'redeem',
    systemKey: 'income.gift',
    sortOrder: 2,
  ),
  _DefaultCategorySeed(
    parentId: 7,
    childId: 8,
    kind: 0,
    name: 'Lainnya',
    iconKey: 'more_horiz',
    systemKey: 'income.other',
    sortOrder: 3,
  ),
  _DefaultCategorySeed(
    parentId: 9,
    childId: 10,
    kind: 1,
    name: 'Makan & minum',
    iconKey: 'restaurant',
    systemKey: 'expense.food_drink',
    sortOrder: 0,
  ),
  _DefaultCategorySeed(
    parentId: 11,
    childId: 12,
    kind: 1,
    name: 'Transportasi',
    iconKey: 'directions_car',
    systemKey: 'expense.transport',
    sortOrder: 1,
  ),
  _DefaultCategorySeed(
    parentId: 13,
    childId: 14,
    kind: 1,
    name: 'Belanja',
    iconKey: 'shopping_bag',
    systemKey: 'expense.shopping',
    sortOrder: 2,
  ),
  _DefaultCategorySeed(
    parentId: 15,
    childId: 16,
    kind: 1,
    name: 'Tagihan',
    iconKey: 'receipt_long',
    systemKey: 'expense.bills',
    sortOrder: 3,
  ),
  _DefaultCategorySeed(
    parentId: 17,
    childId: 18,
    kind: 1,
    name: 'Kesehatan',
    iconKey: 'medical_services',
    systemKey: 'expense.health',
    sortOrder: 4,
  ),
  _DefaultCategorySeed(
    parentId: 19,
    childId: 20,
    kind: 1,
    name: 'Hiburan',
    iconKey: 'movie',
    systemKey: 'expense.entertainment',
    sortOrder: 5,
  ),
  _DefaultCategorySeed(
    parentId: 21,
    childId: 22,
    kind: 1,
    name: 'Lainnya',
    iconKey: 'more_horiz',
    systemKey: 'expense.other',
    sortOrder: 6,
  ),
];
