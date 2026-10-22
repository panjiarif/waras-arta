import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/updates/android_update_installer.dart';
import 'package:waras_arta/domain/app_update.dart';

import '../support/update_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(updateInstallerChannelName);
  const installer = AndroidUpdateInstaller();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('passes expected hash, size and version to native verifier', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    expect(await installer.canInstall(), isTrue);
    expect(await installer.requestPermission(), isTrue);
    await installer.install('/cache/updates/update-123.apk', updateRelease());
    expect(calls.map((call) => call.method), [
      'canInstall',
      'requestInstallPermission',
      'installUpdate',
    ]);
    expect(calls.last.arguments, {
      'path': '/cache/updates/update-123.apk',
      'sha256': updateRelease().sha256,
      'size': 3,
      'version': '0.1.1',
    });
  });
  for (final code in [
    'invalid_apk',
    'not_newer',
    'permission_denied',
    'file_missing',
    'busy',
    'unexpected',
  ]) {
    test(
      'native $code is shown as a safe error without claiming success',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              throw PlatformException(code: code);
            });
        await expectLater(
          installer.install('/cache/updates/update-123.apk', updateRelease()),
          throwsA(isA<AppUpdateException>()),
        );
      },
    );
  }
}
