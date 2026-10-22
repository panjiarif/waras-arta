import 'package:flutter/services.dart';

import '../../domain/app_update.dart';

const updateInstallerChannelName = 'io.github.panjiarif.waras_arta/app_updates';

class AndroidUpdateInstaller implements UpdateInstaller {
  const AndroidUpdateInstaller();
  static const _channel = MethodChannel(updateInstallerChannelName);

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const AppUpdateException(
        'Pemasangan pembaruan hanya tersedia pada Android.',
      );
    } on PlatformException catch (error) {
      throw AppUpdateException(switch (error.code) {
        'permission_denied' => 'Izin pemasangan belum diberikan. Izinkan Waras Arta memasang pembaruan, lalu coba lagi.',
        'invalid_apk' => 'APK tidak cocok, rusak, atau tanda tangannya berbeda. Pembaruan tidak dipasang.',
        'not_newer' =>
          'APK bukan versi yang lebih baru. Periksa pembaruan lagi.',
        'file_missing' =>
          'File pembaruan sudah tidak tersedia. Unduh ulang terlebih dahulu.',
        'busy' => 'Pemasang sedang dibuka. Tunggu lalu coba lagi.',
        _ => 'Pemasang Android belum dapat dibuka. Coba lagi.',
      });
    }
  }

  @override
  Future<bool> canInstall() async => await _invoke<bool>('canInstall') ?? false;
  @override
  Future<bool> requestPermission() async =>
      await _invoke<bool>('requestInstallPermission') ?? false;
  @override
  Future<void> install(String path, UpdateRelease release) async {
    await _invoke<bool>('installUpdate', {
      'path': path,
      'sha256': release.sha256,
      'size': release.size,
      'version': release.version.toString(),
    });
  }
}
