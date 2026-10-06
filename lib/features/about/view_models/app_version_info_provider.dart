import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  const AppVersionInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get label {
    final normalizedVersion = version.trim();
    if (normalizedVersion.isEmpty) return 'Versi tidak tersedia';
    final normalizedBuildNumber = buildNumber.trim();
    return normalizedBuildNumber.isEmpty
        ? 'Versi $normalizedVersion'
        : 'Versi $normalizedVersion ($normalizedBuildNumber)';
  }
}

final appVersionInfoProvider = FutureProvider<AppVersionInfo>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return AppVersionInfo(
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
  );
});
