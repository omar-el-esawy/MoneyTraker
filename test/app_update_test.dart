import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/services/app_update_logic.dart';

void main() {
  test('a release label includes the build number when it exists', () {
    expect(releaseLabel('2.0.3', 4), '2.0.3 (4)');
    expect(releaseLabel('2.0.3', null), '2.0.3');
    expect(releaseLabel('2.0.3', 0), '2.0.3');
  });

  test('version names compare numerically', () {
    expect(compareVersionNames('2.0.3', '2.0.2'), greaterThan(0));
    expect(compareVersionNames('2.0.2', '2.0.2'), 0);
    expect(compareVersionNames('2.0.1', '2.0.2'), lessThan(0));
    expect(compareVersionNames('2.1', '2.0.9'), greaterThan(0));
    expect(compareVersionNames('2.0.10', '2.0.9'), greaterThan(0));
  });

  test('build number is only a tiebreaker', () {
    expect(
      isRemoteNewer(
        localVersion: '2.0.2',
        localBuild: 4,
        remoteVersion: '2.0.2',
        remoteBuild: 5,
      ),
      isTrue,
    );
    expect(
      isRemoteNewer(
        localVersion: '2.0.2',
        localBuild: 5,
        remoteVersion: '2.0.2',
        remoteBuild: 5,
      ),
      isFalse,
    );
    expect(
      isRemoteNewer(
        localVersion: '2.0.2',
        localBuild: 9,
        remoteVersion: '2.0.2',
        remoteBuild: null,
      ),
      isFalse,
    );
    expect(
      isRemoteNewer(
        localVersion: '2.0.2',
        localBuild: 9,
        remoteVersion: '2.0.2',
        remoteBuild: 0,
      ),
      isFalse,
    );
    expect(
      isRemoteNewer(
        localVersion: '2.0.3',
        localBuild: 1,
        remoteVersion: '2.0.2',
        remoteBuild: 99,
      ),
      isFalse,
    );
    expect(
      isRemoteNewer(
        localVersion: '2.0.2',
        localBuild: 99,
        remoteVersion: '2.0.3',
        remoteBuild: 1,
      ),
      isTrue,
    );
  });

  test('parses force update and rejects a non-https download', () {
    final release = parseRemoteRelease({
      'version': '2.0.3',
      'build_number': '12',
      'force_update': true,
      'download_url': 'https://github.com/example/app.apk',
      'changelog': 'fix',
    });
    expect(release, isNotNull);
    expect(release!.forceUpdate, isTrue);
    expect(release.buildNumber, 12);
    expect(release.changelog, 'fix');

    expect(
      parseRemoteRelease({
        'version': '2.0.3',
        'force_upload': 'yes',
        'download_url': 'https://github.com/example/app.apk',
      })!.forceUpdate,
      isTrue,
    );

    expect(
      parseRemoteRelease({
        'version': '2.0.3',
        'build_number': null,
        'force_update': false,
        'download_url': 'https://github.com/example/app.apk',
      })!.buildNumber,
      isNull,
    );

    expect(
      parseRemoteRelease({
        'version': '2.0.3',
        'download_url': 'http://insecure.example/app.apk',
      }),
      isNull,
    );
  });
}
