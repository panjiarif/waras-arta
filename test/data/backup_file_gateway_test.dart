import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/backup/backup_file_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('waras_arta.test/backup_files');
  late Future<Object?> Function(MethodCall call) handler;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) => handler(call));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('save sends encrypted bytes and the native size limit', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    late MethodCall received;
    handler = (call) async {
      received = call;
      return true;
    };

    final saved = await const SafBackupFileGateway(channel: channel)
        .save(suggestedName: 'waras-arta-backup.warasarta', bytes: bytes);

    expect(saved, isTrue);
    expect(received.method, 'saveBackup');
    final arguments = received.arguments! as Map<Object?, Object?>;
    expect(arguments['suggestedName'], 'waras-arta-backup.warasarta');
    expect(arguments['bytes'], orderedEquals(bytes));
    expect(arguments['maxBytes'], maxBackupFileBytes);
  });

  test('save cancellation remains a non-error false result', () async {
    handler = (_) async => false;

    final saved = await const SafBackupFileGateway(channel: channel).save(
      suggestedName: 'waras-arta-backup.warasarta',
      bytes: Uint8List.fromList([1]),
    );

    expect(saved, isFalse);
  });

  test('save exposes a safe message when native verification fails', () async {
    handler = (_) async => throw PlatformException(
      code: 'write_verification_failed',
      message: 'provider-internal-path',
    );

    await expectLater(
      const SafBackupFileGateway(channel: channel).save(
        suggestedName: 'waras-arta-backup.warasarta',
        bytes: Uint8List.fromList([1]),
      ),
      throwsA(
        isA<BackupFileException>()
            .having(
              (error) => error.message,
              'message',
              contains('tidak dapat diverifikasi'),
            )
            .having(
              (error) => error.message,
              'safe message',
              isNot(contains('provider-internal-path')),
            ),
      ),
    );
  });

  test('pick decodes bytes returned by the direct SAF reader', () async {
    final bytes = Uint8List.fromList([9, 8, 7]);
    late MethodCall received;
    handler = (call) async {
      received = call;
      return <String, Object?>{'name': 'backup-uji.warasarta', 'bytes': bytes};
    };

    final selected = await const SafBackupFileGateway(channel: channel).pick();

    expect(received.method, 'pickBackup');
    expect(received.arguments, containsPair('maxBytes', maxBackupFileBytes));
    expect(selected?.name, 'backup-uji.warasarta');
    expect(selected?.bytes, orderedEquals(bytes));
  });

  test('pick cancellation remains null', () async {
    handler = (_) async => null;

    final selected = await const SafBackupFileGateway(channel: channel).pick();

    expect(selected, isNull);
  });

  test('pick rejects malformed native results', () async {
    handler = (_) async => <String, Object?>{
      'name': 'backup-uji.warasarta',
      'bytes': 'not-bytes',
    };

    await expectLater(
      const SafBackupFileGateway(channel: channel).pick(),
      throwsA(isA<BackupFileException>()),
    );
  });
}
