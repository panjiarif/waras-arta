import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/backup/backup_service.dart';
import 'package:waras_arta/data/backup/encrypted_backup_codec.dart';
import 'package:waras_arta/domain/backup.dart';
import 'package:waras_arta/domain/backup_repository.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
  const password = 'sandi-rahasia';
  final now = DateTime.utc(2026, 9, 6, 7, 5);

  group('BackupService', () {
    test(
      'create exports UTC data and returns encrypted bytes and name',
      () async {
        final document = _backupDocument(createdAtUtc: now);
        final store = _FakeBackupDataStore(
          databaseSchemaVersion: 5,
          documentToExport: document,
        );
        final codec = _testCodec();
        final service = BackupService(dataStore: store, codec: codec);

        final created = await service.create(password: password, now: now);

        expect(store.exportCalls, 1);
        expect(store.lastExportCreatedAtUtc, now.toUtc());
        expect(
          created.suggestedName,
          'waras-arta-backup-20260906-070500.warasarta',
        );
        expect(created.summary.accountCount, 1);
        expect(created.summary.categoryCount, 4);
        expect(created.summary.ledgerEntryCount, 0);
        expect(created.bytes, isNotEmpty);
        expect(
          (await codec.decrypt(created.bytes, password: password)).toJson(),
          document.toJson(),
        );
      },
    );

    test(
      'inspect returns a plan that restore delegates to the store',
      () async {
        final document = _backupDocument(createdAtUtc: now);
        final store = _FakeBackupDataStore(
          databaseSchemaVersion: 5,
          documentToExport: document,
        );
        final codec = _testCodec();
        final service = BackupService(dataStore: store, codec: codec);
        final bytes = await codec.encrypt(document, password: password);

        final plan = await service.inspect(bytes: bytes, password: password);
        await service.restore(plan);

        expect(plan.summary.accountCount, 1);
        expect(plan.summary.categoryCount, 4);
        expect(store.restoreCalls, 1);
        expect(store.lastRestoredDocument?.toJson(), document.toJson());
      },
    );

    test('inspect accepts a v1/schema 3 backup on target schema 5', () async {
      final document = _backupDocument(
        backupVersion: 1,
        databaseSchemaVersion: 3,
        createdAtUtc: now,
      );
      final store = _FakeBackupDataStore(
        databaseSchemaVersion: 5,
        documentToExport: document,
      );
      final codec = _testCodec();
      final service = BackupService(dataStore: store, codec: codec);
      final bytes = await codec.encrypt(document, password: password);

      final plan = await service.inspect(bytes: bytes, password: password);
      await service.restore(plan);

      expect(plan.document.backupVersion, 1);
      expect(plan.document.databaseSchemaVersion, 3);
      expect(store.restoreCalls, 1);
    });

    test('inspect rejects a valid v3 backup on target schema 4', () async {
      final document = _backupDocument(createdAtUtc: now);
      final store = _FakeBackupDataStore(
        databaseSchemaVersion: 4,
        documentToExport: document,
      );
      final codec = _testCodec();
      final service = BackupService(dataStore: store, codec: codec);
      final bytes = await codec.encrypt(document, password: password);

      await expectLater(
        service.inspect(bytes: bytes, password: password),
        throwsA(
          isA<BackupValidationException>().having(
            (error) => error.message,
            'message',
            contains('Versi database'),
          ),
        ),
      );

      expect(store.restoreCalls, 0);
      expect(store.lastRestoredDocument, isNull);
    });
  });

  test('backupFileName pads calendar components and uses the extension', () {
    expect(
      backupFileName(DateTime(2026, 1, 2, 3, 4)),
      'waras-arta-backup-20260102-030400.warasarta',
    );
    expect(
      safetyBackupFileName(DateTime(2026, 1, 2, 3, 4)),
      'waras-arta-sebelum-restore-20260102-030400.warasarta',
    );
  });
}

class _FakeBackupDataStore implements BackupDataStore {
  _FakeBackupDataStore({
    required this.databaseSchemaVersion,
    required this.documentToExport,
  });

  @override
  final int databaseSchemaVersion;

  final BackupDocument documentToExport;
  int exportCalls = 0;
  int restoreCalls = 0;
  DateTime? lastExportCreatedAtUtc;
  BackupDocument? lastRestoredDocument;

  @override
  Future<BackupDocument> exportDocument({
    required DateTime createdAtUtc,
  }) async {
    exportCalls++;
    lastExportCreatedAtUtc = createdAtUtc;
    return documentToExport;
  }

  @override
  Future<void> restoreDocument(BackupDocument document) async {
    restoreCalls++;
    lastRestoredDocument = document;
  }
}

EncryptedBackupCodec _testCodec() {
  var nextByte = 0;
  return EncryptedBackupCodec(
    parameters: const BackupCryptoParameters(
      memoryKiB: 8,
      iterations: 1,
      parallelism: 1,
      keyLength: 32,
    ),
    randomBytes: (length) {
      final result = Uint8List(length);
      for (var index = 0; index < length; index++) {
        result[index] = nextByte++ & 0xff;
      }
      return result;
    },
  );
}

BackupDocument _backupDocument({
  int backupVersion = currentBackupVersion,
  int databaseSchemaVersion = 5,
  required DateTime createdAtUtc,
}) {
  final rowCreatedAt = DateTime.utc(2026, 9, 5, 4, 30);
  return BackupDocument(
    backupVersion: backupVersion,
    databaseSchemaVersion: databaseSchemaVersion,
    createdAtUtc: createdAtUtc,
    sequences: const BackupSequences(
      accounts: 1,
      categories: 4,
      ledgerEntries: 0,
    ),
    accounts: [
      BackupAccount(
        id: 1,
        name: 'Dompet',
        normalizedName: 'dompet',
        type: AccountType.cash,
        isArchived: false,
        createdAtUtc: rowCreatedAt,
      ),
    ],
    categories: [
      BackupCategory(
        id: 1,
        parentId: null,
        kind: CategoryKind.income,
        name: 'Pemasukan',
        normalizedName: 'pemasukan',
        iconKey: 'work',
        isArchived: false,
        sortOrder: 0,
        systemKey: null,
        createdAtUtc: rowCreatedAt,
        updatedAtUtc: rowCreatedAt,
      ),
      BackupCategory(
        id: 2,
        parentId: 1,
        kind: CategoryKind.income,
        name: 'Umum',
        normalizedName: 'umum',
        iconKey: 'work',
        isArchived: false,
        sortOrder: 0,
        systemKey: null,
        createdAtUtc: rowCreatedAt,
        updatedAtUtc: rowCreatedAt,
      ),
      BackupCategory(
        id: 3,
        parentId: null,
        kind: CategoryKind.expense,
        name: 'Pengeluaran',
        normalizedName: 'pengeluaran',
        iconKey: 'work',
        isArchived: false,
        sortOrder: 0,
        systemKey: null,
        createdAtUtc: rowCreatedAt,
        updatedAtUtc: rowCreatedAt,
      ),
      BackupCategory(
        id: 4,
        parentId: 3,
        kind: CategoryKind.expense,
        name: 'Umum',
        normalizedName: 'umum',
        iconKey: 'work',
        isArchived: false,
        sortOrder: 0,
        systemKey: null,
        createdAtUtc: rowCreatedAt,
        updatedAtUtc: rowCreatedAt,
      ),
    ],
    ledgerEntries: const [],
  );
}
