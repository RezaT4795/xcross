@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../flutter_test_runtime.dart';

void main() {
  test('resolves the actual WordUp Xcode configurations', () {
    final root = Platform.environment['WORDUP_ROOT'];

    expect(root, isNotNull, reason: 'WORDUP_ROOT must point to zann-flutter');

    final project = File('$root/ios/Runner.xcodeproj/project.pbxproj');

    expect(project.existsSync(), isTrue);

    final resolver = testIPhoneRuntime().bundleIds;

    for (final mode in ['Debug', 'Profile', 'Release']) {
      expect(
        resolver.resolve(root!, configuration: '$mode-wordup_full'),
        'com.geeksltd.wordatown',
        reason: 'Wrong bundle ID for $mode-wordup_full',
      );
    }
  });
}
