import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/updates/android_update_installer.dart';
import '../../../data/updates/github_update_service.dart';
import '../../../domain/app_update.dart';
import 'app_version_info_provider.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final service = GitHubUpdateService();
  ref.onDispose(service.dispose);
  return service;
});
final updateInstallerProvider = Provider<UpdateInstaller>(
  (ref) => const AndroidUpdateInstaller(),
);

enum AppUpdatePhase {
  idle,
  checking,
  current,
  available,
  downloading,
  ready,
  installing,
}

class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.release,
    this.progress,
    this.path,
    this.error,
    this.message,
  });
  final AppUpdatePhase phase;
  final UpdateRelease? release;
  final UpdateProgress? progress;
  final String? path;
  final String? error;
  final String? message;
  bool get isBusy => const {
    AppUpdatePhase.checking,
    AppUpdatePhase.downloading,
    AppUpdatePhase.installing,
  }.contains(phase);
}

final appUpdateProvider = NotifierProvider<AppUpdateViewModel, AppUpdateState>(
  AppUpdateViewModel.new,
);

class AppUpdateViewModel extends Notifier<AppUpdateState> {
  @override
  AppUpdateState build() => const AppUpdateState();

  Future<void> check() async {
    if (state.isBusy) return;
    state = const AppUpdateState(phase: AppUpdatePhase.checking);
    try {
      final info = await ref.read(appVersionInfoProvider.future);
      final release = await ref
          .read(appUpdateServiceProvider)
          .check(info.version);
      if (!ref.mounted) return;
      state = AppUpdateState(
        phase: release == null
            ? AppUpdatePhase.current
            : AppUpdatePhase.available,
        release: release,
      );
    } catch (error) {
      if (ref.mounted) {
        state = AppUpdateState(
          error: _message(error, 'Pembaruan belum dapat diperiksa. Coba lagi.'),
        );
      }
    }
  }

  Future<void> download() async {
    final release = state.release;
    if (state.isBusy || release == null) return;
    state = AppUpdateState(
      phase: AppUpdatePhase.downloading,
      release: release,
      progress: UpdateProgress(0, release.size),
    );
    try {
      final path = await ref.read(appUpdateServiceProvider).download(release, (
        progress,
      ) {
        if (ref.mounted && state.phase == AppUpdatePhase.downloading) {
          state = AppUpdateState(
            phase: AppUpdatePhase.downloading,
            release: release,
            progress: progress,
          );
        }
      });
      if (ref.mounted) {
        state = AppUpdateState(
          phase: AppUpdatePhase.ready,
          release: release,
          path: path,
        );
      }
    } catch (error) {
      if (ref.mounted) {
        state = AppUpdateState(
          phase: AppUpdatePhase.available,
          release: release,
          error: _message(error, 'Unduhan gagal. Coba lagi.'),
        );
      }
    }
  }

  void cancelDownload() {
    if (state.phase == AppUpdatePhase.downloading) {
      ref.read(appUpdateServiceProvider).cancelDownload();
    }
  }

  Future<void> install() async {
    final previous = state;
    final release = previous.release;
    final path = previous.path;
    if (previous.isBusy || release == null || path == null) return;
    state = AppUpdateState(
      phase: AppUpdatePhase.installing,
      release: release,
      path: path,
    );
    try {
      final installer = ref.read(updateInstallerProvider);
      if (!await installer.canInstall() &&
          !await installer.requestPermission()) {
        throw const AppUpdateException(
          'Izin pemasangan belum diberikan. Unduhan tetap tersimpan; kamu dapat mencoba lagi.',
        );
      }
      await installer.install(path, release);
      if (ref.mounted) {
        state = AppUpdateState(
          phase: AppUpdatePhase.ready,
          release: release,
          path: path,
          message: 'Pemasang Android dibuka. Pembaruan belum terpasang sampai proses di Android selesai. Jika dibatalkan, kamu dapat mencoba lagi.',
        );
      }
    } catch (error) {
      if (ref.mounted) {
        state = AppUpdateState(
          phase: AppUpdatePhase.ready,
          release: release,
          path: path,
          error: _message(error, 'Pemasang belum dapat dibuka. Coba lagi.'),
        );
      }
    }
  }

  String _message(Object error, String fallback) =>
      error is AppUpdateException ? error.message : fallback;
}
