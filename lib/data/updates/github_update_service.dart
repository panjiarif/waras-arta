import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/app_update.dart';

class UpdateHttpResponse {
  const UpdateHttpResponse({
    required this.status,
    required this.body,
    this.length = -1,
  });
  final int status;
  final int length;
  final Stream<List<int>> body;
}

abstract interface class UpdateHttpTransport {
  Future<UpdateHttpResponse> get(Uri uri);
  void close();
}

class IoUpdateHttpTransport implements UpdateHttpTransport {
  IoUpdateHttpTransport() {
    _client.connectionTimeout = const Duration(seconds: 20);
    _client.userAgent = 'WarasArta-updater';
  }
  final _client = HttpClient();
  @override
  Future<UpdateHttpResponse> get(Uri uri) async {
    for (var redirect = 0; redirect <= 5; redirect++) {
      if (!isTrustedUpdateUri(uri)) {
        throw const AppUpdateException(
          'Alamat unduhan pembaruan tidak diizinkan.',
        );
      }
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 25));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        uri.host == 'api.github.com'
            ? 'application/vnd.github+json'
            : 'application/octet-stream',
      );
      // No authentication token or finance data is sent, including on redirects.
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw const AppUpdateException(
            'Alamat unduhan pembaruan tidak tersedia.',
          );
        }
        uri = uri.resolve(location);
        continue;
      }
      return UpdateHttpResponse(
        status: response.statusCode,
        body: response,
        length: response.contentLength,
      );
    }
    throw const AppUpdateException(
      'Terlalu banyak pengalihan unduhan. Coba lagi.',
    );
  }

  @override
  void close() => _client.close(force: true);
}

class GitHubUpdateService implements AppUpdateService {
  GitHubUpdateService({
    UpdateHttpTransport Function()? transportFactory,
    Future<Directory> Function()? cacheDirectory,
  }) : _transportFactory = transportFactory ?? IoUpdateHttpTransport.new,
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory;
  final UpdateHttpTransport Function() _transportFactory;
  final Future<Directory> Function() _cacheDirectory;
  UpdateHttpTransport? _active;
  bool _canceled = false;
  bool _disposed = false;

  @override
  Future<UpdateRelease?> check(String installedVersion) async {
    final transport = _begin();
    try {
      final releases = <Object?>[];
      // Bound metadata memory and pagination; include pre-releases, not /latest.
      for (var page = 1; page <= 3; page++) {
        final response = await transport.get(
          Uri.https('api.github.com', '/repos/$updateRepository/releases', {
            'per_page': '100',
            'page': '$page',
          }),
        );
        _checkStatus(response.status);
        const limit = 2 * 1024 * 1024;
        if (response.length > limit) {
          throw const AppUpdateException(
            'Daftar rilis terlalu besar. Coba lagi nanti.',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response.body.timeout(
          const Duration(seconds: 30),
        )) {
          _ensureActive();
          if (bytes.length + chunk.length > limit) {
            throw const AppUpdateException(
              'Daftar rilis terlalu besar. Coba lagi nanti.',
            );
          }
          bytes.addAll(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! List) {
          throw const AppUpdateException('Daftar rilis GitHub tidak valid.');
        }
        releases.addAll(decoded);
        if (decoded.length < 100) {
          return selectUpdateRelease(releases, installedVersion);
        }
      }
      throw const AppUpdateException(
        'Daftar rilis terlalu panjang untuk diperiksa. Coba lagi nanti.',
      );
    } on AppUpdateException {
      rethrow;
    } catch (_) {
      throw const AppUpdateException(
        'Pembaruan belum dapat diperiksa. Periksa koneksi internet lalu coba lagi.',
      );
    } finally {
      transport.close();
      if (identical(_active, transport)) _active = null;
    }
  }

  @override
  Future<String> download(
    UpdateRelease release,
    void Function(UpdateProgress) onProgress,
  ) async {
    final transport = _begin();
    File? partial;
    RandomAccessFile? output;
    try {
      if (release.assetId <= 0 ||
          !isTrustedUpdateUri(release.downloadUri) ||
          release.size <= 0 ||
          release.size > maxUpdateApkBytes ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(release.sha256)) {
        throw const AppUpdateException('Metadata pembaruan tidak valid.');
      }
      final cache = await _cacheDirectory();
      final directory = Directory('${cache.path}/updates');
      await directory.create(recursive: true);
      // Only our dedicated cache folder is managed; never touch the database.
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File &&
            RegExp(r'^update-[0-9]+\.apk(?:\.part)?$')
                .hasMatch(entry.uri.pathSegments.last)) {
          await entry.delete();
        }
      }
      _ensureActive();
      final finalFile = File('${directory.path}/update-${release.assetId}.apk');
      partial = File('${finalFile.path}.part');
      output = await partial.open(mode: FileMode.write);
      final response = await transport.get(release.downloadUri);
      _checkStatus(response.status);
      if (response.length >= 0 && response.length != release.size) {
        throw const AppUpdateException(
          'Ukuran APK tidak sesuai dengan rilis. Unduhan dibatalkan.',
        );
      }
      final hash = const DartSha256().newHashSink();
      var received = 0;
      final stopwatch = Stopwatch()..start();
      var lastProgress = -150;
      onProgress(UpdateProgress(0, release.size));
      await for (final chunk in response.body.timeout(
        const Duration(seconds: 30),
      )) {
        _ensureActive();
        received += chunk.length;
        if (received > release.size) {
          throw const AppUpdateException(
            'Ukuran APK melebihi rilis. Unduhan dibatalkan.',
          );
        }
        hash.add(chunk);
        await output.writeFrom(chunk);
        if (stopwatch.elapsedMilliseconds - lastProgress >= 150) {
          onProgress(UpdateProgress(received, release.size));
          lastProgress = stopwatch.elapsedMilliseconds;
        }
      }
      hash.close();
      final digest = (await hash.hash()).bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      _ensureActive();
      if (received != release.size || digest != release.sha256) {
        throw const AppUpdateException(
          'Verifikasi APK gagal. File tidak akan dipasang; silakan unduh ulang.',
        );
      }
      await output.flush();
      await output.close();
      output = null;
      _ensureActive();
      partial = await partial.rename(finalFile.path);
      _ensureActive();
      partial = null;
      onProgress(UpdateProgress(received, release.size));
      return finalFile.path;
    } on AppUpdateException {
      rethrow;
    } on FileSystemException {
      throw const AppUpdateException(
        'APK belum dapat disimpan. Periksa ruang penyimpanan lalu unduh ulang.',
      );
    } catch (_) {
      throw AppUpdateException(
        _canceled
            ? 'Unduhan dibatalkan.'
            : 'Unduhan terputus. Periksa koneksi lalu unduh ulang.',
      );
    } finally {
      try {
        try {
          await output?.close();
        } on FileSystemException {
          // Closing a failed write must not prevent connection cleanup.
        }
        try {
          if (partial != null && await partial.exists()) await partial.delete();
        } on FileSystemException {
          // A stale .part is never installable and is retried on next download.
        }
      } finally {
        transport.close();
        if (identical(_active, transport)) _active = null;
      }
    }
  }

  UpdateHttpTransport _begin() {
    if (_disposed || _active != null) {
      throw const AppUpdateException(
        'Pembaruan sedang diproses. Tunggu sebentar.',
      );
    }
    _canceled = false;
    return _active = _transportFactory();
  }

  void _ensureActive() {
    if (_disposed || _canceled) {
      throw const AppUpdateException('Unduhan dibatalkan.');
    }
  }

  void _checkStatus(int status) {
    if (status == 403 || status == 429) {
      throw const AppUpdateException(
        'Batas akses GitHub tercapai. Coba lagi nanti.',
      );
    }
    if (status != 200) {
      throw const AppUpdateException(
        'GitHub belum dapat menyediakan pembaruan. Coba lagi nanti.',
      );
    }
  }

  @override
  void cancelDownload() {
    _canceled = true;
    _active?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _active?.close();
  }
}
