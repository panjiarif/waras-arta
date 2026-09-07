import 'dart:typed_data';

import '../../domain/backup.dart';
import '../../domain/backup_repository.dart';
import 'encrypted_backup_codec.dart';

class CreatedBackup {
  const CreatedBackup({
    required this.bytes,
    required this.suggestedName,
    required this.summary,
  });

  final Uint8List bytes;
  final String suggestedName;
  final BackupSummary summary;
}

class BackupRestorePlan {
  const BackupRestorePlan({required this.document});

  final BackupDocument document;
  BackupSummary get summary => document.summary;
}

abstract interface class BackupOperations {
  Future<CreatedBackup> create({
    required String password,
    required DateTime now,
  });

  Future<BackupRestorePlan> inspect({
    required Uint8List bytes,
    required String password,
  });

  Future<void> restore(BackupRestorePlan plan);
}

class BackupService implements BackupOperations {
  BackupService({required this.dataStore, required this.codec});

  final BackupDataStore dataStore;
  final EncryptedBackupCodec codec;

  @override
  Future<CreatedBackup> create({
    required String password,
    required DateTime now,
  }) async {
    final document = await dataStore.exportDocument(createdAtUtc: now.toUtc());
    final bytes = await codec.encrypt(document, password: password);
    return CreatedBackup(
      bytes: bytes,
      suggestedName: backupFileName(now),
      summary: document.summary,
    );
  }

  @override
  Future<BackupRestorePlan> inspect({
    required Uint8List bytes,
    required String password,
  }) async {
    final document = await codec.decrypt(bytes, password: password);
    validateBackupDocument(document);
    if (document.databaseSchemaVersion != dataStore.databaseSchemaVersion) {
      throw const BackupValidationException(
        'Versi database pada backup belum didukung oleh aplikasi ini.',
      );
    }
    return BackupRestorePlan(document: document);
  }

  @override
  Future<void> restore(BackupRestorePlan plan) =>
      dataStore.restoreDocument(plan.document);
}

String backupFileName(DateTime value) {
  return _datedBackupFileName(value, label: 'backup');
}

String safetyBackupFileName(DateTime value) {
  return _datedBackupFileName(value, label: 'sebelum-restore');
}

String _datedBackupFileName(DateTime value, {required String label}) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return 'waras-arta-$label-${value.year}'
      '${twoDigits(value.month)}${twoDigits(value.day)}-'
      '${twoDigits(value.hour)}${twoDigits(value.minute)}'
      '${twoDigits(value.second)}.warasarta';
}
