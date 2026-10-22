import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/data/updates/github_update_service.dart';

void main() {
  test(
    'live public GitHub metadata is compatible with the production checker',
    () async {
      final service = GitHubUpdateService();
      addTearDown(service.dispose);
      // Read metadata only: never download or install an APK in this test.
      final release = await service.check('0.0.0');
      expect(release, isNotNull);
      expect(release!.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(release.downloadUri.host, 'github.com');
    },
    skip: !const bool.fromEnvironment('LIVE_GITHUB_UPDATE_CHECK'),
  );
}
