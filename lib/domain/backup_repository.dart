import 'backup.dart';

abstract interface class BackupDataStore {
  int get databaseSchemaVersion;

  Future<BackupDocument> exportDocument({required DateTime createdAtUtc});

  Future<void> restoreDocument(BackupDocument document);
}
