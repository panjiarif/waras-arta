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
  TextColumn get category => text().nullable()();
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
      (kind IN (0, 1) AND destination_account_id IS NULL AND category IS NOT NULL)
      OR (kind = 2 AND destination_account_id IS NOT NULL
        AND destination_account_id <> account_id AND category IS NULL)
      OR (kind = 3 AND destination_account_id IS NULL AND category IS NULL)
    )''',
    '''CHECK (
      (kind = 0 AND category IN ('Gaji', 'Usaha', 'Hadiah', 'Lainnya'))
      OR (kind = 1 AND category IN (
        'Makan & minum', 'Transportasi', 'Belanja', 'Tagihan',
        'Kesehatan', 'Hiburan', 'Lainnya'
      ))
      OR kind IN (2, 3)
    )''',
  ];
}

@DriftDatabase(tables: [Accounts, LedgerEntries])
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement(
        'CREATE INDEX ledger_entries_occurred_day_id '
        'ON ledger_entries (occurred_day DESC, id DESC)',
      );
      await customStatement(
        'CREATE INDEX ledger_entries_account_id ON ledger_entries (account_id)',
      );
      await customStatement(
        'CREATE INDEX ledger_entries_destination_account_id '
        'ON ledger_entries (destination_account_id)',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
