import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/domain/app_update.dart';
import 'package:waras_arta/features/about/view_models/app_update_view_model.dart';
import 'package:waras_arta/features/about/view_models/app_version_info_provider.dart';
import 'package:waras_arta/features/about/views/about_screen.dart';

import '../../support/update_fixtures.dart';

void main() {
  late FakeUpdates service;
  late FakeInstaller installer;
  late ProviderContainer container;
  setUp(() {
    service = FakeUpdates();
    installer = FakeInstaller();
    container = ProviderContainer(
      overrides: [
        appUpdateServiceProvider.overrideWithValue(service),
        updateInstallerProvider.overrideWithValue(installer),
        appVersionInfoProvider.overrideWith(
          (ref) async =>
              const AppVersionInfo(version: '0.1.0', buildNumber: '1'),
        ),
      ],
    );
  });
  tearDown(() {
    container.dispose();
  });

  test('no automatic network check when updater is first read', () {
    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.idle);
    expect(service.checks, 0);
  });
  test(
    'check, progress, verified download and installer handoff are separate',
    () async {
      final vm = container.read(appUpdateProvider.notifier);
      await vm.check();
      expect(container.read(appUpdateProvider).phase, AppUpdatePhase.available);
      expect(installer.calls, 0);
      await vm.download();
      expect(container.read(appUpdateProvider).phase, AppUpdatePhase.ready);
      expect(installer.calls, 0);
      await vm.install();
      expect(installer.calls, 1);
      expect(
        container.read(appUpdateProvider).message,
        contains('belum terpasang'),
      );
    },
  );
  test(
    'latest, failed check, and retry work without touching finance providers',
    () async {
      final vm = container.read(appUpdateProvider.notifier);
      service.latest = null;
      await vm.check();
      expect(container.read(appUpdateProvider).phase, AppUpdatePhase.current);
      service.checkError = true;
      await vm.check();
      expect(container.read(appUpdateProvider).error, 'Offline uji');
      service.checkError = false;
      service.latest = updateRelease();
      await vm.check();
      expect(container.read(appUpdateProvider).release, isNotNull);
    },
  );
  test('download failure never exposes an installable path', () async {
    final vm = container.read(appUpdateProvider.notifier);
    await vm.check();
    service.downloadError = true;
    await vm.download();
    expect(container.read(appUpdateProvider).path, isNull);
    await vm.install();
    expect(installer.calls, 0);
    expect(container.read(appUpdateProvider).error, 'Unduhan uji gagal');
  });
  test(
    'permission refusal keeps verified APK and allows install retry',
    () async {
      final vm = container.read(appUpdateProvider.notifier);
      await vm.check();
      await vm.download();
      installer.permission = false;
      await vm.install();
      expect(installer.requests, 1);
      expect(installer.calls, 0);
      expect(container.read(appUpdateProvider).phase, AppUpdatePhase.ready);
      expect(container.read(appUpdateProvider).path, isNotNull);
      installer.permission = true;
      await vm.install();
      expect(installer.calls, 1);
      expect(service.downloads, 1);
    },
  );
  test('permission grant returns to app before opening installer', () async {
    final vm = container.read(appUpdateProvider.notifier);
    await vm.check();
    await vm.download();
    installer.permission = false;
    installer.grant = true;
    await vm.install();
    expect(installer.requests, 1);
    expect(installer.calls, 1);
  });
  test('duplicate taps cannot start parallel requests', () async {
    final vm = container.read(appUpdateProvider.notifier);
    service.checkPending = Completer<UpdateRelease?>();
    final checking = vm.check();
    await vm.check();
    await Future<void>.delayed(Duration.zero);
    expect(service.checks, 1);
    service.checkPending!.complete(updateRelease());
    await checking;
  });
  test('cancel keeps available release and cannot invoke installer', () async {
    final vm = container.read(appUpdateProvider.notifier);
    await vm.check();
    service.downloadPending = Completer<String>();
    final downloading = vm.download();
    vm.cancelDownload();
    await downloading;
    expect(service.canceled, isTrue);
    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.available);
    expect(container.read(appUpdateProvider).path, isNull);
    expect(installer.calls, 0);
  });

  Future<void> pumpAbout(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AboutScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('about shows manual update controls and no background request', (
    tester,
  ) async {
    await pumpAbout(tester);
    expect(find.byKey(const Key('check-app-update')), findsOneWidget);
    expect(service.checks, 0);
    expect(find.byKey(const Key('download-update')), findsNothing);
    await tapVisible(tester, 'check-app-update');
    expect(find.text('Tersedia v0.1.1 · Versi pengujian'), findsOneWidget);
    expect(find.byKey(const Key('install-update')), findsNothing);
    await tapVisible(tester, 'download-update');
    expect(find.byKey(const Key('install-update')), findsOneWidget);
    expect(installer.calls, 0);
    await tapVisible(tester, 'install-update');
    expect(find.text('Pasang pembaruan?'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(installer.calls, 0);
    await tapVisible(tester, 'install-update');
    await tester.tap(find.byKey(const Key('confirm-install-update')));
    await tester.pumpAndSettle();
    expect(installer.calls, 1);
    expect(find.textContaining('Pemasang Android dibuka.'), findsOneWidget);
  });
  testWidgets('offline check shows retry, not an automatic download', (
    tester,
  ) async {
    service.checkError = true;
    await pumpAbout(tester);
    await tapVisible(tester, 'check-app-update');
    expect(find.text('Offline uji'), findsOneWidget);
    expect(service.downloads, 0);
    service.checkError = false;
    await tapVisible(tester, 'check-app-update');
    expect(find.byKey(const Key('download-update')), findsOneWidget);
    expect(find.text('Offline uji'), findsNothing);
  });
  testWidgets('download percentage and cancel button stay accessible', (
    tester,
  ) async {
    await pumpAbout(tester);
    await tapVisible(tester, 'check-app-update');
    service.downloadPending = Completer<String>();
    final downloading = container.read(appUpdateProvider.notifier).download();
    service.report!(const UpdateProgress(1, 3));
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('update-download-progress')),
          )
          .value,
      closeTo(1 / 3, .001),
    );
    await tester.ensureVisible(find.byKey(const Key('cancel-update-download')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cancel-update-download')));
    await tester.pumpAndSettle();
    await downloading;
    expect(service.canceled, isTrue);
    expect(find.byKey(const Key('install-update')), findsNothing);
  });
  testWidgets(
    'about and update states fit narrow screens with 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpAbout(tester);
      await tapVisible(tester, 'check-app-update');
      await tapVisible(tester, 'download-update');
      await tapVisible(tester, 'install-update');
      expect(tester.takeException(), isNull);
    },
  );
}

class FakeUpdates implements AppUpdateService {
  UpdateRelease? latest = updateRelease();
  bool checkError = false, downloadError = false, canceled = false;
  int checks = 0, downloads = 0;
  Completer<UpdateRelease?>? checkPending;
  Completer<String>? downloadPending;
  void Function(UpdateProgress)? report;
  @override
  Future<UpdateRelease?> check(String installedVersion) async {
    checks++;
    if (checkError) throw const AppUpdateException('Offline uji');
    return checkPending?.future ?? latest;
  }

  @override
  Future<String> download(
    UpdateRelease release,
    void Function(UpdateProgress) onProgress,
  ) async {
    downloads++;
    report = onProgress;
    if (downloadError) throw const AppUpdateException('Unduhan uji gagal');
    onProgress(UpdateProgress(0, release.size));
    return downloadPending?.future ?? '/private/cache/updates/update-123.apk';
  }

  @override
  void cancelDownload() {
    canceled = true;
    downloadPending?.completeError(
      const AppUpdateException('Unduhan dibatalkan.'),
    );
  }

  @override
  void dispose() {}
}

class FakeInstaller implements UpdateInstaller {
  bool permission = true, grant = false;
  int calls = 0, requests = 0;
  @override
  Future<bool> canInstall() async => permission;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return grant;
  }

  @override
  Future<void> install(String path, UpdateRelease release) async {
    calls++;
  }
}
