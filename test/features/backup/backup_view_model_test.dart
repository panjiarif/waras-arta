import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/backup/backup_file_gateway.dart';
import 'package:waras_arta/data/backup/backup_service.dart';
import 'package:waras_arta/domain/backup.dart';
import 'package:waras_arta/features/backup/view_models/backup_view_model.dart';

void main() {
  test(
    'a second backup request is rejected while the first is running',
    () async {
      final operations = _BlockingBackupOperations();
      final files = _CountingFileGateway();
      final container = ProviderContainer(
        overrides: [
          backupOperationsProvider.overrideWithValue(operations),
          backupFileGatewayProvider.overrideWithValue(files),
          backupClockProvider.overrideWithValue(
            () => DateTime(2026, 9, 6, 14, 30, 12),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(backupControllerProvider.notifier);

      final first = controller.createBackup('kalimat-rahasia');
      await operations.started.future;
      expect(
        container.read(backupControllerProvider).phase,
        BackupPhase.preparingExport,
      );

      expect(
        await controller.createBackup('kalimat-rahasia'),
        BackupActionOutcome.busy,
      );
      expect(operations.createCount, 1);

      operations.result.complete(
        CreatedBackup(
          bytes: Uint8List.fromList([1, 2, 3]),
          suggestedName: 'backup.warasarta',
          summary: BackupSummary(
            createdAtUtc: DateTime.utc(2026, 9, 6),
            accountCount: 0,
            archivedAccountCount: 0,
            categoryCount: 0,
            archivedCategoryCount: 0,
            ledgerEntryCount: 0,
          ),
        ),
      );

      expect(await first, BackupActionOutcome.success);
      expect(files.saveCount, 1);
      expect(container.read(backupControllerProvider).phase, BackupPhase.idle);
    },
  );
}

class _BlockingBackupOperations implements BackupOperations {
  final started = Completer<void>();
  final result = Completer<CreatedBackup>();
  int createCount = 0;

  @override
  Future<CreatedBackup> create({
    required String password,
    required DateTime now,
  }) {
    createCount++;
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  Future<BackupRestorePlan> inspect({
    required Uint8List bytes,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> restore(BackupRestorePlan plan) => throw UnimplementedError();
}

class _CountingFileGateway implements BackupFileGateway {
  int saveCount = 0;

  @override
  Future<PickedBackupFile?> pick() => throw UnimplementedError();

  @override
  Future<bool> save({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    saveCount++;
    return true;
  }
}
