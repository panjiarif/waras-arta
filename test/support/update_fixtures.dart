import 'package:waras_arta/domain/app_update.dart';

Map<String, Object?> releaseJson({
  String tag = 'v0.1.1',
  bool draft = false,
  bool prerelease = true,
  String? digest,
  int size = 3,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'body': 'Perbaikan untuk tester.',
  'assets': [
    <String, Object?>{
      'id': 123,
      'name': 'waras-arta-$tag-android.apk',
      'state': 'uploaded',
      'size': size,
      // SHA-256 of [1, 2, 3].
      'digest': digest ?? 'sha256:039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
      'browser_download_url':
          'https://github.com/panjiarif/waras-arta/releases/download/$tag/waras-arta-$tag-android.apk',
    },
  ],
};

UpdateRelease updateRelease() => selectUpdateRelease([releaseJson()], '0.1.0')!;
