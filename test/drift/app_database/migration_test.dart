// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:waras_arta/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('migration from v1 to v2 does not corrupt data', () async {
    const createdAtBase = 1700000000000;
    const legacyCategories =
        <
          ({int kind, String parentName, int parentId, int childId, int amount})
        >[
          (
            kind: 0,
            parentName: 'Gaji',
            parentId: 1,
            childId: 2,
            amount: 100000,
          ),
          (
            kind: 0,
            parentName: 'Usaha',
            parentId: 3,
            childId: 4,
            amount: 20000,
          ),
          (
            kind: 0,
            parentName: 'Hadiah',
            parentId: 5,
            childId: 6,
            amount: 3000,
          ),
          (
            kind: 0,
            parentName: 'Lainnya',
            parentId: 7,
            childId: 8,
            amount: 400,
          ),
          (
            kind: 1,
            parentName: 'Makan & minum',
            parentId: 9,
            childId: 10,
            amount: 10000,
          ),
          (
            kind: 1,
            parentName: 'Transportasi',
            parentId: 11,
            childId: 12,
            amount: 2000,
          ),
          (
            kind: 1,
            parentName: 'Belanja',
            parentId: 13,
            childId: 14,
            amount: 3000,
          ),
          (
            kind: 1,
            parentName: 'Tagihan',
            parentId: 15,
            childId: 16,
            amount: 4000,
          ),
          (
            kind: 1,
            parentName: 'Kesehatan',
            parentId: 17,
            childId: 18,
            amount: 5000,
          ),
          (
            kind: 1,
            parentName: 'Hiburan',
            parentId: 19,
            childId: 20,
            amount: 6000,
          ),
          (
            kind: 1,
            parentName: 'Lainnya',
            parentId: 21,
            childId: 22,
            amount: 7000,
          ),
        ];

    final oldAccountsData = <v1.AccountsData>[
      const v1.AccountsData(
        id: 1,
        name: 'Dompet',
        normalizedName: 'dompet',
        type: 0,
        createdAt: createdAtBase - 2,
      ),
      const v1.AccountsData(
        id: 2,
        name: 'Bank',
        normalizedName: 'bank',
        type: 1,
        createdAt: createdAtBase - 1,
      ),
    ];
    final expectedNewAccountsData = <v2.AccountsData>[
      const v2.AccountsData(
        id: 1,
        name: 'Dompet',
        normalizedName: 'dompet',
        type: 0,
        createdAt: createdAtBase - 2,
      ),
      const v2.AccountsData(
        id: 2,
        name: 'Bank',
        normalizedName: 'bank',
        type: 1,
        createdAt: createdAtBase - 1,
      ),
    ];

    final oldLedgerEntriesData = <v1.LedgerEntriesData>[
      for (final (index, category) in legacyCategories.indexed)
        v1.LedgerEntriesData(
          id: index + 1,
          kind: category.kind,
          accountId: 1,
          amount: category.amount,
          category: category.parentName,
          note: 'legacy ${category.kind}:${category.parentName}',
          occurredDay: 20240101 + index,
          createdAt: createdAtBase + index + 1,
        ),
      const v1.LedgerEntriesData(
        id: 12,
        kind: 2,
        accountId: 1,
        destinationAccountId: 2,
        amount: 11000,
        note: 'transfer lampau',
        occurredDay: 20231215,
        createdAt: createdAtBase + 12,
      ),
      const v1.LedgerEntriesData(
        id: 13,
        kind: 3,
        accountId: 2,
        amount: 5000,
        note: 'saldo awal lampau',
        occurredDay: 20230101,
        createdAt: createdAtBase + 13,
      ),
    ];
    final expectedNewLedgerEntriesData = <v2.LedgerEntriesData>[
      for (final (index, category) in legacyCategories.indexed)
        v2.LedgerEntriesData(
          id: index + 1,
          kind: category.kind,
          accountId: 1,
          amount: category.amount,
          categoryId: category.childId,
          note: 'legacy ${category.kind}:${category.parentName}',
          occurredDay: 20240101 + index,
          createdAt: createdAtBase + index + 1,
        ),
      const v2.LedgerEntriesData(
        id: 12,
        kind: 2,
        accountId: 1,
        destinationAccountId: 2,
        amount: 11000,
        note: 'transfer lampau',
        occurredDay: 20231215,
        createdAt: createdAtBase + 12,
      ),
      const v2.LedgerEntriesData(
        id: 13,
        kind: 3,
        accountId: 2,
        amount: 5000,
        note: 'saldo awal lampau',
        occurredDay: 20230101,
        createdAt: createdAtBase + 13,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.accounts, oldAccountsData);
        batch.insertAll(oldDb.ledgerEntries, oldLedgerEntriesData);
      },
      validateItems: (newDb) async {
        final migratedAccounts = await newDb.select(newDb.accounts).get();
        migratedAccounts.sort((a, b) => a.id.compareTo(b.id));
        expect(migratedAccounts, expectedNewAccountsData);

        final migratedEntries = await newDb.select(newDb.ledgerEntries).get();
        migratedEntries.sort((a, b) => a.id.compareTo(b.id));
        expect(migratedEntries, expectedNewLedgerEntriesData);

        final categoryCount = await newDb
            .customSelect('SELECT COUNT(*) AS total FROM categories')
            .getSingle();
        expect(categoryCount.read<int>('total'), 22);

        final childRows = await newDb.customSelect('''
          SELECT child.id AS child_id, child.kind, child.name AS child_name,
                 child.parent_id, parent.name AS parent_name
          FROM categories AS child
          JOIN categories AS parent ON parent.id = child.parent_id
          ORDER BY child.id
        ''').get();
        final childMappings = childRows
            .map(
              (row) => (
                childId: row.read<int>('child_id'),
                kind: row.read<int>('kind'),
                childName: row.read<String>('child_name'),
                parentId: row.read<int>('parent_id'),
                parentName: row.read<String>('parent_name'),
              ),
            )
            .toList();
        expect(childMappings, [
          for (final category in legacyCategories)
            (
              childId: category.childId,
              kind: category.kind,
              childName: 'Umum',
              parentId: category.parentId,
              parentName: category.parentName,
            ),
        ]);

        final summary = await newDb.customSelect('''
          SELECT
            SUM(CASE WHEN kind = 0 THEN amount ELSE 0 END) AS income,
            SUM(CASE WHEN kind = 1 THEN amount ELSE 0 END) AS expense,
            SUM(CASE WHEN kind = 2 THEN amount ELSE 0 END) AS transfer,
            SUM(CASE WHEN kind = 3 THEN amount ELSE 0 END) AS adjustment
          FROM ledger_entries
        ''').getSingle();
        expect(summary.read<int>('income'), 123400);
        expect(summary.read<int>('expense'), 37000);
        expect(summary.read<int>('transfer'), 11000);
        expect(summary.read<int>('adjustment'), 5000);

        final balances = await newDb.customSelect('''
          WITH deltas(account_id, delta) AS (
            SELECT account_id,
              CASE kind WHEN 0 THEN amount WHEN 1 THEN -amount
                        WHEN 2 THEN -amount WHEN 3 THEN amount END
            FROM ledger_entries
            UNION ALL
            SELECT destination_account_id, amount
            FROM ledger_entries WHERE kind = 2
          )
          SELECT account_id, SUM(delta) AS balance
          FROM deltas GROUP BY account_id ORDER BY account_id
        ''').get();
        expect(
          balances
              .map(
                (row) => (
                  accountId: row.read<int>('account_id'),
                  balance: row.read<int>('balance'),
                ),
              )
              .toList(),
          [(accountId: 1, balance: 75400), (accountId: 2, balance: 16000)],
        );

        final customSchemaObjects = await newDb.customSelect('''
          SELECT name, type
          FROM sqlite_schema
          WHERE name IN (
            'categories_unique_root_name',
            'categories_unique_child_name',
            'categories_tree_order',
            'ledger_entries_occurred_day_id',
            'ledger_entries_account_id',
            'ledger_entries_destination_account_id',
            'ledger_entries_category_id',
            'categories_validate_parent_insert',
            'categories_immutable_structure',
            'ledger_validate_category_insert',
            'ledger_validate_category_update'
          )
        ''').get();
        expect(
          {
            for (final row in customSchemaObjects)
              row.read<String>('name'): row.read<String>('type'),
          },
          const {
            'categories_unique_root_name': 'index',
            'categories_unique_child_name': 'index',
            'categories_tree_order': 'index',
            'ledger_entries_occurred_day_id': 'index',
            'ledger_entries_account_id': 'index',
            'ledger_entries_destination_account_id': 'index',
            'ledger_entries_category_id': 'index',
            'categories_validate_parent_insert': 'trigger',
            'categories_immutable_structure': 'trigger',
            'ledger_validate_category_insert': 'trigger',
            'ledger_validate_category_update': 'trigger',
          },
        );

        await expectLater(
          newDb.customStatement(
            'UPDATE ledger_entries SET category_id = 1 WHERE id = 1',
          ),
          throwsA(anything),
        );
        final protectedEntry = await newDb
            .customSelect('SELECT category_id FROM ledger_entries WHERE id = 1')
            .getSingle();
        expect(protectedEntry.read<int>('category_id'), 2);

        await newDb.customStatement('PRAGMA foreign_keys = ON');
        expect(
          await newDb.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  });

  test(
    'migration from v2 to v3 preserves rows and enables account rules',
    () async {
      const accountsV2 = [
        v2.AccountsData(
          id: 1,
          name: 'Dompet',
          normalizedName: 'dompet',
          type: 0,
          createdAt: 1700000000000,
        ),
        v2.AccountsData(
          id: 2,
          name: 'Bank',
          normalizedName: 'bank',
          type: 1,
          createdAt: 1700000000001,
        ),
      ];
      const accountsV3 = [
        v3.AccountsData(
          id: 1,
          name: 'Dompet',
          normalizedName: 'dompet',
          type: 0,
          isArchived: 0,
          createdAt: 1700000000000,
        ),
        v3.AccountsData(
          id: 2,
          name: 'Bank',
          normalizedName: 'bank',
          type: 1,
          isArchived: 0,
          createdAt: 1700000000001,
        ),
      ];
      const categoriesV2 = [
        v2.CategoriesData(
          id: 1,
          kind: 0,
          name: 'Gaji',
          normalizedName: 'gaji',
          iconKey: 'work',
          isArchived: 0,
          sortOrder: 0,
          systemKey: 'income.salary',
          createdAt: 1700000000000,
          updatedAt: 1700000000000,
        ),
        v2.CategoriesData(
          id: 2,
          parentId: 1,
          kind: 0,
          name: 'Umum',
          normalizedName: 'umum',
          iconKey: 'work',
          isArchived: 0,
          sortOrder: 0,
          systemKey: 'income.salary.general',
          createdAt: 1700000000000,
          updatedAt: 1700000000000,
        ),
        v2.CategoriesData(
          id: 9,
          kind: 1,
          name: 'Makan & minum',
          normalizedName: 'makan & minum',
          iconKey: 'restaurant',
          isArchived: 0,
          sortOrder: 0,
          systemKey: 'expense.food_drink',
          createdAt: 1700000000000,
          updatedAt: 1700000000000,
        ),
        v2.CategoriesData(
          id: 10,
          parentId: 9,
          kind: 1,
          name: 'Umum',
          normalizedName: 'umum',
          iconKey: 'restaurant',
          isArchived: 0,
          sortOrder: 0,
          systemKey: 'expense.food_drink.general',
          createdAt: 1700000000000,
          updatedAt: 1700000000000,
        ),
      ];
      const entriesV2 = [
        v2.LedgerEntriesData(
          id: 1,
          kind: 0,
          accountId: 1,
          amount: 100,
          categoryId: 2,
          note: 'pemasukan',
          occurredDay: 20240101,
          createdAt: 1700000000010,
        ),
        v2.LedgerEntriesData(
          id: 2,
          kind: 1,
          accountId: 1,
          amount: 40,
          categoryId: 10,
          note: 'pengeluaran',
          occurredDay: 20240102,
          createdAt: 1700000000020,
        ),
        v2.LedgerEntriesData(
          id: 3,
          kind: 2,
          accountId: 1,
          destinationAccountId: 2,
          amount: 10,
          note: 'transfer',
          occurredDay: 20240103,
          createdAt: 1700000000030,
        ),
        v2.LedgerEntriesData(
          id: 4,
          kind: 3,
          accountId: 2,
          amount: 5,
          note: 'Saldo awal',
          occurredDay: 20240104,
          createdAt: 1700000000040,
        ),
      ];
      const entriesV3 = [
        v3.LedgerEntriesData(
          id: 1,
          kind: 0,
          accountId: 1,
          amount: 100,
          categoryId: 2,
          note: 'pemasukan',
          occurredDay: 20240101,
          createdAt: 1700000000010,
        ),
        v3.LedgerEntriesData(
          id: 2,
          kind: 1,
          accountId: 1,
          amount: 40,
          categoryId: 10,
          note: 'pengeluaran',
          occurredDay: 20240102,
          createdAt: 1700000000020,
        ),
        v3.LedgerEntriesData(
          id: 3,
          kind: 2,
          accountId: 1,
          destinationAccountId: 2,
          amount: 10,
          note: 'transfer',
          occurredDay: 20240103,
          createdAt: 1700000000030,
        ),
        v3.LedgerEntriesData(
          id: 4,
          kind: 3,
          accountId: 2,
          amount: 5,
          note: 'Saldo awal',
          occurredDay: 20240104,
          createdAt: 1700000000040,
        ),
      ];

      await verifier.testWithDataIntegrity(
        oldVersion: 2,
        newVersion: 3,
        createOld: v2.DatabaseAtV2.new,
        createNew: v3.DatabaseAtV3.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch.insertAll(oldDb.accounts, accountsV2);
          batch.insertAll(oldDb.categories, categoriesV2);
          batch.insertAll(oldDb.ledgerEntries, entriesV2);
        },
        validateItems: (newDb) async {
          final accounts = await newDb.select(newDb.accounts).get();
          accounts.sort((a, b) => a.id.compareTo(b.id));
          expect(accounts, accountsV3);
          final entries = await newDb.select(newDb.ledgerEntries).get();
          entries.sort((a, b) => a.id.compareTo(b.id));
          expect(entries, entriesV3);
          expect(await newDb.select(newDb.categories).get(), hasLength(4));

          final extras = await newDb.customSelect('''
          SELECT name, type FROM sqlite_schema
          WHERE name IN (
            'accounts_archive_order',
            'ledger_require_active_accounts_insert',
            'ledger_require_active_accounts_update',
            'ledger_require_active_accounts_delete'
          )
        ''').get();
          expect(
            {
              for (final row in extras)
                row.read<String>('name'): row.read<String>('type'),
            },
            const {
              'accounts_archive_order': 'index',
              'ledger_require_active_accounts_insert': 'trigger',
              'ledger_require_active_accounts_update': 'trigger',
              'ledger_require_active_accounts_delete': 'trigger',
            },
          );

          await newDb.customStatement('''
          INSERT INTO ledger_entries
            (kind, account_id, amount, category_id, note, occurred_day, created_at)
          VALUES (3, 1, -15, NULL, 'turun', 20240105, 1700000000050)
        ''');
          await expectLater(
            newDb.customStatement('''
            INSERT INTO ledger_entries
              (kind, account_id, amount, category_id, note, occurred_day, created_at)
            VALUES (0, 1, -1, 2, 'invalid', 20240105, 1700000000051)
          '''),
            throwsA(anything),
          );
          await newDb.customStatement(
            'UPDATE accounts SET is_archived = 1 WHERE id = 2',
          );
          await expectLater(
            newDb.customStatement('''
            INSERT INTO ledger_entries
              (kind, account_id, amount, category_id, note, occurred_day, created_at)
            VALUES (0, 2, 1, 2, 'arsip', 20240105, 1700000000052)
          '''),
            throwsA(anything),
          );
          expect(
            await newDb.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
        },
      );
    },
  );

  test('migration from v1 to v4 runs category, account, and allocation steps in order', () async {
    const accountsV1 = [
      v1.AccountsData(
        id: 1,
        name: 'Dompet',
        normalizedName: 'dompet',
        type: 0,
        createdAt: 1700000000000,
      ),
      v1.AccountsData(
        id: 2,
        name: 'Bank',
        normalizedName: 'bank',
        type: 1,
        createdAt: 1700000000001,
      ),
    ];
    const entriesV1 = [
      v1.LedgerEntriesData(
        id: 1,
        kind: 0,
        accountId: 1,
        amount: 100,
        category: 'Lainnya',
        note: 'lain pemasukan',
        occurredDay: 20240101,
        createdAt: 1700000000010,
      ),
      v1.LedgerEntriesData(
        id: 2,
        kind: 1,
        accountId: 1,
        amount: 40,
        category: 'Lainnya',
        note: 'lain pengeluaran',
        occurredDay: 20240102,
        createdAt: 1700000000020,
      ),
      v1.LedgerEntriesData(
        id: 3,
        kind: 2,
        accountId: 1,
        destinationAccountId: 2,
        amount: 10,
        note: 'transfer',
        occurredDay: 20240103,
        createdAt: 1700000000030,
      ),
      v1.LedgerEntriesData(
        id: 4,
        kind: 3,
        accountId: 2,
        amount: 5,
        note: 'Saldo awal',
        occurredDay: 20240104,
        createdAt: 1700000000040,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 4,
      createOld: v1.DatabaseAtV1.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.accounts, accountsV1);
        batch.insertAll(oldDb.ledgerEntries, entriesV1);
      },
      validateItems: (newDb) async {
        final accounts = await newDb.select(newDb.accounts).get();
        accounts.sort((a, b) => a.id.compareTo(b.id));
        expect(accounts, const [
          v4.AccountsData(
            id: 1,
            name: 'Dompet',
            normalizedName: 'dompet',
            type: 0,
            isArchived: 0,
            createdAt: 1700000000000,
          ),
          v4.AccountsData(
            id: 2,
            name: 'Bank',
            normalizedName: 'bank',
            type: 1,
            isArchived: 0,
            createdAt: 1700000000001,
          ),
        ]);
        final entries = await newDb.select(newDb.ledgerEntries).get();
        entries.sort((a, b) => a.id.compareTo(b.id));
        expect(entries.map((row) => row.kind), [0, 1, 2, 3]);
        expect(entries.map((row) => row.amount), [100, 40, 10, 5]);
        final allocations = await newDb.select(newDb.ledgerAllocations).get();
        allocations.sort((a, b) => a.entryId.compareTo(b.entryId));
        expect(allocations, const [
          v4.LedgerAllocationsData(
            entryId: 1,
            position: 0,
            categoryId: 8,
            amount: 100,
          ),
          v4.LedgerAllocationsData(
            entryId: 2,
            position: 0,
            categoryId: 22,
            amount: 40,
          ),
        ]);
        final categories = await newDb
            .customSelect('SELECT COUNT(*) AS amount FROM categories')
            .getSingle();
        expect(categories.read<int>('amount'), 22);
        expect(
          await newDb.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  });

  test('migration directly from v1 to v5 preserves ledger and defaults account groups', () async {
    const accountsV1 = [
      v1.AccountsData(
        id: 1,
        name: 'Dompet lama',
        normalizedName: 'dompet lama',
        type: 0,
        createdAt: 1700000000000,
      ),
      v1.AccountsData(
        id: 2,
        name: 'Bank lama',
        normalizedName: 'bank lama',
        type: 1,
        createdAt: 1700000000001,
      ),
    ];
    const entriesV1 = [
      v1.LedgerEntriesData(
        id: 1,
        kind: 0,
        accountId: 1,
        amount: 100,
        category: 'Lainnya',
        note: 'pemasukan lama',
        occurredDay: 20240101,
        createdAt: 1700000000010,
      ),
      v1.LedgerEntriesData(
        id: 2,
        kind: 2,
        accountId: 1,
        destinationAccountId: 2,
        amount: 40,
        note: 'transfer lama',
        occurredDay: 20240102,
        createdAt: 1700000000020,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 5,
      createOld: v1.DatabaseAtV1.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.accounts, accountsV1);
        batch.insertAll(oldDb.ledgerEntries, entriesV1);
      },
      validateItems: (newDb) async {
        final accounts = await newDb.select(newDb.accounts).get();
        accounts.sort((left, right) => left.id.compareTo(right.id));
        expect(accounts, const [
          v5.AccountsData(
            id: 1,
            name: 'Dompet lama',
            normalizedName: 'dompet lama',
            type: 0,
            balanceGroup: 0,
            isArchived: 0,
            createdAt: 1700000000000,
          ),
          v5.AccountsData(
            id: 2,
            name: 'Bank lama',
            normalizedName: 'bank lama',
            type: 1,
            balanceGroup: 0,
            isArchived: 0,
            createdAt: 1700000000001,
          ),
        ]);

        final entries = await newDb.select(newDb.ledgerEntries).get();
        entries.sort((left, right) => left.id.compareTo(right.id));
        expect(entries, const [
          v5.LedgerEntriesData(
            id: 1,
            kind: 0,
            accountId: 1,
            amount: 100,
            note: 'pemasukan lama',
            occurredDay: 20240101,
            createdAt: 1700000000010,
          ),
          v5.LedgerEntriesData(
            id: 2,
            kind: 2,
            accountId: 1,
            destinationAccountId: 2,
            amount: 40,
            note: 'transfer lama',
            occurredDay: 20240102,
            createdAt: 1700000000020,
          ),
        ]);
        expect(await newDb.select(newDb.ledgerAllocations).get(), const [
          v5.LedgerAllocationsData(
            entryId: 1,
            position: 0,
            categoryId: 8,
            amount: 100,
          ),
        ]);

        final index = await newDb.customSelect('''
              SELECT type FROM sqlite_schema
              WHERE name = 'accounts_balance_group_order'
            ''').getSingle();
        expect(index.read<String>('type'), 'index');
        expect(
          await newDb.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  });

  test('migration from v3 to v4 preserves headers, creates allocations, and keeps the id high-water mark', () async {
    const accountsV3 = [
      v3.AccountsData(
        id: 1,
        name: 'Dompet',
        normalizedName: 'dompet',
        type: 0,
        isArchived: 0,
        createdAt: 1700000000000,
      ),
      v3.AccountsData(
        id: 2,
        name: 'Bank',
        normalizedName: 'bank',
        type: 1,
        isArchived: 0,
        createdAt: 1700000000001,
      ),
    ];
    const categoriesV3 = [
      v3.CategoriesData(
        id: 1,
        kind: 0,
        name: 'Gaji',
        normalizedName: 'gaji',
        iconKey: 'work',
        isArchived: 0,
        sortOrder: 0,
        systemKey: 'income.salary',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      ),
      v3.CategoriesData(
        id: 2,
        parentId: 1,
        kind: 0,
        name: 'Umum',
        normalizedName: 'umum',
        iconKey: 'work',
        isArchived: 0,
        sortOrder: 0,
        systemKey: 'income.salary.general',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      ),
      v3.CategoriesData(
        id: 9,
        kind: 1,
        name: 'Makan & minum',
        normalizedName: 'makan & minum',
        iconKey: 'restaurant',
        isArchived: 0,
        sortOrder: 0,
        systemKey: 'expense.food_drink',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      ),
      v3.CategoriesData(
        id: 10,
        parentId: 9,
        kind: 1,
        name: 'Umum',
        normalizedName: 'umum',
        iconKey: 'restaurant',
        isArchived: 1,
        sortOrder: 0,
        systemKey: 'expense.food_drink.general',
        createdAt: 1700000000000,
        updatedAt: 1700000000002,
      ),
    ];
    const entriesV3 = [
      v3.LedgerEntriesData(
        id: 5,
        kind: 0,
        accountId: 1,
        amount: 100,
        categoryId: 2,
        note: 'pemasukan lama',
        occurredDay: 20240101,
        createdAt: 1700000000010,
      ),
      v3.LedgerEntriesData(
        id: 9,
        kind: 1,
        accountId: 1,
        amount: 40,
        categoryId: 10,
        note: 'pengeluaran berkategori arsip',
        occurredDay: 20240102,
        createdAt: 1700000000020,
      ),
      v3.LedgerEntriesData(
        id: 12,
        kind: 2,
        accountId: 1,
        destinationAccountId: 2,
        amount: 10,
        note: 'transfer lama',
        occurredDay: 20240103,
        createdAt: 1700000000030,
      ),
      v3.LedgerEntriesData(
        id: 14,
        kind: 3,
        accountId: 2,
        amount: -5,
        note: 'koreksi turun',
        occurredDay: 20240104,
        createdAt: 1700000000040,
      ),
    ];
    const expectedEntriesV4 = [
      v4.LedgerEntriesData(
        id: 5,
        kind: 0,
        accountId: 1,
        amount: 100,
        note: 'pemasukan lama',
        occurredDay: 20240101,
        createdAt: 1700000000010,
      ),
      v4.LedgerEntriesData(
        id: 9,
        kind: 1,
        accountId: 1,
        amount: 40,
        note: 'pengeluaran berkategori arsip',
        occurredDay: 20240102,
        createdAt: 1700000000020,
      ),
      v4.LedgerEntriesData(
        id: 12,
        kind: 2,
        accountId: 1,
        destinationAccountId: 2,
        amount: 10,
        note: 'transfer lama',
        occurredDay: 20240103,
        createdAt: 1700000000030,
      ),
      v4.LedgerEntriesData(
        id: 14,
        kind: 3,
        accountId: 2,
        amount: -5,
        note: 'koreksi turun',
        occurredDay: 20240104,
        createdAt: 1700000000040,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.accounts, accountsV3);
        batch.insertAll(oldDb.categories, categoriesV3);
        batch.insertAll(oldDb.ledgerEntries, entriesV3);
        batch.customStatement(
          "UPDATE sqlite_sequence SET seq = 70 WHERE name = 'ledger_entries'",
        );
        // Generated schema fixtures omit custom extras that exist in real v3
        // installations. Keep these here to exercise the production upgrade.
        batch.customStatement('''
          CREATE INDEX ledger_entries_category_id
          ON ledger_entries (category_id)
        ''');
        batch.customStatement('''
          CREATE TRIGGER ledger_validate_category_insert
          BEFORE INSERT ON ledger_entries
          WHEN NEW.kind IN (0, 1) AND NOT EXISTS (
            SELECT 1 FROM categories AS category
            WHERE category.id = NEW.category_id
              AND category.kind = NEW.kind
              AND category.parent_id IS NOT NULL)
          BEGIN SELECT RAISE(ABORT, 'invalid ledger category'); END
        ''');
        batch.customStatement('''
          CREATE TRIGGER ledger_validate_category_update
          BEFORE UPDATE OF kind, category_id ON ledger_entries
          WHEN NEW.kind IN (0, 1) AND NOT EXISTS (
            SELECT 1 FROM categories AS category
            WHERE category.id = NEW.category_id
              AND category.kind = NEW.kind
              AND category.parent_id IS NOT NULL)
          BEGIN SELECT RAISE(ABORT, 'invalid ledger category'); END
        ''');
      },
      validateItems: (newDb) async {
        final entries = await newDb.select(newDb.ledgerEntries).get();
        entries.sort((a, b) => a.id.compareTo(b.id));
        expect(entries, expectedEntriesV4);

        final allocations = await newDb.select(newDb.ledgerAllocations).get();
        allocations.sort((a, b) => a.entryId.compareTo(b.entryId));
        expect(allocations, const [
          v4.LedgerAllocationsData(
            entryId: 5,
            position: 0,
            categoryId: 2,
            amount: 100,
          ),
          v4.LedgerAllocationsData(
            entryId: 9,
            position: 0,
            categoryId: 10,
            amount: 40,
          ),
        ]);

        final sequence = await newDb.customSelect('''
            SELECT seq FROM sqlite_sequence WHERE name = 'ledger_entries'
          ''').getSingle();
        expect(sequence.read<int>('seq'), 70);

        final schemaObjects = await newDb.customSelect('''
            SELECT name, type FROM sqlite_schema
            WHERE name IN (
              'ledger_allocations_category_entry',
              'ledger_allocations_validate_insert',
              'ledger_allocations_validate_update',
              'ledger_validate_allocations_kind_update',
              'accounts_archive_order',
              'ledger_require_active_accounts_insert',
              'ledger_require_active_accounts_update',
              'ledger_require_active_accounts_delete'
            )
          ''').get();
        expect(
          {
            for (final row in schemaObjects)
              row.read<String>('name'): row.read<String>('type'),
          },
          const {
            'ledger_allocations_category_entry': 'index',
            'ledger_allocations_validate_insert': 'trigger',
            'ledger_allocations_validate_update': 'trigger',
            'ledger_validate_allocations_kind_update': 'trigger',
            'accounts_archive_order': 'index',
            'ledger_require_active_accounts_insert': 'trigger',
            'ledger_require_active_accounts_update': 'trigger',
            'ledger_require_active_accounts_delete': 'trigger',
          },
        );
        final retiredObjects = await newDb.customSelect('''
            SELECT COUNT(*) AS amount FROM sqlite_schema
            WHERE name IN (
              'ledger_entries_category_id',
              'ledger_validate_category_insert',
              'ledger_validate_category_update'
            )
          ''').getSingle();
        expect(retiredObjects.read<int>('amount'), 0);

        await newDb.customStatement('''
            INSERT INTO ledger_entries
              (kind, account_id, amount, note, occurred_day, created_at)
            VALUES (3, 1, -1, 'setelah migrasi', 20240105, 1700000000050)
          ''');
        final inserted = await newDb.customSelect('''
            SELECT id FROM ledger_entries WHERE note = 'setelah migrasi'
          ''').getSingle();
        expect(inserted.read<int>('id'), 71);

        await expectLater(
          newDb.customStatement('''
              INSERT INTO ledger_allocations
                (entry_id, position, category_id, amount)
              VALUES (12, 0, 2, 10)
            '''),
          throwsA(anything),
        );
        await expectLater(
          newDb.customStatement('''
              UPDATE ledger_allocations SET category_id = 10
              WHERE entry_id = 5 AND position = 0
            '''),
          throwsA(anything),
        );
        await expectLater(
          newDb.customStatement(
            'UPDATE ledger_entries SET kind = 1 WHERE id = 5',
          ),
          throwsA(anything),
        );
        expect(
          await newDb.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  });

  test(
    'fresh v6 enforces row rules and exposes cross-row verification',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 6);
        await db.customStatement('''
        INSERT INTO accounts
          (id, name, normalized_name, type, is_archived, created_at)
        VALUES
          (1, 'Dompet', 'dompet', 0, 0, 1700000000000),
          (2, 'Bank', 'bank', 1, 0, 1700000000001)
      ''');
        await db.customStatement('''
        INSERT INTO ledger_entries
          (id, kind, account_id, amount, note, occurred_day, created_at)
        VALUES (1, 0, 1, 100, 'belum dialokasikan', 20240101, 1700000000010)
      ''');
        await expectLater(
          db.verifyLedgerAllocationIntegrity(entryId: 1),
          throwsA(isA<StateError>()),
        );
        await db.customStatement('''
        INSERT INTO ledger_allocations
          (entry_id, position, category_id, amount)
        VALUES (1, 0, 2, 100)
      ''');
        await db.verifyLedgerAllocationIntegrity(entryId: 1);

        await db.customStatement('''
        INSERT INTO ledger_entries
          (id, kind, account_id, amount, note, occurred_day, created_at)
        VALUES (2, 0, 1, 100, 'posisi bercelah', 20240102, 1700000000020)
      ''');
        await db.customStatement('''
        INSERT INTO ledger_allocations
          (entry_id, position, category_id, amount)
        VALUES (2, 1, 2, 100)
      ''');
        await expectLater(
          db.verifyLedgerAllocationIntegrity(entryId: 2),
          throwsA(isA<StateError>()),
        );

        await db.customStatement('''
        INSERT INTO ledger_entries
          (id, kind, account_id, amount, note, occurred_day, created_at)
        VALUES (3, 0, 1, 100, 'kategori invalid', 20240103, 1700000000030)
      ''');
        await expectLater(
          db.customStatement('''
          INSERT INTO ledger_allocations
            (entry_id, position, category_id, amount)
          VALUES (3, 0, 1, 100)
        '''),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement('''
          INSERT INTO ledger_allocations
            (entry_id, position, category_id, amount)
          VALUES (3, 0, 10, 100)
        '''),
          throwsA(anything),
        );

        await db.customStatement('''
        INSERT INTO ledger_entries
          (id, kind, account_id, destination_account_id, amount, note,
           occurred_day, created_at)
        VALUES (4, 2, 1, 2, 10, 'transfer', 20240104, 1700000000040)
      ''');
        await expectLater(
          db.customStatement('''
          INSERT INTO ledger_allocations
            (entry_id, position, category_id, amount)
          VALUES (4, 0, 2, 10)
        '''),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement('''
          UPDATE ledger_allocations SET category_id = 10
          WHERE entry_id = 1 AND position = 0
        '''),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement('UPDATE ledger_entries SET kind = 1 WHERE id = 1'),
          throwsA(anything),
        );

        await db.customStatement('''
        INSERT INTO ledger_entries
          (id, kind, account_id, amount, note, occurred_day, created_at)
        VALUES (5, 0, 1, 200, 'kategori ganda', 20240105, 1700000000050)
      ''');
        await db.customStatement('''
        INSERT INTO ledger_allocations
          (entry_id, position, category_id, amount)
        VALUES (5, 0, 2, 100)
      ''');
        await expectLater(
          db.customStatement('''
          INSERT INTO ledger_allocations
            (entry_id, position, category_id, amount)
          VALUES (5, 1, 2, 100)
        '''),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement('DELETE FROM categories WHERE id = 2'),
          throwsA(anything),
        );

        await db.customStatement(
          'DELETE FROM ledger_entries WHERE id IN (1, 2, 3, 5)',
        );
        final cascaded = await db.customSelect('''
        SELECT COUNT(*) AS amount FROM ledger_allocations
        WHERE entry_id IN (1, 2, 3, 5)
      ''').getSingle();
        expect(cascaded.read<int>('amount'), 0);
        await db.verifyLedgerAllocationIntegrity();
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    },
  );

  test('fresh v6 enforces budget periods, mappings, and relations', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 6);

      Future<void> insertBudget({
        required int id,
        required int periodKind,
        required int startDay,
        required int endDay,
        required String name,
        int limitAmount = 100000,
        int createdAt = 1700000000000,
        int updatedAt = 1700000000000,
      }) => db.customStatement(
        '''
          INSERT INTO budgets (
            id, period_kind, start_day, end_day, name, normalized_name,
            limit_amount, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          id,
          periodKind,
          startDay,
          endDay,
          name,
          name.toLowerCase(),
          limitAmount,
          createdAt,
          updatedAt,
        ],
      );

      await insertBudget(
        id: 1,
        periodKind: 0,
        startDay: 20260101,
        endDay: 20260131,
        name: 'Makan Januari',
      );
      await insertBudget(
        id: 2,
        periodKind: 0,
        startDay: 20260201,
        endDay: 20260228,
        name: 'Makan Februari',
      );
      await insertBudget(
        id: 3,
        periodKind: 2,
        startDay: 20260131,
        endDay: 20260202,
        name: 'Akhir pekan',
      );
      await insertBudget(
        id: 4,
        periodKind: 1,
        startDay: 20260101,
        endDay: 20261231,
        name: 'Kesehatan tahunan',
      );
      await insertBudget(
        id: 5,
        periodKind: 2,
        startDay: 20000229,
        endDay: 20000229,
        name: 'Hari kabisat',
      );
      await insertBudget(
        id: 6,
        periodKind: 2,
        startDay: 99991231,
        endDay: 99991231,
        name: 'Batas tanggal',
      );

      await expectLater(
        insertBudget(
          id: 20,
          periodKind: 2,
          startDay: 20250229,
          endDay: 20250229,
          name: 'Tanggal semu',
        ),
        throwsA(anything),
      );
      await expectLater(
        insertBudget(
          id: 21,
          periodKind: 2,
          startDay: 21000229,
          endDay: 21000229,
          name: 'Bukan kabisat',
        ),
        throwsA(anything),
      );
      await expectLater(
        insertBudget(
          id: 22,
          periodKind: 2,
          startDay: 20260431,
          endDay: 20260431,
          name: 'Hari April semu',
        ),
        throwsA(anything),
      );
      await expectLater(
        insertBudget(
          id: 23,
          periodKind: 3,
          startDay: 20260301,
          endDay: 20260301,
          name: 'Jenis asing',
        ),
        throwsA(anything),
      );
      await expectLater(
        insertBudget(
          id: 24,
          periodKind: 0,
          startDay: 20260102,
          endDay: 20260131,
          name: 'Bulan tidak canonical',
        ),
        throwsA(anything),
      );
      await expectLater(
        insertBudget(
          id: 25,
          periodKind: 1,
          startDay: 20260102,
          endDay: 20261231,
          name: 'Tahun tidak canonical',
        ),
        throwsA(anything),
      );
      await expectLater(
        insertBudget(
          id: 26,
          periodKind: 2,
          startDay: 20260302,
          endDay: 20260301,
          name: 'Rentang terbalik',
        ),
        throwsA(anything),
      );
      await expectLater(
        insertBudget(
          id: 27,
          periodKind: 2,
          startDay: 20260301,
          endDay: 20260301,
          name: 'Batas nol',
          limitAmount: 0,
        ),
        throwsA(anything),
      );
      await expectLater(
        insertBudget(
          id: 28,
          periodKind: 2,
          startDay: 20260101,
          endDay: 20260131,
          name: 'MAKAN JANUARI',
        ),
        throwsA(anything),
      );
      await expectLater(
        insertBudget(
          id: 29,
          periodKind: 2,
          startDay: 20260301,
          endDay: 20260301,
          name: 'Jam mundur',
          createdAt: 1700000000001,
          updatedAt: 1700000000000,
        ),
        throwsA(anything),
      );

      await db.customStatement('''
        INSERT INTO budget_categories (budget_id, category_id)
        VALUES (1, 10), (2, 10), (3, 12), (4, 14), (5, 16), (6, 18)
      ''');
      await db.customStatement('''
        UPDATE budget_categories
        SET budget_id = budget_id, category_id = category_id
        WHERE budget_id = 1 AND category_id = 10
      ''');

      await expectLater(
        db.customStatement('''
          INSERT INTO budget_categories (budget_id, category_id)
          VALUES (3, 10)
        '''),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('''
          UPDATE budget_categories SET category_id = 10
          WHERE budget_id = 3 AND category_id = 12
        '''),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('''
          UPDATE budget_categories SET budget_id = 3
          WHERE budget_id = 2 AND category_id = 10
        '''),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('''
          UPDATE budget_categories SET category_id = 9
          WHERE budget_id = 3 AND category_id = 12
        '''),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('''
          INSERT INTO budget_categories (budget_id, category_id)
          VALUES (3, 9)
        '''),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('''
          INSERT INTO budget_categories (budget_id, category_id)
          VALUES (3, 2)
        '''),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'UPDATE budgets SET end_day = 20260203 WHERE id = 3',
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('DELETE FROM categories WHERE id = 10'),
        throwsA(anything),
      );

      await db.verifyBudgetIntegrity();
      await insertBudget(
        id: 7,
        periodKind: 2,
        startDay: 20260301,
        endDay: 20260301,
        name: 'Tanpa kategori',
      );
      await expectLater(
        db.verifyBudgetIntegrity(budgetId: 7),
        throwsA(isA<StateError>()),
      );
      await db.customStatement('DELETE FROM budgets WHERE id = 7');

      await db.customStatement('DELETE FROM budgets WHERE id = 1');
      final cascade = await db.customSelect('''
        SELECT COUNT(*) AS amount
        FROM budget_categories
        WHERE budget_id = 1
      ''').getSingle();
      expect(cascade.read<int>('amount'), 0);
      final preservedCategory = await db.customSelect('''
        SELECT COUNT(*) AS amount FROM categories WHERE id = 10
      ''').getSingle();
      expect(preservedCategory.read<int>('amount'), 1);
      await db.verifyBudgetIntegrity();
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    } finally {
      await db.close();
    }
  });

  test('migration from v4 to v5 preserves account ledger data and defaults balance groups', () async {
    const accountsV4 = [
      v4.AccountsData(
        id: 1,
        name: 'Bank aktif',
        normalizedName: 'bank aktif',
        type: 1,
        isArchived: 0,
        createdAt: 1700000000000,
      ),
      v4.AccountsData(
        id: 2,
        name: 'Dompet arsip',
        normalizedName: 'dompet arsip',
        type: 0,
        isArchived: 1,
        createdAt: 1700000000001,
      ),
    ];
    const categoriesV4 = [
      v4.CategoriesData(
        id: 1,
        kind: 0,
        name: 'Gaji',
        normalizedName: 'gaji',
        iconKey: 'work',
        isArchived: 0,
        sortOrder: 0,
        systemKey: 'income.salary',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      ),
      v4.CategoriesData(
        id: 2,
        parentId: 1,
        kind: 0,
        name: 'Umum',
        normalizedName: 'umum',
        iconKey: 'work',
        isArchived: 0,
        sortOrder: 0,
        systemKey: 'income.salary.general',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      ),
    ];
    const entriesV4 = [
      v4.LedgerEntriesData(
        id: 5,
        kind: 0,
        accountId: 1,
        amount: 100,
        note: 'pemasukan lama',
        occurredDay: 20240101,
        createdAt: 1700000000010,
      ),
      v4.LedgerEntriesData(
        id: 6,
        kind: 2,
        accountId: 1,
        destinationAccountId: 2,
        amount: 40,
        note: 'transfer ke arsip',
        occurredDay: 20240102,
        createdAt: 1700000000020,
      ),
      v4.LedgerEntriesData(
        id: 7,
        kind: 2,
        accountId: 2,
        destinationAccountId: 1,
        amount: 40,
        note: 'transfer dari arsip',
        occurredDay: 20240103,
        createdAt: 1700000000030,
      ),
    ];
    const allocationsV4 = [
      v4.LedgerAllocationsData(
        entryId: 5,
        position: 0,
        categoryId: 2,
        amount: 100,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 4,
      newVersion: 5,
      createOld: v4.DatabaseAtV4.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.accounts, accountsV4);
        batch.insertAll(oldDb.categories, categoriesV4);
        batch.insertAll(oldDb.ledgerEntries, entriesV4);
        batch.insertAll(oldDb.ledgerAllocations, allocationsV4);
      },
      validateItems: (newDb) async {
        final accounts = await newDb.select(newDb.accounts).get();
        accounts.sort((left, right) => left.id.compareTo(right.id));
        expect(accounts, const [
          v5.AccountsData(
            id: 1,
            name: 'Bank aktif',
            normalizedName: 'bank aktif',
            type: 1,
            balanceGroup: 0,
            isArchived: 0,
            createdAt: 1700000000000,
          ),
          v5.AccountsData(
            id: 2,
            name: 'Dompet arsip',
            normalizedName: 'dompet arsip',
            type: 0,
            balanceGroup: 0,
            isArchived: 1,
            createdAt: 1700000000001,
          ),
        ]);

        final entries = await newDb.select(newDb.ledgerEntries).get();
        entries.sort((left, right) => left.id.compareTo(right.id));
        expect(entries, const [
          v5.LedgerEntriesData(
            id: 5,
            kind: 0,
            accountId: 1,
            amount: 100,
            note: 'pemasukan lama',
            occurredDay: 20240101,
            createdAt: 1700000000010,
          ),
          v5.LedgerEntriesData(
            id: 6,
            kind: 2,
            accountId: 1,
            destinationAccountId: 2,
            amount: 40,
            note: 'transfer ke arsip',
            occurredDay: 20240102,
            createdAt: 1700000000020,
          ),
          v5.LedgerEntriesData(
            id: 7,
            kind: 2,
            accountId: 2,
            destinationAccountId: 1,
            amount: 40,
            note: 'transfer dari arsip',
            occurredDay: 20240103,
            createdAt: 1700000000030,
          ),
        ]);

        expect(await newDb.select(newDb.ledgerAllocations).get(), const [
          v5.LedgerAllocationsData(
            entryId: 5,
            position: 0,
            categoryId: 2,
            amount: 100,
          ),
        ]);

        final index = await newDb.customSelect('''
            SELECT type FROM sqlite_schema
            WHERE name = 'accounts_balance_group_order'
          ''').getSingle();
        expect(index.read<String>('type'), 'index');

        await expectLater(
          newDb.customStatement(
            'UPDATE accounts SET balance_group = 2 WHERE id = 1',
          ),
          throwsA(anything),
        );
        final unchanged = await newDb.customSelect('''
            SELECT balance_group FROM accounts WHERE id = 1
          ''').getSingle();
        expect(unchanged.read<int>('balance_group'), 0);
        expect(
          await newDb.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  });

  test('migration from v5 to v6 preserves existing finance data', () async {
    const accountsV5 = [
      v5.AccountsData(
        id: 1,
        name: 'Dana darurat',
        normalizedName: 'dana darurat',
        type: 1,
        balanceGroup: 1,
        isArchived: 0,
        createdAt: 1700000000000,
      ),
    ];
    const categoriesV5 = [
      v5.CategoriesData(
        id: 9,
        kind: 1,
        name: 'Makan & minum',
        normalizedName: 'makan & minum',
        iconKey: 'restaurant',
        isArchived: 0,
        sortOrder: 0,
        systemKey: 'expense.food_drink',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      ),
      v5.CategoriesData(
        id: 10,
        parentId: 9,
        kind: 1,
        name: 'Umum',
        normalizedName: 'umum',
        iconKey: 'restaurant',
        isArchived: 1,
        sortOrder: 0,
        systemKey: 'expense.food_drink.general',
        createdAt: 1700000000001,
        updatedAt: 1700000000001,
      ),
    ];
    const entriesV5 = [
      v5.LedgerEntriesData(
        id: 7,
        kind: 1,
        accountId: 1,
        amount: 17500,
        note: 'makan lama',
        occurredDay: 20260908,
        createdAt: 1700000000010,
      ),
    ];
    const allocationsV5 = [
      v5.LedgerAllocationsData(
        entryId: 7,
        position: 0,
        categoryId: 10,
        amount: 17500,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 5,
      newVersion: 6,
      createOld: v5.DatabaseAtV5.new,
      createNew: v6.DatabaseAtV6.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.accounts, accountsV5);
        batch.insertAll(oldDb.categories, categoriesV5);
        batch.insertAll(oldDb.ledgerEntries, entriesV5);
        batch.insertAll(oldDb.ledgerAllocations, allocationsV5);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.accounts).get(), const [
          v6.AccountsData(
            id: 1,
            name: 'Dana darurat',
            normalizedName: 'dana darurat',
            type: 1,
            balanceGroup: 1,
            isArchived: 0,
            createdAt: 1700000000000,
          ),
        ]);
        expect(await newDb.select(newDb.categories).get(), const [
          v6.CategoriesData(
            id: 9,
            kind: 1,
            name: 'Makan & minum',
            normalizedName: 'makan & minum',
            iconKey: 'restaurant',
            isArchived: 0,
            sortOrder: 0,
            systemKey: 'expense.food_drink',
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
          v6.CategoriesData(
            id: 10,
            parentId: 9,
            kind: 1,
            name: 'Umum',
            normalizedName: 'umum',
            iconKey: 'restaurant',
            isArchived: 1,
            sortOrder: 0,
            systemKey: 'expense.food_drink.general',
            createdAt: 1700000000001,
            updatedAt: 1700000000001,
          ),
        ]);
        expect(await newDb.select(newDb.ledgerEntries).get(), const [
          v6.LedgerEntriesData(
            id: 7,
            kind: 1,
            accountId: 1,
            amount: 17500,
            note: 'makan lama',
            occurredDay: 20260908,
            createdAt: 1700000000010,
          ),
        ]);
        expect(await newDb.select(newDb.ledgerAllocations).get(), const [
          v6.LedgerAllocationsData(
            entryId: 7,
            position: 0,
            categoryId: 10,
            amount: 17500,
          ),
        ]);
        expect(await newDb.select(newDb.budgets).get(), isEmpty);
        expect(await newDb.select(newDb.budgetCategories).get(), isEmpty);

        final extras = await newDb.customSelect('''
          SELECT name
          FROM sqlite_schema
          WHERE name IN (
            'budgets_unique_period_name',
            'budgets_kind_period_order',
            'budget_categories_category_budget',
            'budget_categories_validate_insert',
            'budget_categories_validate_update',
            'budget_categories_overlap_insert',
            'budget_categories_overlap_update',
            'budgets_immutable_period'
          )
          ORDER BY name
        ''').get();
        expect(extras.map((row) => row.read<String>('name')).toSet(), {
          'budgets_unique_period_name',
          'budgets_kind_period_order',
          'budget_categories_category_budget',
          'budget_categories_validate_insert',
          'budget_categories_validate_update',
          'budget_categories_overlap_insert',
          'budget_categories_overlap_update',
          'budgets_immutable_period',
        });
        expect(
          await newDb.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  });

  test(
    'invalid v3 category aborts migration before rebuilding ledger',
    () async {
      final schema = await verifier.schemaAt(3);
      final oldDb = v3.DatabaseAtV3(schema.newConnection());
      await oldDb.batch((batch) {
        batch.insert(
          oldDb.accounts,
          const v3.AccountsData(
            id: 1,
            name: 'Dompet',
            normalizedName: 'dompet',
            type: 0,
            isArchived: 0,
            createdAt: 1700000000000,
          ),
        );
        batch.insert(
          oldDb.categories,
          const v3.CategoriesData(
            id: 1,
            kind: 0,
            name: 'Gaji',
            normalizedName: 'gaji',
            iconKey: 'work',
            isArchived: 0,
            sortOrder: 0,
            systemKey: 'income.salary',
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
        batch.insert(
          oldDb.ledgerEntries,
          const v3.LedgerEntriesData(
            id: 1,
            kind: 0,
            accountId: 1,
            amount: 100,
            categoryId: 1,
            note: 'menunjuk kategori root',
            occurredDay: 20240101,
            createdAt: 1700000000010,
          ),
        );
      });
      await oldDb.close();

      final testedDb = AppDatabase(schema.newConnection());
      await expectLater(
        verifier.migrateAndValidate(testedDb, 4),
        throwsA(isA<StateError>()),
      );
      await testedDb.close();

      final checkDb = v3.DatabaseAtV3(schema.newConnection());
      final version = await checkDb
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 3);
      final preserved = await checkDb
          .customSelect('SELECT category_id FROM ledger_entries WHERE id = 1')
          .getSingle();
      expect(preserved.read<int>('category_id'), 1);
      final allocationTable = await checkDb.customSelect('''
      SELECT COUNT(*) AS amount FROM sqlite_schema
      WHERE type = 'table' AND name = 'ledger_allocations'
    ''').getSingle();
      expect(allocationTable.read<int>('amount'), 0);
      await checkDb.close();
      schema.close();
    },
  );
}
