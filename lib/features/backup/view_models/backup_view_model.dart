import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/backup/backup_file_gateway.dart';
import '../../../data/backup/backup_service.dart';
import '../../../data/backup/drift_backup_data_store.dart';
import '../../../data/backup/encrypted_backup_codec.dart';
import '../../../domain/backup.dart';
import '../../../domain/backup_repository.dart';
import '../../calendar/view_models/calendar_view_model.dart';
import '../../categories/view_models/category_view_model.dart';
import '../../ledger/view_models/ledger_view_model.dart';

final backupClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final backupDataStoreProvider = Provider<BackupDataStore>((ref) {
  return DriftBackupDataStore(ref.watch(databaseProvider));
});

final encryptedBackupCodecProvider = Provider<EncryptedBackupCodec>((ref) {
  return EncryptedBackupCodec();
});

final backupOperationsProvider = Provider<BackupOperations>((ref) {
  return BackupService(
    dataStore: ref.watch(backupDataStoreProvider),
    codec: ref.watch(encryptedBackupCodecProvider),
  );
});

final backupFileGatewayProvider = Provider<BackupFileGateway>((ref) {
  return const SafBackupFileGateway();
});

enum BackupPhase {
  idle,
  preparingExport,
  savingFile,
  pickingFile,
  decrypting,
  restoring,
}

class BackupState {
  const BackupState({this.phase = BackupPhase.idle, this.error});

  final BackupPhase phase;
  final String? error;

  bool get isBusy => phase != BackupPhase.idle;
}

enum BackupActionOutcome { success, canceled, failed, busy }

final backupControllerProvider =
    NotifierProvider<BackupController, BackupState>(BackupController.new);

class BackupController extends Notifier<BackupState> {
  @override
  BackupState build() => const BackupState();

  void clearError() {
    if (!state.isBusy && state.error != null) state = const BackupState();
  }

  Future<BackupActionOutcome> createBackup(String password) async {
    if (state.isBusy) return BackupActionOutcome.busy;
    state = const BackupState(phase: BackupPhase.preparingExport);
    try {
      final now = ref.read(backupClockProvider)();
      final created = await ref
          .read(backupOperationsProvider)
          .create(password: password, now: now);
      if (!ref.mounted) return BackupActionOutcome.canceled;
      state = const BackupState(phase: BackupPhase.savingFile);
      final saved = await ref
          .read(backupFileGatewayProvider)
          .save(suggestedName: created.suggestedName, bytes: created.bytes);
      if (ref.mounted) state = const BackupState();
      return saved ? BackupActionOutcome.success : BackupActionOutcome.canceled;
    } catch (error) {
      _setError(error, fallback: 'Backup belum dapat dibuat. Coba lagi.');
      return BackupActionOutcome.failed;
    }
  }

  Future<PickedBackupFile?> pickRestoreFile() async {
    if (state.isBusy) return null;
    state = const BackupState(phase: BackupPhase.pickingFile);
    try {
      final file = await ref.read(backupFileGatewayProvider).pick();
      if (ref.mounted) state = const BackupState();
      return file;
    } catch (error) {
      _setError(
        error,
        fallback: 'File backup belum dapat dibuka. Periksa penyimpanan.',
      );
      return null;
    }
  }

  Future<BackupRestorePlan?> inspectRestore(
    Uint8List bytes,
    String password,
  ) async {
    if (state.isBusy) return null;
    state = const BackupState(phase: BackupPhase.decrypting);
    try {
      final plan = await ref
          .read(backupOperationsProvider)
          .inspect(bytes: bytes, password: password);
      if (ref.mounted) state = const BackupState();
      return plan;
    } catch (error) {
      _setError(
        error,
        fallback: 'Backup belum dapat dibaca. File mungkin tidak valid.',
      );
      return null;
    }
  }

  Future<BackupActionOutcome> restoreWithSafetyBackup(
    BackupRestorePlan plan,
    String password,
  ) async {
    if (state.isBusy) return BackupActionOutcome.busy;
    state = const BackupState(phase: BackupPhase.preparingExport);
    try {
      final now = ref.read(backupClockProvider)();
      final created = await ref
          .read(backupOperationsProvider)
          .create(password: password, now: now);
      if (!ref.mounted) return BackupActionOutcome.canceled;

      state = const BackupState(phase: BackupPhase.savingFile);
      final saved = await ref
          .read(backupFileGatewayProvider)
          .save(suggestedName: safetyBackupFileName(now), bytes: created.bytes);
      if (!ref.mounted) return BackupActionOutcome.canceled;
      if (!saved) {
        state = const BackupState();
        return BackupActionOutcome.canceled;
      }

      state = const BackupState(phase: BackupPhase.restoring);
      await ref.read(backupOperationsProvider).restore(plan);
      if (!ref.mounted) return BackupActionOutcome.canceled;
      ref.invalidate(financeSnapshotProvider);
      ref.invalidate(categoryTreeProvider);
      ref.invalidate(calendarMonthProvider);
      ref.invalidate(selectedCalendarDayEntriesProvider);
      state = const BackupState();
      return BackupActionOutcome.success;
    } catch (error) {
      _setError(error, fallback: 'Restore gagal. Data lama tetap tersimpan.');
      return BackupActionOutcome.failed;
    }
  }

  void _setError(Object error, {required String fallback}) {
    if (!ref.mounted) return;
    final message = switch (error) {
      BackupException(:final message) => message,
      BackupFileException(:final message) => message,
      _ => fallback,
    };
    state = BackupState(error: message);
  }
}
