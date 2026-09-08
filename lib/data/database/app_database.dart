import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.steps.dart';

part 'app_database.g.dart';

String _civilYearSql(String column) => 'CAST(($column) / 10000 AS INTEGER)';

String _civilMonthSql(String column) =>
    '(CAST(($column) / 100 AS INTEGER) % 100)';

String _civilDaySql(String column) => '(($column) % 100)';

String _daysInCivilMonthSql(String column) =>
    '''
  CASE ${_civilMonthSql(column)}
    WHEN 1 THEN 31
    WHEN 2 THEN CASE
      WHEN (${_civilYearSql(column)} % 400 = 0)
        OR (${_civilYearSql(column)} % 4 = 0
          AND ${_civilYearSql(column)} % 100 <> 0)
      THEN 29 ELSE 28 END
    WHEN 3 THEN 31
    WHEN 4 THEN 30
    WHEN 5 THEN 31
    WHEN 6 THEN 30
    WHEN 7 THEN 31
    WHEN 8 THEN 31
    WHEN 9 THEN 30
    WHEN 10 THEN 31
    WHEN 11 THEN 30
    WHEN 12 THEN 31
    ELSE 0
  END
''';

String _validCivilDaySql(String column) =>
    '''
  ($column) BETWEEN 20000101 AND 99991231
  AND ${_civilMonthSql(column)} BETWEEN 1 AND 12
  AND ${_civilDaySql(column)} BETWEEN 1
    AND (${_daysInCivilMonthSql(column)})
''';

String _canonicalBudgetPeriodSql({
  required String kind,
  required String startDay,
  required String endDay,
}) =>
    '''
  (($kind) = 0
    AND ${_civilDaySql(startDay)} = 1
    AND CAST(($startDay) / 100 AS INTEGER)
      = CAST(($endDay) / 100 AS INTEGER)
    AND ${_civilDaySql(endDay)} = (${_daysInCivilMonthSql(startDay)}))
  OR (($kind) = 1
    AND (($startDay) % 10000) = 101
    AND (($endDay) % 10000) = 1231
    AND ${_civilYearSql(startDay)} = ${_civilYearSql(endDay)})
  OR (($kind) = 2)
''';

@DataClassName('AccountRow')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get normalizedName => text().unique()();
  IntColumn get type => integer()();
  IntColumn get balanceGroup => integer()
      .withDefault(const Constant(0))
      .check(const CustomExpression<bool>('balance_group IN (0, 1)'))();
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

@DataClassName('BudgetRow')
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get periodKind => integer()();
  IntColumn get startDay => integer()();
  IntColumn get endDay => integer()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get normalizedName => text().withLength(min: 1, max: 80)();
  IntColumn get limitAmount => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK (period_kind BETWEEN 0 AND 2)',
    '''CHECK (
      start_day BETWEEN 20000101 AND 99991231
      AND (CAST(start_day / 100 AS INTEGER) % 100) BETWEEN 1 AND 12
      AND (start_day % 100) BETWEEN 1 AND CASE
        (CAST(start_day / 100 AS INTEGER) % 100)
        WHEN 1 THEN 31
        WHEN 2 THEN CASE
          WHEN (CAST(start_day / 10000 AS INTEGER) % 400 = 0)
            OR (CAST(start_day / 10000 AS INTEGER) % 4 = 0
              AND CAST(start_day / 10000 AS INTEGER) % 100 <> 0)
          THEN 29 ELSE 28 END
        WHEN 3 THEN 31
        WHEN 4 THEN 30
        WHEN 5 THEN 31
        WHEN 6 THEN 30
        WHEN 7 THEN 31
        WHEN 8 THEN 31
        WHEN 9 THEN 30
        WHEN 10 THEN 31
        WHEN 11 THEN 30
        WHEN 12 THEN 31
        ELSE 0
      END
    )''',
    '''CHECK (
      end_day BETWEEN 20000101 AND 99991231
      AND (CAST(end_day / 100 AS INTEGER) % 100) BETWEEN 1 AND 12
      AND (end_day % 100) BETWEEN 1 AND CASE
        (CAST(end_day / 100 AS INTEGER) % 100)
        WHEN 1 THEN 31
        WHEN 2 THEN CASE
          WHEN (CAST(end_day / 10000 AS INTEGER) % 400 = 0)
            OR (CAST(end_day / 10000 AS INTEGER) % 4 = 0
              AND CAST(end_day / 10000 AS INTEGER) % 100 <> 0)
          THEN 29 ELSE 28 END
        WHEN 3 THEN 31
        WHEN 4 THEN 30
        WHEN 5 THEN 31
        WHEN 6 THEN 30
        WHEN 7 THEN 31
        WHEN 8 THEN 31
        WHEN 9 THEN 30
        WHEN 10 THEN 31
        WHEN 11 THEN 30
        WHEN 12 THEN 31
        ELSE 0
      END
    )''',
    'CHECK (start_day <= end_day)',
    '''CHECK (
      (period_kind = 0
        AND (start_day % 100) = 1
        AND CAST(start_day / 100 AS INTEGER)
          = CAST(end_day / 100 AS INTEGER)
        AND (end_day % 100) = CASE
          (CAST(start_day / 100 AS INTEGER) % 100)
          WHEN 1 THEN 31
          WHEN 2 THEN CASE
            WHEN (CAST(start_day / 10000 AS INTEGER) % 400 = 0)
              OR (CAST(start_day / 10000 AS INTEGER) % 4 = 0
                AND CAST(start_day / 10000 AS INTEGER) % 100 <> 0)
            THEN 29 ELSE 28 END
          WHEN 3 THEN 31
          WHEN 4 THEN 30
          WHEN 5 THEN 31
          WHEN 6 THEN 30
          WHEN 7 THEN 31
          WHEN 8 THEN 31
          WHEN 9 THEN 30
          WHEN 10 THEN 31
          WHEN 11 THEN 30
          WHEN 12 THEN 31
          ELSE 0
        END)
      OR (period_kind = 1
        AND (start_day % 10000) = 101
        AND (end_day % 10000) = 1231
        AND CAST(start_day / 10000 AS INTEGER)
          = CAST(end_day / 10000 AS INTEGER))
      OR period_kind = 2
    )''',
    'CHECK (limit_amount BETWEEN 1 AND 999999999999)',
    'CHECK (length(trim(name)) BETWEEN 1 AND 80)',
    'CHECK (length(trim(normalized_name)) BETWEEN 1 AND 80)',
    'CHECK (updated_at >= created_at)',
  ];
}

@DataClassName('BudgetCategoryRow')
class BudgetCategories extends Table {
  @ReferenceName('categoryAssignments')
  IntColumn get budgetId =>
      integer().references(Budgets, #id, onDelete: KeyAction.cascade)();
  @ReferenceName('budgetAssignments')
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column<Object>> get primaryKey => {budgetId, categoryId};
}

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    LedgerEntries,
    LedgerAllocations,
    Budgets,
    BudgetCategories,
  ],
)
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
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _seedDefaultCategories();
      await _createCommonSchemaExtras();
      await _createSchemaV3Extras();
      await _createSchemaV4Extras();
      await _createSchemaV5Extras();
      await _createSchemaV6Extras();
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
            from4To5: _migrateV4ToV5,
            from5To6: _migrateV5ToV6,
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
          if (to >= 5) {
            await _createSchemaV5Extras();
          }
          if (to >= 6) {
            await _createSchemaV6Extras();
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
          if (to >= 6) {
            await verifyBudgetIntegrity();
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

  Future<void> _migrateV4ToV5(Migrator migrator, Schema5 schema) async {
    await migrator.addColumn(schema.accounts, schema.accounts.balanceGroup);
  }

  Future<void> _migrateV5ToV6(Migrator migrator, Schema6 schema) async {
    await migrator.createTable(schema.budgets);
    await migrator.createTable(schema.budgetCategories);
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

  Future<void> _createSchemaV5Extras() async {
    await customStatement(
      '''CREATE INDEX IF NOT EXISTS accounts_balance_group_order
         ON accounts
           (is_archived, balance_group, normalized_name, id)''',
    );
  }

  Future<void> _createSchemaV6Extras() async {
    const statements = [
      '''CREATE UNIQUE INDEX IF NOT EXISTS budgets_unique_period_name
         ON budgets (start_day, end_day, normalized_name)''',
      '''CREATE INDEX IF NOT EXISTS budgets_kind_period_order
         ON budgets
           (period_kind, start_day, end_day, normalized_name, id)''',
      '''CREATE INDEX IF NOT EXISTS budget_categories_category_budget
         ON budget_categories (category_id, budget_id)''',
      '''CREATE TRIGGER IF NOT EXISTS budget_categories_validate_insert
         BEFORE INSERT ON budget_categories
         WHEN NOT EXISTS (
           SELECT 1
           FROM categories AS category
           JOIN categories AS parent ON parent.id = category.parent_id
           WHERE category.id = NEW.category_id
             AND category.kind = 1
             AND category.parent_id IS NOT NULL
             AND parent.kind = 1
             AND parent.parent_id IS NULL)
         BEGIN SELECT RAISE(ABORT, 'invalid budget category'); END''',
      '''CREATE TRIGGER IF NOT EXISTS budget_categories_validate_update
         BEFORE UPDATE OF category_id ON budget_categories
         WHEN NOT EXISTS (
           SELECT 1
           FROM categories AS category
           JOIN categories AS parent ON parent.id = category.parent_id
           WHERE category.id = NEW.category_id
             AND category.kind = 1
             AND category.parent_id IS NOT NULL
             AND parent.kind = 1
             AND parent.parent_id IS NULL)
         BEGIN SELECT RAISE(ABORT, 'invalid budget category'); END''',
      '''CREATE TRIGGER IF NOT EXISTS budget_categories_overlap_insert
         BEFORE INSERT ON budget_categories
         WHEN EXISTS (
           SELECT 1
           FROM budgets AS candidate
           JOIN budget_categories AS existing_assignment
             ON existing_assignment.category_id = NEW.category_id
           JOIN budgets AS existing
             ON existing.id = existing_assignment.budget_id
           WHERE candidate.id = NEW.budget_id
             AND candidate.start_day <= existing.end_day
             AND existing.start_day <= candidate.end_day)
         BEGIN SELECT RAISE(ABORT, 'overlapping budget category'); END''',
      '''CREATE TRIGGER IF NOT EXISTS budget_categories_overlap_update
         BEFORE UPDATE OF budget_id, category_id ON budget_categories
         WHEN EXISTS (
           SELECT 1
           FROM budgets AS candidate
           JOIN budget_categories AS existing_assignment
             ON existing_assignment.category_id = NEW.category_id
           JOIN budgets AS existing
             ON existing.id = existing_assignment.budget_id
           WHERE candidate.id = NEW.budget_id
             AND NOT (
               existing_assignment.budget_id = OLD.budget_id
               AND existing_assignment.category_id = OLD.category_id)
             AND candidate.start_day <= existing.end_day
             AND existing.start_day <= candidate.end_day)
         BEGIN SELECT RAISE(ABORT, 'overlapping budget category'); END''',
      '''CREATE TRIGGER IF NOT EXISTS budgets_immutable_period
         BEFORE UPDATE OF period_kind, start_day, end_day ON budgets
         WHEN NEW.period_kind <> OLD.period_kind
           OR NEW.start_day <> OLD.start_day
           OR NEW.end_day <> OLD.end_day
         BEGIN SELECT RAISE(ABORT, 'immutable budget period'); END''',
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

  /// Verifies budget invariants that cannot be expressed by row constraints.
  ///
  /// Call this inside the same transaction as budget writes. Passing a
  /// [budgetId] limits row and mapping checks to that budget. Overlap checks
  /// still compare it with every other budget.
  Future<void> verifyBudgetIntegrity({int? budgetId}) async {
    if (budgetId != null && budgetId < 1) {
      throw ArgumentError.value(budgetId, 'budgetId', 'must be positive');
    }
    final definitionFilter = budgetId == null ? '' : 'AND budget.id = ?';
    final assignmentFilter = budgetId == null
        ? ''
        : 'AND assignment.budget_id = ?';
    final overlapFilter = budgetId == null
        ? ''
        : 'AND (left_budget.id = ? OR right_budget.id = ?)';

    final invalidDefinitions = await customSelect(
      '''
        SELECT COUNT(*) AS amount
        FROM budgets AS budget
        WHERE NOT (
          budget.period_kind BETWEEN 0 AND 2
          AND ${_validCivilDaySql('budget.start_day')}
          AND ${_validCivilDaySql('budget.end_day')}
          AND budget.start_day <= budget.end_day
          AND (${_canonicalBudgetPeriodSql(kind: 'budget.period_kind', startDay: 'budget.start_day', endDay: 'budget.end_day')})
          AND budget.limit_amount BETWEEN 1 AND 999999999999
          AND length(trim(budget.name)) BETWEEN 1 AND 80
          AND length(trim(budget.normalized_name)) BETWEEN 1 AND 80
          AND budget.updated_at >= budget.created_at
        )
        $definitionFilter
      ''',
      variables: budgetId == null ? const [] : [Variable.withInt(budgetId)],
      readsFrom: {budgets},
    ).getSingle();
    if (invalidDefinitions.read<int>('amount') != 0) {
      throw StateError('Definisi anggaran tidak valid.');
    }

    final missingAssignments = await customSelect(
      '''
        SELECT COUNT(*) AS amount
        FROM budgets AS budget
        WHERE NOT EXISTS (
          SELECT 1
          FROM budget_categories AS assignment
          WHERE assignment.budget_id = budget.id
        )
        $definitionFilter
      ''',
      variables: budgetId == null ? const [] : [Variable.withInt(budgetId)],
      readsFrom: {budgets, budgetCategories},
    ).getSingle();
    if (missingAssignments.read<int>('amount') != 0) {
      throw StateError('Anggaran wajib memiliki minimal satu kategori.');
    }

    final invalidAssignments = await customSelect(
      '''
        SELECT COUNT(*) AS amount
        FROM budget_categories AS assignment
        LEFT JOIN budgets AS budget ON budget.id = assignment.budget_id
        LEFT JOIN categories AS category ON category.id = assignment.category_id
        LEFT JOIN categories AS parent ON parent.id = category.parent_id
        WHERE (
          budget.id IS NULL
          OR category.id IS NULL
          OR category.kind <> 1
          OR category.parent_id IS NULL
          OR parent.id IS NULL
          OR parent.kind <> 1
          OR parent.parent_id IS NOT NULL
        )
        $assignmentFilter
      ''',
      variables: budgetId == null ? const [] : [Variable.withInt(budgetId)],
      readsFrom: {budgets, budgetCategories, categories},
    ).getSingle();
    if (invalidAssignments.read<int>('amount') != 0) {
      throw StateError('Integritas kategori anggaran tidak valid.');
    }

    final overlappingAssignments = await customSelect(
      '''
        SELECT COUNT(*) AS amount
        FROM budget_categories AS left_assignment
        JOIN budgets AS left_budget
          ON left_budget.id = left_assignment.budget_id
        JOIN budget_categories AS right_assignment
          ON right_assignment.category_id = left_assignment.category_id
         AND right_assignment.budget_id > left_assignment.budget_id
        JOIN budgets AS right_budget
          ON right_budget.id = right_assignment.budget_id
        WHERE left_budget.start_day <= right_budget.end_day
          AND right_budget.start_day <= left_budget.end_day
        $overlapFilter
      ''',
      variables: budgetId == null
          ? const []
          : [Variable.withInt(budgetId), Variable.withInt(budgetId)],
      readsFrom: {budgets, budgetCategories},
    ).getSingle();
    if (overlappingAssignments.read<int>('amount') != 0) {
      throw StateError('Kategori anggaran memiliki periode yang beririsan.');
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
