import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/updates/github_update_service.dart';
import 'package:waras_arta/domain/app_update.dart';

import '../support/update_fixtures.dart';

void main() {
  late Directory directory;
  late FakeTransport transport;
  late GitHubUpdateService service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'waras-arta-update-test-',
    );
    transport = FakeTransport();
    service = GitHubUpdateService(
      transportFactory: () => transport,
      cacheDirectory: () async => directory,
    );
  });
  tearDown(() async {
    service.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'checks public releases including prereleases without authentication',
    () async {
      transport.responses.add(jsonResponse([releaseJson()]));
      expect((await service.check('0.1.0'))!.tag, 'v0.1.1');
      expect(transport.uris.single.host, 'api.github.com');
      expect(
        transport.uris.single.path,
        '/repos/panjiarif/waras-arta/releases',
      );
      expect(transport.uris.single.queryParameters['page'], '1');
      expect(transport.closed, isTrue);
    },
  );
  test(
    'reads further pages instead of relying on latest stable endpoint',
    () async {
      transport.responses.add(
        jsonResponse(List.generate(100, (_) => releaseJson(tag: 'old'))),
      );
      transport.responses.add(jsonResponse([releaseJson()]));
      expect((await service.check('0.1.0'))!.tag, 'v0.1.1');
      expect(transport.uris.last.queryParameters['page'], '2');
    },
  );
  for (final status in [403, 429, 404, 500]) {
    test('reports HTTP $status and does not write an APK', () async {
      transport.responses.add(
        UpdateHttpResponse(status: status, body: const Stream.empty()),
      );
      await expectLater(
        service.check('0.1.0'),
        throwsA(isA<AppUpdateException>()),
      );
      expect(await directory.list().toList(), isEmpty);
    });
  }
  test('rejects malformed and oversized metadata', () async {
    for (final response in [
      UpdateHttpResponse(
        status: 200,
        body: Stream.value(utf8.encode('{invalid')),
      ),
      UpdateHttpResponse(
        status: 200,
        length: 3 * 1024 * 1024,
        body: const Stream.empty(),
      ),
    ]) {
      transport.responses.add(response);
      await expectLater(
        service.check('0.1.0'),
        throwsA(isA<AppUpdateException>()),
      );
    }
  });
  test(
    'streams verified APK to dedicated private cache and reports progress',
    () async {
      transport.responses.add(
        UpdateHttpResponse(
          status: 200,
          length: 3,
          body: Stream.fromIterable([
            [1],
            [2, 3],
          ]),
        ),
      );
      final progress = <UpdateProgress>[];
      final path = await service.download(updateRelease(), progress.add);
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      expect(path, endsWith('updates/update-123.apk'));
      expect(await File('$path.part').exists(), isFalse);
      expect(progress.first.received, 0);
      expect(progress.last.fraction, 1);
      expect(transport.closed, isTrue);
    },
  );
  for (final bytes in [
    [1, 2],
    [1, 2, 3, 4],
    [3, 2, 1],
  ]) {
    test(
      'rejects truncated, oversized or corrupt bytes $bytes and removes partial file',
      () async {
        transport.responses.add(
          UpdateHttpResponse(status: 200, body: Stream.value(bytes)),
        );
        await expectLater(
          service.download(updateRelease(), (_) {}),
          throwsA(isA<AppUpdateException>()),
        );
        expect(
          await Directory('${directory.path}/updates').list().toList(),
          isEmpty,
        );
        expect(transport.closed, isTrue);
      },
    );
  }
  test('rejects misleading Content-Length before reading body', () async {
    transport.responses.add(
      UpdateHttpResponse(
        status: 200,
        length: 999,
        body: Stream.value([1, 2, 3]),
      ),
    );
    await expectLater(
      service.download(updateRelease(), (_) {}),
      throwsA(isA<AppUpdateException>()),
    );
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
  });
  test('cancel prevents promotion of partial data and permits retry', () async {
    transport.responses.add(
      UpdateHttpResponse(
        status: 200,
        body: Stream.fromIterable([
          [1],
          [2, 3],
        ]),
      ),
    );
    await expectLater(
      service.download(updateRelease(), (progress) {
        if (progress.received > 0) service.cancelDownload();
      }),
      throwsA(isA<AppUpdateException>()),
    );
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
    transport.responses.add(
      UpdateHttpResponse(status: 200, body: Stream.value([1, 2, 3])),
    );
    expect(
      await File(await service.download(updateRelease(), (_) {})).exists(),
      isTrue,
    );
  });
  test('connection failure cannot leave an installable partial APK', () async {
    transport.responses.add(
      UpdateHttpResponse(
        status: 200,
        body: Stream.error(const SocketException('offline')),
      ),
    );
    await expectLater(
      service.download(updateRelease(), (_) {}),
      throwsA(isA<AppUpdateException>()),
    );
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
  });
  test('rejects overlapping operations', () async {
    final stream = StreamController<List<int>>();
    transport.responses.add(
      UpdateHttpResponse(status: 200, body: stream.stream),
    );
    final pending = service.check('0.1.0');
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      service.check('0.1.0'),
      throwsA(isA<AppUpdateException>()),
    );
    stream.add(utf8.encode('[]'));
    await stream.close();
    expect(await pending, isNull);
  });
}

UpdateHttpResponse jsonResponse(Object json) => UpdateHttpResponse(
  status: 200,
  body: Stream.value(utf8.encode(jsonEncode(json))),
);

class FakeTransport implements UpdateHttpTransport {
  final responses = Queue<UpdateHttpResponse>();
  final uris = <Uri>[];
  bool closed = false;
  @override
  Future<UpdateHttpResponse> get(Uri uri) async {
    uris.add(uri);
    return responses.removeFirst();
  }

  @override
  void close() {
    closed = true;
  }
}
