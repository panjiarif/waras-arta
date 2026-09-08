import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/backup/encrypted_backup_codec.dart';
import 'package:waras_arta/domain/backup.dart';
import 'package:waras_arta/domain/budget.dart';
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
      expect(decrypted.backupVersion, 4);
      expect(decrypted.databaseSchemaVersion, 6);
      expect(
        decrypted.accounts.single.balanceGroup,
        AccountBalanceGroup.savingsInvestment,
      );
      expect(decrypted.ledgerEntries.single.allocations, hasLength(2));
      expect(decrypted.budgets.single.categoryIds, [4]);
    });

    test('decodes strict payload v1 into the current allocation model', () {
      final legacyJson = _legacyV1Json();

      final decoded = BackupDocument.fromJson(legacyJson);

      expect(decoded.backupVersion, 1);
      expect(decoded.databaseSchemaVersion, 3);
      expect(decoded.ledgerEntries[0].allocations, hasLength(1));
      expect(decoded.ledgerEntries[0].allocations.single.position, 0);
      expect(decoded.ledgerEntries[0].allocations.single.categoryId, 2);
      expect(decoded.ledgerEntries[0].allocations.single.amount, 100);
      expect(decoded.ledgerEntries[1].allocations, isEmpty);
      expect(decoded.ledgerEntries[2].allocations, isEmpty);
      expect(decoded.budgets, isEmpty);
      expect(decoded.sequences.budgets, 0);
      expect(decoded.toJson(), legacyJson);
    });

    test('decodes payload v2 accounts as Saldo utama', () {
      final legacyJson = _legacyV2Json();

      final decoded = BackupDocument.fromJson(legacyJson);

      expect(decoded.backupVersion, 2);
      expect(decoded.databaseSchemaVersion, 4);
      expect(decoded.accounts.single.balanceGroup, AccountBalanceGroup.primary);
      expect(decoded.budgets, isEmpty);
      expect(decoded.toJson(), legacyJson);
    });

    test('keeps account shapes strict across payload versions', () {
      final missingGroup = _mutableJson(_backupDocument().toJson());
      final currentData = missingGroup['data']! as Map<String, Object?>;
      final currentAccounts = currentData['accounts']! as List<Object?>;
      (currentAccounts.single as Map<String, Object?>).remove('balanceGroup');

      final unknownGroup = _mutableJson(_backupDocument().toJson());
      final unknownData = unknownGroup['data']! as Map<String, Object?>;
      final unknownAccounts = unknownData['accounts']! as List<Object?>;
      (unknownAccounts.single as Map<String, Object?>)['balanceGroup'] =
          'unknown';

      final addedToLegacy = _legacyV2Json();
      final legacyData = addedToLegacy['data']! as Map<String, Object?>;
      final legacyAccounts = legacyData['accounts']! as List<Object?>;
      (legacyAccounts.single as Map<String, Object?>)['balanceGroup'] =
          AccountBalanceGroup.primary.name;

      for (final invalid in [missingGroup, unknownGroup, addedToLegacy]) {
        expect(
          () => BackupDocument.fromJson(invalid),
          throwsA(isA<BackupFormatException>()),
        );
      }
    });

    test('legacy payload cannot silently drop a non-primary group', () {
      final legacyLabeledDocument = _backupDocument(
        backupVersion: 2,
        databaseSchemaVersion: 4,
      );

      expect(
        legacyLabeledDocument.toJson,
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('routes payload parsers by an exact version and schema pair', () {
      final legacyWithWrongSchema = _mutableJson(_legacyV1Json());
      legacyWithWrongSchema['databaseSchemaVersion'] = 4;
      final currentWithWrongSchema = _mutableJson(_backupDocument().toJson());
      currentWithWrongSchema['databaseSchemaVersion'] = 3;

      expect(
        () => BackupDocument.fromJson(legacyWithWrongSchema),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => BackupDocument.fromJson(currentWithWrongSchema),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('uses an explicit restore compatibility matrix', () {
      final legacy = BackupDocument.fromJson(_legacyV1Json());
      final allocationLegacy = BackupDocument.fromJson(_legacyV2Json());
      final current = _backupDocument();

      expect(canRestoreBackupDocumentToSchema(legacy, 3), isTrue);
      expect(canRestoreBackupDocumentToSchema(legacy, 4), isTrue);
      expect(canRestoreBackupDocumentToSchema(legacy, 5), isTrue);
      expect(canRestoreBackupDocumentToSchema(legacy, 6), isTrue);
      expect(canRestoreBackupDocumentToSchema(allocationLegacy, 3), isFalse);
      expect(canRestoreBackupDocumentToSchema(allocationLegacy, 4), isTrue);
      expect(canRestoreBackupDocumentToSchema(allocationLegacy, 5), isTrue);
      expect(canRestoreBackupDocumentToSchema(allocationLegacy, 6), isTrue);
      expect(canRestoreBackupDocumentToSchema(current, 3), isFalse);
      expect(canRestoreBackupDocumentToSchema(current, 4), isFalse);
      expect(canRestoreBackupDocumentToSchema(current, 5), isFalse);
      expect(canRestoreBackupDocumentToSchema(current, 6), isTrue);
    });

    test('keeps v1 and v4 ledger shapes strict and separate', () {
      final legacy = _mutableJson(_legacyV1Json());
      final legacyData = legacy['data']! as Map<String, Object?>;
      final legacyEntries = legacyData['ledgerEntries']! as List<Object?>;
      (legacyEntries.first as Map<String, Object?>)['allocations'] =
          <Object?>[];

      final current = _mutableJson(_backupDocument().toJson());
      final currentData = current['data']! as Map<String, Object?>;
      final currentEntries = currentData['ledgerEntries']! as List<Object?>;
      (currentEntries.first as Map<String, Object?>)['categoryId'] = 2;

      expect(
        () => BackupDocument.fromJson(legacy),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => BackupDocument.fromJson(current),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('validates v3 allocation count, positions, uniqueness, and sum', () {
      Map<String, Object?> firstEntry(Map<String, Object?> document) {
        final data = document['data']! as Map<String, Object?>;
        final entries = data['ledgerEntries']! as List<Object?>;
        return entries.first as Map<String, Object?>;
      }

      final empty = _mutableJson(_backupDocument().toJson());
      firstEntry(empty)['allocations'] = <Object?>[];

      final positionGap = _mutableJson(_backupDocument().toJson());
      final positionAllocations =
          firstEntry(positionGap)['allocations']! as List<Object?>;
      (positionAllocations[1] as Map<String, Object?>)['position'] = 2;

      final duplicateCategory = _mutableJson(_backupDocument().toJson());
      final duplicateAllocations =
          firstEntry(duplicateCategory)['allocations']! as List<Object?>;
      (duplicateAllocations[1] as Map<String, Object?>)['categoryId'] = 2;

      final mismatchedSum = _mutableJson(_backupDocument().toJson());
      final mismatchedAllocations =
          firstEntry(mismatchedSum)['allocations']! as List<Object?>;
      (mismatchedAllocations[1] as Map<String, Object?>)['amount'] = 2344;

      final tooMany = _mutableJson(_backupDocument().toJson());
      firstEntry(tooMany)['allocations'] = List<Object?>.generate(
        maxBackupLedgerAllocationsPerEntry + 1,
        (index) => <String, Object?>{
          'position': index,
          'categoryId': 2,
          'amount': 1,
        },
      );

      for (final invalid in [
        empty,
        positionGap,
        duplicateCategory,
        mismatchedSum,
      ]) {
        expect(
          () => BackupDocument.fromJson(invalid),
          throwsA(isA<BackupValidationException>()),
        );
      }
      expect(
        () => BackupDocument.fromJson(tooMany),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('payload estimator includes every allocation', () {
      final single = estimateBackupPayloadUpperBoundBytes(
        _backupDocument(split: false),
      );
      final split = estimateBackupPayloadUpperBoundBytes(_backupDocument());

      expect(split - single, 128);
    });

    test('payload v4 rejects overlapping budgets for one category', () {
      final json = _mutableJson(_backupDocument().toJson());
      final sequences = json['sequences']! as Map<String, Object?>;
      sequences['budgets'] = 2;
      final data = json['data']! as Map<String, Object?>;
      final budgets = data['budgets']! as List<Object?>;
      final overlapping =
          Map<String, Object?>.from(budgets.single! as Map<String, Object?>)
            ..['id'] = 2
            ..['periodKind'] = BudgetPeriodKind.custom.name
            ..['startDay'] = 20260915
            ..['endDay'] = 20261015
            ..['name'] = 'Makan lintas bulan'
            ..['normalizedName'] = 'makan lintas bulan';
      budgets.add(overlapping);

      expect(
        () => BackupDocument.fromJson(json),
        throwsA(
          isA<BackupValidationException>().having(
            (error) => error.message,
            'message',
            contains('beririsan'),
          ),
        ),
      );
    });

    test('payload v4 validates period shape and sorted category IDs', () {
      Map<String, Object?> firstBudget(Map<String, Object?> document) {
        final data = document['data']! as Map<String, Object?>;
        final budgets = data['budgets']! as List<Object?>;
        return budgets.single! as Map<String, Object?>;
      }

      final nonCanonicalMonth = _mutableJson(_backupDocument().toJson());
      firstBudget(nonCanonicalMonth)['startDay'] = 20260902;

      final duplicateCategory = _mutableJson(_backupDocument().toJson());
      firstBudget(duplicateCategory)['categoryIds'] = <Object?>[4, 4];

      final incomeCategory = _mutableJson(_backupDocument().toJson());
      firstBudget(incomeCategory)['categoryIds'] = <Object?>[2];

      for (final invalid in [
        nonCanonicalMonth,
        duplicateCategory,
        incomeCategory,
      ]) {
        expect(
          () => BackupDocument.fromJson(invalid),
          throwsA(isA<BackupValidationException>()),
        );
      }
    });

    test('rejects a document above the total allocation record limit', () {
      final oversized = BackupDocument(
        databaseSchemaVersion: 6,
        createdAtUtc: DateTime.utc(2026, 9, 6),
        sequences: const BackupSequences(
          accounts: 0,
          categories: 0,
          ledgerEntries: 1,
        ),
        accounts: const [],
        categories: const [],
        ledgerEntries: [
          BackupLedgerEntry(
            id: 1,
            kind: EntryKind.income,
            accountId: 1,
            destinationAccountId: null,
            amount: 1,
            allocations: List<BackupLedgerAllocation>.filled(
              maxBackupLedgerAllocationRecords + 1,
              const BackupLedgerAllocation(
                position: 0,
                categoryId: 1,
                amount: 1,
              ),
              growable: false,
            ),
            note: '',
            occurredDay: 20260906,
            createdAtUtc: DateTime.utc(2026, 9, 6),
          ),
        ],
      );

      expect(
        () => validateBackupDocument(oversized),
        throwsA(
          isA<BackupValidationException>().having(
            (error) => error.message,
            'message',
            contains('Jumlah data'),
          ),
        ),
      );
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
      entry['allocations'] = <Object?>[];

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
      final json = _legacyV1Json();
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

Map<String, Object?> _mutableJson(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();

Map<String, Object?> _legacyV1Json() => <String, Object?>{
  'format': warasArtaBackupFormat,
  'backupVersion': 1,
  'databaseSchemaVersion': 3,
  'createdAtUtc': '2026-09-06T07:30:00.000Z',
  'sequences': <String, Object?>{
    'accounts': 2,
    'categories': 4,
    'ledgerEntries': 3,
  },
  'data': <String, Object?>{
    'accounts': <Object?>[
      <String, Object?>{
        'id': 1,
        'name': 'Dompet Lama',
        'normalizedName': 'dompet lama',
        'type': 'cash',
        'isArchived': false,
        'createdAtUtc': '2026-09-05T04:30:00.000Z',
      },
      <String, Object?>{
        'id': 2,
        'name': 'Bank Lama',
        'normalizedName': 'bank lama',
        'type': 'bank',
        'isArchived': false,
        'createdAtUtc': '2026-09-05T04:30:00.000Z',
      },
    ],
    'categories': <Object?>[
      <String, Object?>{
        'id': 1,
        'parentId': null,
        'kind': 'income',
        'name': 'Pemasukan',
        'normalizedName': 'pemasukan',
        'iconKey': 'work',
        'isArchived': false,
        'sortOrder': 0,
        'systemKey': null,
        'createdAtUtc': '2026-09-05T04:30:00.000Z',
        'updatedAtUtc': '2026-09-05T04:30:00.000Z',
      },
      <String, Object?>{
        'id': 2,
        'parentId': 1,
        'kind': 'income',
        'name': 'Umum',
        'normalizedName': 'umum',
        'iconKey': 'work',
        'isArchived': false,
        'sortOrder': 0,
        'systemKey': null,
        'createdAtUtc': '2026-09-05T04:30:00.000Z',
        'updatedAtUtc': '2026-09-05T04:30:00.000Z',
      },
      <String, Object?>{
        'id': 3,
        'parentId': null,
        'kind': 'expense',
        'name': 'Pengeluaran',
        'normalizedName': 'pengeluaran',
        'iconKey': 'restaurant',
        'isArchived': false,
        'sortOrder': 0,
        'systemKey': null,
        'createdAtUtc': '2026-09-05T04:30:00.000Z',
        'updatedAtUtc': '2026-09-05T04:30:00.000Z',
      },
      <String, Object?>{
        'id': 4,
        'parentId': 3,
        'kind': 'expense',
        'name': 'Umum',
        'normalizedName': 'umum',
        'iconKey': 'restaurant',
        'isArchived': false,
        'sortOrder': 0,
        'systemKey': null,
        'createdAtUtc': '2026-09-05T04:30:00.000Z',
        'updatedAtUtc': '2026-09-05T04:30:00.000Z',
      },
    ],
    'ledgerEntries': <Object?>[
      <String, Object?>{
        'id': 1,
        'kind': 'income',
        'accountId': 1,
        'destinationAccountId': null,
        'amount': 100,
        'categoryId': 2,
        'note': 'Pemasukan lama',
        'occurredDay': 20260905,
        'createdAtUtc': '2026-09-05T04:30:00.000Z',
      },
      <String, Object?>{
        'id': 2,
        'kind': 'transfer',
        'accountId': 1,
        'destinationAccountId': 2,
        'amount': 10,
        'categoryId': null,
        'note': 'Transfer lama',
        'occurredDay': 20260905,
        'createdAtUtc': '2026-09-05T04:30:00.000Z',
      },
      <String, Object?>{
        'id': 3,
        'kind': 'adjustment',
        'accountId': 2,
        'destinationAccountId': null,
        'amount': 5,
        'categoryId': null,
        'note': 'Koreksi lama',
        'occurredDay': 20260905,
        'createdAtUtc': '2026-09-05T04:30:00.000Z',
      },
    ],
  },
};

Map<String, Object?> _legacyV2Json() {
  final json = _mutableJson(_backupDocument().toJson());
  json['backupVersion'] = 2;
  json['databaseSchemaVersion'] = 4;
  final data = json['data']! as Map<String, Object?>;
  data.remove('budgets');
  final sequences = json['sequences']! as Map<String, Object?>;
  sequences.remove('budgets');
  final accounts = data['accounts']! as List<Object?>;
  for (final value in accounts) {
    (value as Map<String, Object?>).remove('balanceGroup');
  }
  return json;
}

BackupDocument _backupDocument({
  int backupVersion = currentBackupVersion,
  int databaseSchemaVersion = 6,
  bool split = true,
}) {
  final createdAt = DateTime.utc(2026, 9, 5, 4, 30);
  return BackupDocument(
    backupVersion: backupVersion,
    databaseSchemaVersion: databaseSchemaVersion,
    createdAtUtc: DateTime.utc(2026, 9, 6, 7, 30),
    sequences: const BackupSequences(
      accounts: 1,
      categories: 5,
      ledgerEntries: 1,
      budgets: 1,
    ),
    accounts: [
      BackupAccount(
        id: 1,
        name: 'Dompet Rahasia',
        normalizedName: 'dompet rahasia',
        type: AccountType.cash,
        balanceGroup: AccountBalanceGroup.savingsInvestment,
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
      BackupCategory(
        id: 5,
        parentId: 1,
        kind: CategoryKind.income,
        name: 'Bonus',
        normalizedName: 'bonus',
        iconKey: 'redeem',
        isArchived: false,
        sortOrder: 1,
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
        allocations: split
            ? const [
                BackupLedgerAllocation(
                  position: 0,
                  categoryId: 2,
                  amount: 10000,
                ),
                BackupLedgerAllocation(
                  position: 1,
                  categoryId: 5,
                  amount: 2345,
                ),
              ]
            : const [
                BackupLedgerAllocation(
                  position: 0,
                  categoryId: 2,
                  amount: 12345,
                ),
              ],
        note: 'PIN bank 9876',
        occurredDay: 20260905,
        createdAtUtc: createdAt,
      ),
    ],
    budgets: [
      BackupBudget(
        id: 1,
        periodKind: BudgetPeriodKind.monthly,
        startDay: 20260901,
        endDay: 20260930,
        name: 'Makan September',
        normalizedName: 'makan september',
        limitAmount: 500000,
        categoryIds: const [4],
        createdAtUtc: createdAt,
        updatedAtUtc: createdAt,
      ),
    ],
  );
}
