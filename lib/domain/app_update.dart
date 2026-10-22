import 'package:pub_semver/pub_semver.dart';

const updateRepository = 'panjiarif/waras-arta';
const maxUpdateApkBytes = 256 * 1024 * 1024;

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateRelease {
  const UpdateRelease({
    required this.tag,
    required this.version,
    required this.notes,
    required this.prerelease,
    required this.assetId,
    required this.size,
    required this.sha256,
    required this.downloadUri,
  });
  final String tag;
  final Version version;
  final String notes;
  final bool prerelease;
  final int assetId;
  final int size;
  final String sha256;
  final Uri downloadUri;
}

/// Highest published semantic version, including alpha releases. Never use
/// /releases/latest: GitHub excludes pre-releases from that endpoint.
UpdateRelease? selectUpdateRelease(List<Object?> releases, String installed) {
  final current = Version.parse(installed);
  Map? selected;
  Version? latest;
  for (final item in releases) {
    if (item is! Map || item['draft'] != false || item['prerelease'] is! bool) {
      continue;
    }
    final tag = item['tag_name'];
    if (tag is! String || tag.length > 100) continue;
    Version version;
    try {
      final normalizedTag = tag.startsWith('v') ? tag.substring(1) : tag;
      version = Version.parse(normalizedTag);
      if (version.build.isNotEmpty ||
          version.canonicalizedVersion != normalizedTag) {
        continue;
      }
    } on FormatException {
      continue;
    }
    if (version <= current || (latest != null && version <= latest)) continue;
    selected = item;
    latest = version;
  }
  if (selected == null || latest == null) return null;
  final tag = selected['tag_name'] as String;
  final assets = selected['assets'];
  if (assets is! List) {
    throw const AppUpdateException(
      'Rilis terbaru belum menyediakan APK pembaruan.',
    );
  }
  final matches = assets
      .whereType<Map>()
      .where((asset) => asset['name'] == 'waras-arta-$tag-android.apk')
      .toList();
  if (matches.length != 1) {
    throw const AppUpdateException(
      'Rilis terbaru belum menyediakan satu APK Android universal dengan nama yang sesuai.',
    );
  }
  final asset = matches.single;
  final id = asset['id'];
  final size = asset['size'];
  final digest = asset['digest'];
  final url = asset['browser_download_url'];
  final uri = url is String ? Uri.tryParse(url) : null;
  if (asset['state'] != 'uploaded' ||
      id is! int ||
      id <= 0 ||
      size is! int ||
      size <= 0 ||
      size > maxUpdateApkBytes ||
      digest is! String ||
      !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) ||
      uri == null ||
      !isTrustedUpdateUri(uri) ||
      uri.host != 'github.com' ||
      uri.query.isNotEmpty ||
      uri.pathSegments.length != 6 ||
      uri.pathSegments.take(4).join('/') !=
          '$updateRepository/releases/download' ||
      uri.pathSegments[4] != tag ||
      uri.pathSegments[5] != asset['name']) {
    throw const AppUpdateException(
      'Metadata APK terbaru belum lengkap atau tidak aman. Coba lagi setelah rilis diperbaiki.',
    );
  }
  final notes = selected['body'] is String ? selected['body'] as String : '';
  return UpdateRelease(
    tag: tag,
    version: latest,
    notes: notes.substring(0, notes.length.clamp(0, 12000)),
    prerelease: selected['prerelease'] as bool,
    assetId: id,
    size: size,
    sha256: digest.substring(7).toLowerCase(),
    downloadUri: uri,
  );
}

bool isTrustedUpdateUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    uri.fragment.isEmpty &&
    const {
      'api.github.com',
      'github.com',
      'release-assets.githubusercontent.com',
      'objects.githubusercontent.com',
    }.contains(uri.host);

class UpdateProgress {
  const UpdateProgress(this.received, this.total);
  final int received;
  final int total;
  double get fraction => (received / total).clamp(0, 1);
}

abstract interface class AppUpdateService {
  Future<UpdateRelease?> check(String installedVersion);
  Future<String> download(
    UpdateRelease release,
    void Function(UpdateProgress) onProgress,
  );
  void cancelDownload();
  void dispose();
}

abstract interface class UpdateInstaller {
  Future<bool> canInstall();
  Future<bool> requestPermission();
  Future<void> install(String path, UpdateRelease release);
}
