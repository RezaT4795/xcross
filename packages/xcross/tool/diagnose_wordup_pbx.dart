import 'dart:io';

import 'package:xcross/src/shared/flutter/build/pbxproj.dart';

void main() {
  final root = Platform.environment['WORDUP_ROOT']!;

  final project = PbxProject.parse(
    File(
      '$root/ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync(),
    projectDirectory: '$root/ios',
  );

  const configuration = 'Debug-wordup_full';

  void inspect(String label, PbxObject? owner) {
    print('\n===== $label =====');

    if (owner == null) {
      print('OWNER MISSING');
      return;
    }

    final list = project.object(
      owner.string('buildConfigurationList'),
    );

    if (list == null) {
      print('CONFIGURATION LIST MISSING');
      return;
    }

    for (final id in list.stringList('buildConfigurations')) {
      final config = project.object(id);

      if (config?.string('name') != configuration) continue;

      final settings = config!.map('buildSettings');

      print('Configuration: $configuration');
      print('Configuration ID: ${config.id}');
      print(
        'PRODUCT_BUNDLE_IDENTIFIER: '
        '${settings['PRODUCT_BUNDLE_IDENTIFIER']}',
      );
      print('DEVELOPMENT_TEAM: ${settings['DEVELOPMENT_TEAM']}');
      print(
        'Base configuration reference: '
        '${config.string('baseConfigurationReference')}',
      );
      return;
    }

    print('CONFIGURATION NOT FOUND');
  }

  inspect(
    'PROJECT-LEVEL SETTINGS',
    project.object(project.rootObjectId),
  );

  for (final target in project.nativeTargets) {
    if (target.string('name') == 'Runner') {
      inspect('RUNNER TARGET SETTINGS', target);
    }
  }
}
