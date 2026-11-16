@TestOn('!windows')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../flutter_test_runtime.dart';

void main() {
  test('resolves the application instead of the UI test target', () async {
    final root = await Directory.systemTemp.createTemp(
      'xcross_flavor_bundle_id-',
    );

    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });

    final project = Directory(p.join(root.path, 'ios', 'Runner.xcodeproj'));
    await project.create(recursive: true);

    await File(p.join(project.path, 'project.pbxproj')).writeAsString(r'''
/* Begin PBXNativeTarget section */
APP = {
    isa = PBXNativeTarget;
    buildConfigurationList = APP_LIST;
    name = Runner;
    productType = "com.apple.product-type.application";
};
TESTS = {
    isa = PBXNativeTarget;
    buildConfigurationList = TEST_LIST;
    name = RunnerUITests;
    productType = "com.apple.product-type.bundle.ui-testing";
};
/* End PBXNativeTarget section */

/* Begin XCConfigurationList section */
APP_LIST = {
    isa = XCConfigurationList;
    buildConfigurations = (APP_WORDUP, APP_LESSONS);
};
TEST_LIST = {
    isa = XCConfigurationList;
    buildConfigurations = (TEST_WORDUP, TEST_LESSONS);
};
/* End XCConfigurationList section */

/* Begin XCBuildConfiguration section */
APP_WORDUP = {
    isa = XCBuildConfiguration;
    buildSettings = {
        PRODUCT_BUNDLE_IDENTIFIER = com.geeksltd.wordatown;
    };
    name = "Debug-wordup_full";
};
APP_LESSONS = {
    isa = XCBuildConfiguration;
    buildSettings = {
        PRODUCT_BUNDLE_IDENTIFIER = zann.lessons;
    };
    name = "Debug-zann_lessons";
};
TEST_WORDUP = {
    isa = XCBuildConfiguration;
    buildSettings = {
        PRODUCT_BUNDLE_IDENTIFIER = com.geeksltd.RunnerUITests;
    };
    name = "Debug-wordup_full";
};
TEST_LESSONS = {
    isa = XCBuildConfiguration;
    buildSettings = {
        PRODUCT_BUNDLE_IDENTIFIER = com.geeksltd.RunnerUITests;
    };
    name = "Debug-zann_lessons";
};
/* End XCBuildConfiguration section */
''');

    final resolver = testIPhoneRuntime().bundleIds;

    expect(
      resolver.resolve(root.path, configuration: 'Debug-wordup_full'),
      'com.geeksltd.wordatown',
    );

    expect(
      resolver.resolve(root.path, configuration: 'Debug-zann_lessons'),
      'zann.lessons',
    );
  });
}
