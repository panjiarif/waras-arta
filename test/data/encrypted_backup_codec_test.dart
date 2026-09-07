import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/backup/encrypted_backup_codec.dart';
import 'package:waras_arta/domain/backup.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
  const password = 'sandi-rahasia';

  group('EncryptedBackupCodec', () {
    test('freezes the production KDF profile for container v1', () {
      expect(backupContainerV1CryptoParameters.memoryKiB, 19 * 1024);
      expect(backupContainerV1CryptoParameters.iterations, 2);
      expect(backupContainerV1CryptoParameters.parallelism, 1);
      expect(backupContainerV1CryptoParameters.keyLength, 32);
    });

    test('round-trips a valid backup document', () async {
      final codec = _testCodec();
      final original = _backupDocument();

      final encrypted = await codec.encrypt(original, password: password);
      final decrypted = await codec.decrypt(encrypted, password: password);

      expect(decrypted.toJson(), original.toJson());
    });

    test('normalizes visually equivalent passwords to NFC', () async {
      final codec = _testCodec();
      const composed = 'rahasia-caf\u00e9';
      const decomposed = 'rahasia-cafe\u0301';

      final encrypted = await codec.encrypt(
        _backupDocument(),
        password: composed,
      );

      expect(
        (await codec.decrypt(encrypted, password: decomposed)).toJson(),
        _backupDocument().toJson(),
      );
    });

    test('rejects a wrong password', () async {
      final codec = _testCodec();
      final encrypted = await codec.encrypt(
        _backupDocument(),
        password: password,
      );

      await expectLater(
        codec.decrypt(encrypted, password: 'sandi-yang-lain'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects tampered ciphertext', () async {
      final codec = _testCodec();
      final encrypted = await codec.encrypt(
        _backupDocument(),
        password: password,
      );
      final tampered = _editEnvelope(encrypted, (envelope) {
        final cipherText = base64Decode(envelope['cipherText']! as String);
        cipherText[0] ^= 1;
        envelope['cipherText'] = base64Encode(cipherText);
      });

      await expectLater(
        codec.decrypt(tampered, password: password),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects tampered authenticated header', () async {
      final codec = _testCodec();
      final encrypted = await codec.encrypt(
        _backupDocument(),
        password: password,
      );
      final tampered = _editHeader(encrypted, (header) {
        final cipher = (header['cipher']! as Map).cast<String, Object?>();
        final nonce = base64Decode(cipher['nonce']! as String);
        nonce[0] ^= 1;
        cipher['nonce'] = base64Encode(nonce);
        header['cipher'] = cipher;
      });

      await expectLater(
        codec.decrypt(tampered, password: password),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('encrypted container does not expose sensitive plaintext', () async {
      final codec = _testCodec();

      final encrypted = await codec.encrypt(
        _backupDocument(),
        password: password,
      );
      final containerText = utf8.decode(encrypted);

      expect(containerText, isNot(contains('Dompet Rahasia')));
      expect(containerText, isNot(contains('PIN bank 9876')));
      expect(containerText, isNot(contains('dompet rahasia')));
    });

    test('enforces new and restore password boundaries', () {
      expect(
        validateNewBackupPassword('a' * (minimumBackupPasswordLength - 1)),
        isNotNull,
      );
      expect(
        validateNewBackupPassword('a' * minimumBackupPasswordLength),
        isNull,
      );
      expect(validateNewBackupPassword('a' * 128), isNull);
      expect(validateNewBackupPassword('a' * 129), isNotNull);
      expect(validateNewBackupPassword('          '), isNotNull);
      expect(validateNewBackupPassword(' sandi-rahasia'), isNotNull);
      expect(validateNewBackupPassword('sandi-rahasia '), isNotNull);

      expect(validateBackupPasswordForRestore('a'), isNotNull);
      expect(validateBackupPasswordForRestore(''), isNotNull);
      expect(
        validateBackupPasswordForRestore('a' * minimumBackupPasswordLength),
        isNull,
      );
      expect(validateBackupPasswordForRestore('a' * 128), isNull);
      expect(validateBackupPasswordForRestore('a' * 129), isNotNull);
      expect(validateBackupPasswordForRestore(' sandi-rahasia'), isNotNull);
      expect(validateBackupPasswordForRestore('sandi-rahasia '), isNotNull);
    });

    test('uses a new random salt and nonce for every backup', () async {
      final codec = EncryptedBackupCodec(
        parameters: const BackupCryptoParameters(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
          keyLength: 32,
        ),
      );

      final first = await codec.encrypt(_backupDocument(), password: password);
      final second = await codec.encrypt(_backupDocument(), password: password);

      expect(first, isNot(orderedEquals(second)));
      final firstEnvelope = (jsonDecode(utf8.decode(first)) as Map)
          .cast<String, Object?>();
      final secondEnvelope = (jsonDecode(utf8.decode(second)) as Map)
          .cast<String, Object?>();
      expect(firstEnvelope['header'], isNot(secondEnvelope['header']));
      expect(firstEnvelope['cipherText'], isNot(secondEnvelope['cipherText']));
    });

    test('accepts the minimum supported KDF work factors', () async {
      final codec = _testCodec(
        parameters: const BackupCryptoParameters(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
          keyLength: 32,
        ),
      );

      final encrypted = await codec.encrypt(
        _backupDocument(),
        password: password,
      );

      expect(
        (await codec.decrypt(encrypted, password: password)).toJson(),
        _backupDocument().toJson(),
      );
    });

    test('rejects invalid KDF parameters before encryption', () async {
      const invalidParameters = <BackupCryptoParameters>[
        BackupCryptoParameters(
          memoryKiB: 7,
          iterations: 1,
          parallelism: 1,
          keyLength: 32,
        ),
        BackupCryptoParameters(
          memoryKiB: 8,
          iterations: 0,
          parallelism: 1,
          keyLength: 32,
        ),
        BackupCryptoParameters(
          memoryKiB: 8,
          iterations: 11,
          parallelism: 1,
          keyLength: 32,
        ),
        BackupCryptoParameters(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 2,
          keyLength: 32,
        ),
        BackupCryptoParameters(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
          keyLength: 31,
        ),
      ];

      for (final parameters in invalidParameters) {
        final codec = _testCodec(parameters: parameters);
        await expectLater(
          codec.encrypt(_backupDocument(), password: password),
          throwsA(isA<BackupFormatException>()),
        );
      }
    });

    test('rejects excessive KDF parameters from an untrusted header', () async {
      final codec = _testCodec();
      final encrypted = await codec.encrypt(
        _backupDocument(),
        password: password,
      );
      final tampered = _editHeader(encrypted, (header) {
        final kdf = (header['kdf']! as Map).cast<String, Object?>();
        kdf['memoryKiB'] = 128 * 1024 + 1;
        header['kdf'] = kdf;
      });

      await expectLater(
        codec.decrypt(tampered, password: password),
        throwsA(
          isA<BackupFormatException>().having(
            (error) => error.message,
            'message',
            contains('Parameter keamanan'),
          ),
        ),
      );
    });

    test(
      'rejects a different in-range KDF profile before derivation',
      () async {
        final codec = _testCodec();
        final encrypted = await codec.encrypt(
          _backupDocument(),
          password: password,
        );
        final tampered = _editHeader(encrypted, (header) {
          final kdf = (header['kdf']! as Map).cast<String, Object?>();
          kdf['iterations'] = 2;
          header['kdf'] = kdf;
        });

        await expectLater(
          codec.decrypt(tampered, password: password),
          throwsA(
            isA<BackupFormatException>().having(
              (error) => error.message,
              'message',
              contains('Profil keamanan'),
            ),
          ),
        );
      },
    );

    test('rejects minimum int adjustment before restore preview', () {
      final json = _backupDocument().toJson();
      final data = json['data']! as Map<String, Object?>;
      final entries = data['ledgerEntries']! as List<Object?>;
      final entry = entries.single as Map<String, Object?>;
      entry['kind'] = EntryKind.adjustment.name;
      entry['amount'] = -9223372036854775808;
      entry['categoryId'] = null;

      expect(
        () => BackupDocument.fromJson(json),
        throwsA(
          isA<BackupValidationException>().having(
            (error) => error.message,
            'message',
            contains('Nominal penyesuaian'),
          ),
        ),
      );
    });

    test('rejects an ID sequence that can exhaust SQLite autoincrement', () {
      final json = _backupDocument().toJson();
      final sequences = json['sequences']! as Map<String, Object?>;
      sequences['ledgerEntries'] = 0x7ffffffffffffffe;

      expect(
        () => BackupDocument.fromJson(json),
        throwsA(
          isA<BackupValidationException>().having(
            (error) => error.message,
            'message',
            contains('Urutan ID transaksi'),
          ),
        ),
      );
    });

    test('accepts an incoming sequence with the required ID headroom', () {
      final json = _backupDocument().toJson();
      final sequences = json['sequences']! as Map<String, Object?>;
      sequences['ledgerEntries'] =
          maxBackupRecordId - minimumRestoredIdHeadroom;

      expect(BackupDocument.fromJson(json).sequences.ledgerEntries, isPositive);
    });

    test('accepts a valid civil date without consulting the device clock', () {
      final json = _backupDocument().toJson();
      final data = json['data']! as Map<String, Object?>;
      final entries = data['ledgerEntries']! as List<Object?>;
      final entry = entries.single as Map<String, Object?>;
      entry['occurredDay'] = 20991231;

      expect(
        BackupDocument.fromJson(json).ledgerEntries.single.occurredDay,
        20991231,
      );
    });

    test('rejects an impossible civil date', () {
      final json = _backupDocument().toJson();
      final data = json['data']! as Map<String, Object?>;
      final entries = data['ledgerEntries']! as List<Object?>;
      final entry = entries.single as Map<String, Object?>;
      entry['occurredDay'] = 20260230;

      expect(
        () => BackupDocument.fromJson(json),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('v1 rejects unknown semantic data instead of dropping it', () {
      final json = _backupDocument().toJson();
      final data = json['data']! as Map<String, Object?>;
      data['budgets'] = <Map<String, Object?>>[];

      expect(
        () => BackupDocument.fromJson(json),
        throwsA(
          isA<BackupFormatException>().having(
            (error) => error.message,
            'message',
            contains('Struktur data'),
          ),
        ),
      );
    });

    test('rejects a newer payload version explicitly', () {
      final json = _backupDocument().toJson();
      json['backupVersion'] = currentBackupVersion + 1;

      expect(
        () => BackupDocument.fromJson(json),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });
}

EncryptedBackupCodec _testCodec({
  BackupCryptoParameters parameters = const BackupCryptoParameters(
    memoryKiB: 8,
    iterations: 1,
    parallelism: 1,
    keyLength: 32,
  ),
}) {
  var nextByte = 0;
  return EncryptedBackupCodec(
    parameters: parameters,
    randomBytes: (length) {
      final result = Uint8List(length);
      for (var index = 0; index < length; index++) {
        result[index] = nextByte++ & 0xff;
      }
      return result;
    },
  );
}

Uint8List _editEnvelope(
  Uint8List bytes,
  void Function(Map<String, Object?> envelope) edit,
) {
  final envelope = (jsonDecode(utf8.decode(bytes)) as Map)
      .cast<String, Object?>();
  edit(envelope);
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

Uint8List _editHeader(
  Uint8List bytes,
  void Function(Map<String, Object?> header) edit,
) => _editEnvelope(bytes, (envelope) {
  final headerBytes = base64Decode(envelope['header']! as String);
  final header = (jsonDecode(utf8.decode(headerBytes)) as Map)
      .cast<String, Object?>();
  edit(header);
  envelope['header'] = base64Encode(utf8.encode(jsonEncode(header)));
});

BackupDocument _backupDocument({int databaseSchemaVersion = 3}) {
  final createdAt = DateTime.utc(2026, 9, 5, 4, 30);
  return BackupDocument(
    databaseSchemaVersion: databaseSchemaVersion,
    createdAtUtc: DateTime.utc(2026, 9, 6, 7, 30),
    sequences: const BackupSequences(
      accounts: 1,
      categories: 4,
      ledgerEntries: 1,
    ),
    accounts: [
      BackupAccount(
        id: 1,
        name: 'Dompet Rahasia',
        normalizedName: 'dompet rahasia',
        type: AccountType.cash,
        isArchived: false,
        createdAtUtc: createdAt,
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
        createdAtUtc: createdAt,
        updatedAtUtc: createdAt,
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
        createdAtUtc: createdAt,
        updatedAtUtc: createdAt,
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
        createdAtUtc: createdAt,
        updatedAtUtc: createdAt,
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
        createdAtUtc: createdAt,
        updatedAtUtc: createdAt,
      ),
    ],
    ledgerEntries: [
      BackupLedgerEntry(
        id: 1,
        kind: EntryKind.income,
        accountId: 1,
        destinationAccountId: null,
        amount: 12345,
        categoryId: 2,
        note: 'PIN bank 9876',
        occurredDay: 20260905,
        createdAtUtc: createdAt,
      ),
    ],
  );
}
