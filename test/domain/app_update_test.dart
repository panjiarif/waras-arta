import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/domain/app_update.dart';

import '../support/update_fixtures.dart';

void main() {
  test(
    'includes alpha releases, ignores drafts and sorts by semantic version',
    () {
      final release = selectUpdateRelease([
        releaseJson(tag: 'v0.1.9'),
        releaseJson(tag: 'v0.1.10'),
        releaseJson(tag: 'v9.0.0', draft: true),
        releaseJson(tag: 'latest'),
      ], '0.1.0')!;
      expect(release.tag, 'v0.1.10');
      expect(release.prerelease, isTrue);
    },
  );
  test('compares prerelease identifiers numerically and prefers stable', () {
    expect(
      selectUpdateRelease([
        releaseJson(tag: 'v0.2.0-alpha.10'),
        releaseJson(tag: 'v0.2.0-alpha.2'),
      ], '0.1.0')!.tag,
      'v0.2.0-alpha.10',
    );
    expect(
      selectUpdateRelease([
        releaseJson(tag: 'v0.2.0-alpha.10'),
        releaseJson(tag: 'v0.2.0', prerelease: false),
      ], '0.1.0')!.tag,
      'v0.2.0',
    );
  });
  test('does not offer same, older, noncanonical or build-only versions', () {
    for (final tag in [
      'v0.1.0',
      'v0.0.9',
      'v0.1.0+2',
      'v00.2.0',
      'unreleased',
    ]) {
      expect(selectUpdateRelease([releaseJson(tag: tag)], '0.1.0'), isNull);
    }
    expect(selectUpdateRelease([], '0.1.0'), isNull);
  });
  test('fails closed for incomplete newest release instead of hiding it', () {
    final latest = releaseJson(tag: 'v0.2.0')..['assets'] = [];
    expect(
      () => selectUpdateRelease([releaseJson(), latest], '0.1.0'),
      throwsA(isA<AppUpdateException>()),
    );
  });
  test('requires exactly one named universal APK', () {
    final json = releaseJson();
    final assets = json['assets']! as List<Object?>;
    assets.add(assets.single);
    expect(
      () => selectUpdateRelease([json], '0.1.0'),
      throwsA(isA<AppUpdateException>()),
    );
    assets.removeLast();
    (assets.single as Map)['name'] = 'arm64-v8a.apk';
    expect(
      () => selectUpdateRelease([json], '0.1.0'),
      throwsA(isA<AppUpdateException>()),
    );
  });
  test('rejects missing digest, unsafe URL, size, state and ID', () {
    final invalid = <String, Object?>{
      'digest': null,
      'size': maxUpdateApkBytes + 1,
      'state': 'new',
      'id': 0,
    };
    for (final entry in invalid.entries) {
      final json = releaseJson();
      ((json['assets']! as List).single as Map)[entry.key] = entry.value;
      expect(
        () => selectUpdateRelease([json], '0.1.0'),
        throwsA(isA<AppUpdateException>()),
        reason: entry.key,
      );
    }
    for (final url in [
      'http://github.com/panjiarif/waras-arta/releases/download/v0.1.1/waras-arta-v0.1.1-android.apk',
      'https://github.com/other/repo/releases/download/v0.1.1/waras-arta-v0.1.1-android.apk',
      'https://github.com/panjiarif/waras-arta/releases/download/v0.1.1/wrong.apk',
      'https://github.com.evil.test/file.apk',
    ]) {
      final json = releaseJson();
      ((json['assets']! as List).single as Map)['browser_download_url'] = url;
      expect(
        () => selectUpdateRelease([json], '0.1.0'),
        throwsA(isA<AppUpdateException>()),
      );
    }
  });
  test(
    'redirect allowlist rejects insecure schemes, credentials and ports',
    () {
      for (final url in [
        'http://github.com/a',
        'https://user:password@github.com/a',
        'https://github.com:444/a',
        'https://evil.test/a',
        'file:///tmp/a',
        'https://github.com/a#fragment',
      ]) {
        expect(isTrustedUpdateUri(Uri.parse(url)), isFalse, reason: url);
      }
      expect(
        isTrustedUpdateUri(
          Uri.parse(
            'https://release-assets.githubusercontent.com/a?token=signed-download',
          ),
        ),
        isTrue,
      );
    },
  );
  test('bounds release notes and never executes their markup', () {
    final json = releaseJson()..['body'] = 'a' * 15000;
    expect(selectUpdateRelease([json], '0.1.0')!.notes.length, 12000);
  });
}
