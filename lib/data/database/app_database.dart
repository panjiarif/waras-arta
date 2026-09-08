import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.steps.dart';

part 'app_database.g.dart';

@DataClassName('AccountRow')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get normalizedName => text().unique()();
  IntColumn get type => integer()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
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
  TextColumn get note => text().withDefault(const Constant(''))();

  /// YYYYMMDD civil date. Never converted through a timezone or UTC timestamp.
  IntColumn get occurredDay => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK (kind BETWEEN 0 AND 3)',
    '''CHECK (
      (kind IN (0, 1, 2) AND amount BETWEEN 1 AND 999999999999)
      OR (kind = 3 AND amount BETWEEN -999999999999 AND 999999999999
        AND amount <> 0)
    )''',
    'CHECK (occurred_day BETWEEN 20000101 AND 99991231)',
    'CHECK (length(note) <= 500)',
    '''CHECK (
      (kind IN (0, 1) AND destination_account_id IS NULL)
      OR (kind = 2 AND destination_account_id IS NOT NULL
        AND destination_account_id <> account_id)
      OR (kind = 3 AND destination_account_id IS NULL)
    )''',
  ];
}

@DataClassName('LedgerAllocationRow')
class LedgerAllocations extends Table {
  @ReferenceName('allocations')
  IntColumn get entryId =>
      integer().references(LedgerEntries, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  @ReferenceName('allocationEntries')
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.restrict)();
  IntColumn get amount => integer()();

  @override
  Set<Column<Object>> get primaryKey => {entryId, position};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {entryId, categoryId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (position BETWEEN 0 AND 49)',
    'CHECK (amount BETWEEN 1 AND 999999999999)',
  ];
}

@DriftDatabase(tables: [Accounts, Categories, LedgerEntries, LedgerAllocations])
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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _seedDefaultCategories();
      await _createCommonSchemaExtras();
      await _createSchemaV3Extras();
      await _createSchemaV4Extras();
    },
    onUpgrade: (migrator, from, to) async {
      if (from >= to) return;
      await customStatement('PRAGMA foreign_keys = OFF');
      try {
        await transaction(() async {
          final runSteps = stepByStep(
            from1To2: _migrateV1ToV2,
            from2To3: _migrateV2ToV3,
            from3To4: _migrateV3ToV4,
          );
          await runSteps(migrator, from, to);

          if (to >= 2) {
            await _createCommonSchemaExtras();
          }
          if (to == 2 || to == 3) {
            await _createLegacyLedgerCategoryExtras();
          }
          if (to >= 3) {
            await _createSchemaV3Extras();
          }
          if (to >= 4) {
            await _createSchemaV4Extras();
          }

          if (to >= 2 && to < 4) {
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
          }
          if (to >= 4) {
            await verifyLedgerAllocationIntegrity();
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

  Future<void> _migrateV1ToV2(Migrator migrator, Schema2 schema) async {
    await migrator.createTable(schema.categories);
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
        schema.ledgerEntries,
        newColumns: [schema.ledgerEntries.categoryId],
        columnTransformer: {
          schema.ledgerEntries.categoryId: const CustomExpression<int>('''
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
  }

  Future<void> _migrateV2ToV3(Migrator migrator, Schema3 schema) async {
    await migrator.addColumn(schema.accounts, schema.accounts.isArchived);
    await migrator.alterTable(TableMigration(schema.ledgerEntries));
  }

  Future<void> _migrateV3ToV4(Migrator migrator, Schema4 schema) async {
    final sequenceState = await customSelect('''
      SELECT
        COALESCE((SELECT seq FROM sqlite_sequence
                  WHERE name = 'ledger_entries'), 0) AS sequence_value,
        COALESCE((SELECT MAX(id) FROM ledger_entries), 0) AS maximum_id
    ''').getSingle();
    final previousSequence = sequenceState.read<int>('sequence_value');
    final maximumLedgerId = sequenceState.read<int>('maximum_id');
    final sequenceToRestore = previousSequence > maximumLedgerId
        ? previousSequence
        : maximumLedgerId;

    await customStatement('DROP TABLE IF EXISTS temp.ledger_allocations_v4');
    await customStatement('''
      CREATE TEMP TABLE ledger_allocations_v4 AS
      SELECT id AS entry_id, 0 AS position, category_id, amount
      FROM ledger_entries
      WHERE kind IN (0, 1)
    ''');
    try {
      final invalid = await customSelect('''
        SELECT COUNT(*) AS amount
        FROM ledger_entries AS entry
        LEFT JOIN categories AS category ON category.id = entry.category_id
        WHERE (entry.kind IN (0, 1) AND
               (category.id IS NULL OR category.parent_id IS NULL OR
                category.kind <> entry.kind))
           OR (entry.kind IN (2, 3) AND entry.category_id IS NOT NULL)
      ''').getSingle();
      if (invalid.read<int>('amount') != 0) {
        throw StateError('Kategori transaksi schema v3 tidak valid.');
      }

      // Drift preserves custom table extras while rebuilding a table. Retire
      // the v3 objects before the category_id column disappears.
      await _dropLegacyLedgerCategoryExtras();
      await migrator.alterTable(TableMigration(schema.ledgerEntries));
      await migrator.createTable(schema.ledgerAllocations);
      await customStatement('''
        INSERT INTO ledger_allocations (entry_id, position, category_id, amount)
        SELECT entry_id, position, category_id, amount
        FROM temp.ledger_allocations_v4
        ORDER BY entry_id
      ''');

      await customStatement(
        "DELETE FROM sqlite_sequence WHERE name = 'ledger_entries'",
      );
      await customStatement(
        "INSERT INTO sqlite_sequence (name, seq) VALUES ('ledger_entries', ?)",
        [sequenceToRestore],
      );
    } finally {
      await customStatement('DROP TABLE IF EXISTS temp.ledger_allocations_v4');
    }
  }

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

  Future<void> _createCommonSchemaExtras() async {
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
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  Future<void> _createLegacyLedgerCategoryExtras() async {
    const statements = [
      '''CREATE INDEX IF NOT EXISTS ledger_entries_category_id
         ON ledger_entries (category_id)''',
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

  Future<void> _dropLegacyLedgerCategoryExtras() async {
    const statements = [
      'DROP INDEX IF EXISTS ledger_entries_category_id',
      'DROP TRIGGER IF EXISTS ledger_validate_category_insert',
      'DROP TRIGGER IF EXISTS ledger_validate_category_update',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  Future<void> _createSchemaV4Extras() async {
    const statements = [
      '''CREATE INDEX IF NOT EXISTS ledger_allocations_category_entry
         ON ledger_allocations (category_id, entry_id)''',
      '''CREATE TRIGGER IF NOT EXISTS ledger_allocations_validate_insert
         BEFORE INSERT ON ledger_allocations
         WHEN NOT EXISTS (
           SELECT 1
           FROM ledger_entries AS entry
           JOIN categories AS category ON category.id = NEW.category_id
           WHERE entry.id = NEW.entry_id
             AND entry.kind IN (0, 1)
             AND category.parent_id IS NOT NULL
             AND category.kind = entry.kind)
         BEGIN SELECT RAISE(ABORT, 'invalid ledger allocation'); END''',
      '''CREATE TRIGGER IF NOT EXISTS ledger_allocations_validate_update
         BEFORE UPDATE OF entry_id, category_id ON ledger_allocations
         WHEN NOT EXISTS (
           SELECT 1
           FROM ledger_entries AS entry
           JOIN categories AS category ON category.id = NEW.category_id
           WHERE entry.id = NEW.entry_id
             AND entry.kind IN (0, 1)
             AND category.parent_id IS NOT NULL
             AND category.kind = entry.kind)
         BEGIN SELECT RAISE(ABORT, 'invalid ledger allocation'); END''',
      '''CREATE TRIGGER IF NOT EXISTS ledger_validate_allocations_kind_update
         BEFORE UPDATE OF kind ON ledger_entries
         WHEN (NEW.kind IN (2, 3) AND EXISTS (
           SELECT 1 FROM ledger_allocations
           WHERE entry_id = OLD.id
         )) OR (NEW.kind IN (0, 1) AND EXISTS (
           SELECT 1
           FROM ledger_allocations AS allocation
           LEFT JOIN categories AS category
             ON category.id = allocation.category_id
           WHERE allocation.entry_id = OLD.id
             AND (category.id IS NULL OR category.parent_id IS NULL
               OR category.kind <> NEW.kind)
         ))
         BEGIN SELECT RAISE(ABORT, 'invalid ledger allocation kind'); END''',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  Future<void> _createSchemaV3Extras() async {
    const statements = [
      '''CREATE INDEX IF NOT EXISTS accounts_archive_order
         ON accounts (is_archived, normalized_name, id)''',
      '''CREATE TRIGGER IF NOT EXISTS ledger_require_active_accounts_insert
         BEFORE INSERT ON ledger_entries
         WHEN EXISTS (
           SELECT 1 FROM accounts
           WHERE id = NEW.account_id AND is_archived = 1
         ) OR (
           NEW.destination_account_id IS NOT NULL AND EXISTS (
             SELECT 1 FROM accounts
             WHERE id = NEW.destination_account_id AND is_archived = 1
           )
         )
         BEGIN SELECT RAISE(ABORT, 'archived account'); END''',
      '''CREATE TRIGGER IF NOT EXISTS ledger_require_active_accounts_update
         BEFORE UPDATE ON ledger_entries
         WHEN EXISTS (
           SELECT 1 FROM accounts
           WHERE id = OLD.account_id AND is_archived = 1
         ) OR (
           OLD.destination_account_id IS NOT NULL AND EXISTS (
             SELECT 1 FROM accounts
             WHERE id = OLD.destination_account_id AND is_archived = 1
           )
         ) OR EXISTS (
           SELECT 1 FROM accounts
           WHERE id = NEW.account_id AND is_archived = 1
         ) OR (
           NEW.destination_account_id IS NOT NULL AND EXISTS (
             SELECT 1 FROM accounts
             WHERE id = NEW.destination_account_id AND is_archived = 1
           )
         )
         BEGIN SELECT RAISE(ABORT, 'archived account'); END''',
      '''CREATE TRIGGER IF NOT EXISTS ledger_require_active_accounts_delete
         BEFORE DELETE ON ledger_entries
         WHEN EXISTS (
           SELECT 1 FROM accounts
           WHERE id = OLD.account_id AND is_archived = 1
         ) OR (
           OLD.destination_account_id IS NOT NULL AND EXISTS (
             SELECT 1 FROM accounts
             WHERE id = OLD.destination_account_id AND is_archived = 1
           )
         )
         BEGIN SELECT RAISE(ABORT, 'archived account'); END''',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  /// Verifies allocation invariants that SQLite cannot enforce per row.
  ///
  /// Call this inside the same transaction as ledger writes. Passing an
  /// [entryId] limits the verification to that transaction header.
  Future<void> verifyLedgerAllocationIntegrity({int? entryId}) async {
    if (entryId != null && entryId < 1) {
      throw ArgumentError.value(entryId, 'entryId', 'must be positive');
    }
    final entryFilter = entryId == null ? '' : 'AND entry.id = ?';
    final allocationFilter = entryId == null
        ? ''
        : 'AND allocation.entry_id = ?';

    final invalidHeaders = await customSelect(
      '''
        WITH allocation_stats AS (
          SELECT entry_id,
                 COUNT(*) AS allocation_count,
                 MIN(position) AS minimum_position,
                 MAX(position) AS maximum_position,
                 COUNT(DISTINCT category_id) AS category_count,
                 SUM(amount) AS allocated_amount
          FROM ledger_allocations
          GROUP BY entry_id
        )
        SELECT COUNT(*) AS amount
        FROM ledger_entries AS entry
        LEFT JOIN allocation_stats AS stats ON stats.entry_id = entry.id
        WHERE (
          (entry.kind IN (0, 1) AND (
            COALESCE(stats.allocation_count, 0) NOT BETWEEN 1 AND 50
            OR stats.minimum_position <> 0
            OR stats.maximum_position <> stats.allocation_count - 1
            OR stats.category_count <> stats.allocation_count
            OR stats.allocated_amount <> entry.amount
          ))
          OR (entry.kind IN (2, 3)
            AND COALESCE(stats.allocation_count, 0) <> 0)
        )
        $entryFilter
      ''',
      variables: entryId == null ? const [] : [Variable.withInt(entryId)],
      readsFrom: {ledgerEntries, ledgerAllocations},
    ).getSingle();
    if (invalidHeaders.read<int>('amount') != 0) {
      throw StateError('Integritas jumlah atau posisi alokasi tidak valid.');
    }

    final invalidReferences = await customSelect(
      '''
        SELECT COUNT(*) AS amount
        FROM ledger_allocations AS allocation
        LEFT JOIN ledger_entries AS entry ON entry.id = allocation.entry_id
        LEFT JOIN categories AS category ON category.id = allocation.category_id
        WHERE (entry.id IS NULL OR entry.kind NOT IN (0, 1)
          OR category.id IS NULL OR category.parent_id IS NULL
          OR category.kind <> entry.kind)
        $allocationFilter
      ''',
      variables: entryId == null ? const [] : [Variable.withInt(entryId)],
      readsFrom: {ledgerEntries, ledgerAllocations, categories},
    ).getSingle();
    if (invalidReferences.read<int>('amount') != 0) {
      throw StateError('Integritas relasi alokasi tidak valid.');
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
