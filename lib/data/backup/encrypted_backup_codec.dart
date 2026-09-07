import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:cryptography/helpers.dart' as crypto_helpers;
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../../domain/backup.dart';
import 'backup_file_gateway.dart';

const encryptedBackupFormat = 'waras-arta-encrypted-backup';
const currentBackupContainerVersion = 1;
const minimumBackupPasswordLength = 12;
const maximumBackupPasswordLength = 128;
const maxBackupPlaintextBytes = 10 * 1024 * 1024;

typedef BackupRandomBytes = Uint8List Function(int length);

// Keep this profile readable when adding a future container version. New
// work factors require version-routed decoding rather than replacing v1.
const backupContainerV1CryptoParameters = BackupCryptoParameters();

String normalizeBackupPassword(String password) => unicode.nfc(password);

class BackupCryptoParameters {
  const BackupCryptoParameters({
    this.memoryKiB = 19 * 1024,
    this.iterations = 2,
    this.parallelism = 1,
    this.keyLength = 32,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int keyLength;
}

String? validateNewBackupPassword(String password) {
  password = normalizeBackupPassword(password);
  final length = password.runes.length;
  if (password.trim().isEmpty) return 'Kata sandi wajib diisi.';
  if (password.trim() != password) {
    return 'Hapus spasi di awal atau akhir kata sandi.';
  }
  if (length < minimumBackupPasswordLength) {
    return 'Gunakan minimal $minimumBackupPasswordLength karakter.';
  }
  if (length > maximumBackupPasswordLength) {
    return 'Kata sandi maksimal $maximumBackupPasswordLength karakter.';
  }
  return null;
}

String? validateBackupPasswordForRestore(String password) {
  password = normalizeBackupPassword(password);
  if (password.isEmpty) return 'Kata sandi wajib diisi.';
  if (password.trim() != password) {
    return 'Hapus spasi di awal atau akhir kata sandi.';
  }
  if (password.runes.length < minimumBackupPasswordLength) {
    return 'Kata sandi backup minimal $minimumBackupPasswordLength karakter.';
  }
  if (password.runes.length > maximumBackupPasswordLength) {
    return 'Kata sandi maksimal $maximumBackupPasswordLength karakter.';
  }
  return null;
}

class EncryptedBackupCodec {
  EncryptedBackupCodec({
    this.parameters = backupContainerV1CryptoParameters,
    BackupRandomBytes? randomBytes,
  }) : _randomBytes = randomBytes ?? _systemRandomBytes;

  final BackupCryptoParameters parameters;
  final BackupRandomBytes _randomBytes;

  Future<Uint8List> encrypt(
    BackupDocument document, {
    required String password,
  }) async {
    final passwordError = validateNewBackupPassword(password);
    if (passwordError != null) {
      throw BackupValidationException(passwordError);
    }
    _validateKdfParameters(parameters);
    validateBackupDocument(document, requireSequenceHeadroom: false);
    _validatePayloadBudget(document);

    final salt = _randomBytes(16);
    final cipher = crypto.Xchacha20.poly1305Aead();
    final nonce = _randomBytes(cipher.nonceLength);
    if (salt.length != 16 || nonce.length != cipher.nonceLength) {
      throw const BackupFormatException(
        'Generator acak tidak menghasilkan ukuran yang diperlukan.',
      );
    }

    final header = <String, Object?>{
      'format': encryptedBackupFormat,
      'containerVersion': currentBackupContainerVersion,
      'kdf': <String, Object?>{
        'name': 'argon2id',
        'version': 19,
        'normalization': 'NFC',
        'memoryKiB': parameters.memoryKiB,
        'iterations': parameters.iterations,
        'parallelism': parameters.parallelism,
        'keyLength': parameters.keyLength,
        'salt': base64Encode(salt),
      },
      'cipher': <String, Object?>{
        'name': 'xchacha20-poly1305',
        'nonce': base64Encode(nonce),
      },
    };
    final headerBytes = Uint8List.fromList(utf8.encode(jsonEncode(header)));
    final clearBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(document.toJson())),
    );
    if (clearBytes.lengthInBytes > maxBackupPlaintextBytes) {
      clearBytes.fillRange(0, clearBytes.length, 0);
      throw const BackupFormatException(
        'Isi backup terlalu besar untuk versi aplikasi ini.',
      );
    }
    crypto.SecretKey? secretKey;
    try {
      secretKey = await _deriveKey(
        password: normalizeBackupPassword(password),
        salt: salt,
        parameters: parameters,
      );
      final encrypted = await cipher.encrypt(
        clearBytes,
        secretKey: secretKey,
        nonce: nonce,
        aad: headerBytes,
      );
      final envelope = <String, Object?>{
        'format': encryptedBackupFormat,
        'containerVersion': currentBackupContainerVersion,
        'header': base64Encode(headerBytes),
        'cipherText': base64Encode(encrypted.cipherText),
        'mac': base64Encode(encrypted.mac.bytes),
      };
      final result = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
      if (result.lengthInBytes > maxBackupFileBytes) {
        throw const BackupFormatException(
          'Backup terlalu besar untuk versi aplikasi ini.',
        );
      }
      return result;
    } finally {
      secretKey?.destroy();
      clearBytes.fillRange(0, clearBytes.length, 0);
    }
  }

  Future<BackupDocument> decrypt(
    Uint8List bytes, {
    required String password,
  }) async {
    final passwordError = validateBackupPasswordForRestore(password);
    if (passwordError != null) {
      throw BackupValidationException(passwordError);
    }
    if (bytes.isEmpty || bytes.lengthInBytes > maxBackupFileBytes) {
      throw const BackupFormatException(
        'Ukuran file backup tidak valid atau tidak didukung.',
      );
    }

    final envelope = _decodeObject(bytes, 'File backup tidak valid.');
    _requireExactKeys(envelope, const {
      'format',
      'containerVersion',
      'header',
      'cipherText',
      'mac',
    }, 'container');
    if (_readString(envelope, 'format') != encryptedBackupFormat) {
      throw const BackupFormatException('File bukan backup Waras Arta.');
    }
    final containerVersion = _readInt(envelope, 'containerVersion');
    if (containerVersion != 1) {
      throw const BackupFormatException(
        'Versi enkripsi backup belum didukung oleh aplikasi ini.',
      );
    }

    final headerBytes = _readBase64(envelope, 'header', maximumLength: 4096);
    final header = _decodeObject(headerBytes, 'Header backup tidak valid.');
    _requireExactKeys(header, const {
      'format',
      'containerVersion',
      'kdf',
      'cipher',
    }, 'header');
    if (_readString(header, 'format') != encryptedBackupFormat ||
        _readInt(header, 'containerVersion') != containerVersion) {
      throw const BackupFormatException('Header backup tidak didukung.');
    }

    final kdf = _readObject(header, 'kdf');
    _requireExactKeys(kdf, const {
      'name',
      'version',
      'normalization',
      'memoryKiB',
      'iterations',
      'parallelism',
      'keyLength',
      'salt',
    }, 'kdf');
    if (_readString(kdf, 'name') != 'argon2id' ||
        _readInt(kdf, 'version') != 19 ||
        _readString(kdf, 'normalization') != 'NFC') {
      throw const BackupFormatException(
        'Metode kata sandi backup belum didukung.',
      );
    }
    final decodedParameters = BackupCryptoParameters(
      memoryKiB: _readInt(kdf, 'memoryKiB'),
      iterations: _readInt(kdf, 'iterations'),
      parallelism: _readInt(kdf, 'parallelism'),
      keyLength: _readInt(kdf, 'keyLength'),
    );
    _validateKdfParameters(decodedParameters);
    if (!_sameKdfProfile(decodedParameters, parameters)) {
      throw const BackupFormatException(
        'Profil keamanan backup belum didukung oleh aplikasi ini.',
      );
    }
    final salt = _readBase64(kdf, 'salt', expectedLength: 16);

    final cipherData = _readObject(header, 'cipher');
    _requireExactKeys(cipherData, const {'name', 'nonce'}, 'cipher');
    if (_readString(cipherData, 'name') != 'xchacha20-poly1305') {
      throw const BackupFormatException(
        'Metode enkripsi backup belum didukung.',
      );
    }
    final cipher = crypto.Xchacha20.poly1305Aead();
    final nonce = _readBase64(
      cipherData,
      'nonce',
      expectedLength: cipher.nonceLength,
    );
    final cipherText = _readBase64(
      envelope,
      'cipherText',
      maximumLength: maxBackupPlaintextBytes,
    );
    final mac = _readBase64(
      envelope,
      'mac',
      expectedLength: cipher.macAlgorithm.macLength,
    );

    crypto.SecretKey? secretKey;
    Uint8List? clearBytes;
    try {
      secretKey = await _deriveKey(
        password: normalizeBackupPassword(password),
        salt: salt,
        parameters: decodedParameters,
      );
      try {
        clearBytes = Uint8List.fromList(
          await cipher.decrypt(
            crypto.SecretBox(cipherText, nonce: nonce, mac: crypto.Mac(mac)),
            secretKey: secretKey,
            aad: headerBytes,
          ),
        );
        if (clearBytes.lengthInBytes > maxBackupPlaintextBytes) {
          throw const BackupFormatException(
            'Isi backup terlalu besar untuk versi aplikasi ini.',
          );
        }
      } on crypto.SecretBoxAuthenticationError {
        throw const BackupFormatException(
          'Kata sandi salah atau file backup rusak.',
        );
      }
      final payload = _decodeObject(
        clearBytes,
        'Isi backup tidak valid atau rusak.',
      );
      return BackupDocument.fromJson(payload);
    } on BackupException {
      rethrow;
    } catch (error) {
      throw BackupFormatException(
        'Kata sandi salah atau file backup rusak.',
        cause: error,
      );
    } finally {
      secretKey?.destroy();
      clearBytes?.fillRange(0, clearBytes.length, 0);
    }
  }

  static Future<crypto.SecretKey> _deriveKey({
    required String password,
    required List<int> salt,
    required BackupCryptoParameters parameters,
  }) {
    return crypto.Argon2id(
      parallelism: parameters.parallelism,
      memory: parameters.memoryKiB,
      iterations: parameters.iterations,
      hashLength: parameters.keyLength,
    ).deriveKeyFromPassword(password: password, nonce: salt);
  }

  static void _validateKdfParameters(BackupCryptoParameters value) {
    if (value.memoryKiB < 8 ||
        value.memoryKiB > 128 * 1024 ||
        value.iterations < 1 ||
        value.iterations > 10 ||
        value.parallelism < 1 ||
        value.parallelism > 4 ||
        value.keyLength != 32 ||
        value.memoryKiB < 8 * value.parallelism) {
      throw const BackupFormatException(
        'Parameter keamanan backup tidak valid atau terlalu berat.',
      );
    }
  }
}

Uint8List _systemRandomBytes(int length) =>
    crypto_helpers.randomBytes(length, random: crypto.SecureRandom.system);

bool _sameKdfProfile(
  BackupCryptoParameters left,
  BackupCryptoParameters right,
) =>
    left.memoryKiB == right.memoryKiB &&
    left.iterations == right.iterations &&
    left.parallelism == right.parallelism &&
    left.keyLength == right.keyLength;

void _validatePayloadBudget(BackupDocument document) {
  var estimatedBytes = 1024;
  for (final account in document.accounts) {
    estimatedBytes +=
        256 + 6 * (account.name.length + account.normalizedName.length);
  }
  for (final category in document.categories) {
    estimatedBytes +=
        384 +
        6 *
            (category.name.length +
                category.normalizedName.length +
                category.iconKey.length +
                (category.systemKey?.length ?? 0));
  }
  for (final entry in document.ledgerEntries) {
    estimatedBytes += 256 + 6 * entry.note.length;
  }
  if (estimatedBytes > maxBackupPlaintextBytes) {
    throw const BackupFormatException(
      'Isi backup terlalu besar untuk versi aplikasi ini.',
    );
  }
}

Map<String, Object?> _decodeObject(Uint8List bytes, String message) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return decoded.cast<String, Object?>();
  } catch (error) {
    throw BackupFormatException(message, cause: error);
  }
  throw BackupFormatException(message);
}

Map<String, Object?> _readObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    try {
      return value.cast<String, Object?>();
    } catch (_) {
      // Report one stable format error below.
    }
  }
  throw BackupFormatException('Field $key pada backup tidak valid.');
}

void _requireExactKeys(
  Map<String, Object?> json,
  Set<String> expected,
  String path,
) {
  if (json.length != expected.length ||
      !json.keys.toSet().containsAll(expected)) {
    throw BackupFormatException(
      'Struktur $path tidak cocok dengan versi enkripsi ini.',
    );
  }
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw BackupFormatException('Field $key pada backup tidak valid.');
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw BackupFormatException('Field $key pada backup tidak valid.');
}

Uint8List _readBase64(
  Map<String, Object?> json,
  String key, {
  int? expectedLength,
  int? maximumLength,
}) {
  try {
    final encoded = _readString(json, key);
    final decodedLimit = expectedLength ?? maximumLength;
    if (decodedLimit != null &&
        encoded.length > ((decodedLimit + 2) ~/ 3) * 4) {
      throw const FormatException();
    }
    final value = Uint8List.fromList(base64Decode(encoded));
    if ((expectedLength != null && value.length != expectedLength) ||
        (maximumLength != null && value.length > maximumLength)) {
      throw const FormatException();
    }
    return value;
  } catch (error) {
    if (error is BackupException) rethrow;
    throw BackupFormatException(
      'Field $key pada backup tidak valid.',
      cause: error,
    );
  }
}
