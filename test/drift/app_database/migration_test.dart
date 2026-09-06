// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:waras_arta/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;

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

  test(
    'migration from v1 to v3 runs category and account steps in order',
    () async {
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
        newVersion: 3,
        createOld: v1.DatabaseAtV1.new,
        createNew: v3.DatabaseAtV3.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch.insertAll(oldDb.accounts, accountsV1);
          batch.insertAll(oldDb.ledgerEntries, entriesV1);
        },
        validateItems: (newDb) async {
          final accounts = await newDb.select(newDb.accounts).get();
          accounts.sort((a, b) => a.id.compareTo(b.id));
          expect(accounts, const [
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
          ]);
          final entries = await newDb.select(newDb.ledgerEntries).get();
          entries.sort((a, b) => a.id.compareTo(b.id));
          expect(entries.map((row) => row.categoryId), [8, 22, null, null]);
          expect(entries.map((row) => row.amount), [100, 40, 10, 5]);
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
    },
  );
}
