import 'package:flutter/services.dart';

const backupFileExtension = 'warasarta';
const maxBackupFileBytes = 16 * 1024 * 1024;

class PickedBackupFile {
  const PickedBackupFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class BackupFileException implements Exception {
  const BackupFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class BackupFileGateway {
  Future<bool> save({required String suggestedName, required Uint8List bytes});

  Future<PickedBackupFile?> pick();
}

const backupFileChannelName = 'io.github.panjiarif.waras_arta/backup_files';

class SafBackupFileGateway implements BackupFileGateway {
  const SafBackupFileGateway({
    this._channel = const MethodChannel(backupFileChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<bool> save({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    if (bytes.lengthInBytes > maxBackupFileBytes) {
      throw const BackupFileException(
        'Backup terlalu besar untuk disimpan oleh versi aplikasi ini.',
      );
    }
    try {
      final saved = await _channel.invokeMethod<bool>('saveBackup', {
        'suggestedName': suggestedName,
        'bytes': bytes,
        'maxBytes': maxBackupFileBytes,
      });
      return saved ?? false;
    } on PlatformException catch (error) {
      throw BackupFileException(_saveErrorMessage(error.code));
    } on MissingPluginException {
      throw const BackupFileException(
        'Penyimpanan backup belum tersedia pada perangkat ini.',
      );
    }
  }

  @override
  Future<PickedBackupFile?> pick() async {
    try {
      final selected = await _channel.invokeMethod<Object?>('pickBackup', {
        'maxBytes': maxBackupFileBytes,
      });
      if (selected == null) return null;
      if (selected is! Map) {
        throw const BackupFileException(
          'Hasil pemilihan file backup tidak valid.',
        );
      }
      final name = selected['name'];
      final bytes = selected['bytes'];
      if (name is! String || name.isEmpty || bytes is! Uint8List) {
        throw const BackupFileException(
          'Hasil pemilihan file backup tidak valid.',
        );
      }
      if (bytes.lengthInBytes > maxBackupFileBytes) {
        throw const BackupFileException(
          'File backup melebihi batas 16 MB dan tidak dapat dibuka.',
        );
      }
      return PickedBackupFile(name: name, bytes: bytes);
    } on BackupFileException {
      rethrow;
    } on PlatformException catch (error) {
      throw BackupFileException(_pickErrorMessage(error.code));
    } on MissingPluginException {
      throw const BackupFileException(
        'Pemilih file backup belum tersedia pada perangkat ini.',
      );
    }
  }
}

String _saveErrorMessage(String code) => switch (code) {
  'busy' => 'Pemilih file sedang digunakan. Tunggu lalu coba lagi.',
  'file_too_large' =>
    'Backup terlalu besar untuk disimpan oleh versi aplikasi ini.',
  'write_verification_failed' =>
    'File tersimpan tidak dapat diverifikasi dan backup dianggap gagal.',
  _ => 'File backup belum dapat disimpan. Pilih lokasi lain lalu coba lagi.',
};

String _pickErrorMessage(String code) => switch (code) {
  'busy' => 'Pemilih file sedang digunakan. Tunggu lalu coba lagi.',
  'file_too_large' =>
    'File backup melebihi batas 16 MB dan tidak dapat dibuka.',
  _ => 'File backup belum dapat dibaca. Pilih file lain lalu coba lagi.',
};
