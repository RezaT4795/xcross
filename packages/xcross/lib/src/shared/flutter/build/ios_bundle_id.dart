import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/flutter/build/pbxproj.dart';
import 'package:xcross/src/shared/flutter/errors.dart';
import 'package:xcross/src/shared/flutter/project/pbx_project_reader.dart';

@internal
final class IosBundleId {
  IosBundleId(this.fileSystem, this.paths, this.projects);

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final PbxProjectReader projects;

  static final _productBundleIdPattern = RegExp(
    r'''^\s*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(["']?)(.*?)\1;\s*$''',
    multiLine: true,
  );

  static final _cfBundleIdentifierPattern = RegExp(
    r'<key>CFBundleIdentifier</key>\s*<string>([^<]*)</string>',
  );

  static const _applicationProductType = 'com.apple.product-type.application';

  String resolve(String projectRoot, {String? configuration}) {
    if (configuration == null) {
      final fromPlist = _cfBundleIdentifierFromPlist(projectRoot);
      if (fromPlist != null && !fromPlist.contains(r'$')) {
        return fromPlist;
      }
    }

    final fromPbxproj = _productBundleIdFromPbxproj(
      projectRoot,
      configuration: configuration,
    );
    if (fromPbxproj != null) return fromPbxproj;

    throw FlutterBuildError(
      'Could not resolve iOS bundle identifier'
      '${configuration == null ? '' : ' for configuration "$configuration"'}.',
    );
  }

  String? _cfBundleIdentifierFromPlist(String projectRoot) {
    final file = fileSystem.file(
      paths.join(projectRoot, 'ios', 'Runner', 'Info.plist'),
    );
    if (!file.existsSync()) return null;

    final match = _cfBundleIdentifierPattern.firstMatch(
      file.readAsStringSync(),
    );

    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _productBundleIdFromPbxproj(
    String projectRoot, {
    String? configuration,
  }) {
    final path = _findPbxproj(projectRoot);
    if (path == null) return null;

    final structured = _appTargetBundleId(path, configuration: configuration);
    if (structured != null) return structured;

    final source = fileSystem.file(path).readAsStringSync();

    if (configuration != null) {
      return _namedConfigurationBundleId(source, configuration);
    }

    final match = _productBundleIdPattern.firstMatch(source);
    return _clean(match?.group(2));
  }

  String? _appTargetBundleId(String pbxprojPath, {String? configuration}) {
    final project = projects.parseFile(pbxprojPath);
    if (project == null) return null;

    ({bool found, String? value}) lookup(
      PbxObject? owner,
      String configurationName,
    ) {
      if (owner == null) {
        return (found: false, value: null);
      }

      final list = project.object(owner.string('buildConfigurationList'));

      for (final id
          in list?.stringList('buildConfigurations') ?? const <String>[]) {
        final config = project.object(id);

        if (config?.isa != 'XCBuildConfiguration' ||
            config?.string('name') != configurationName) {
          continue;
        }

        final raw = config!.map('buildSettings')['PRODUCT_BUNDLE_IDENTIFIER'];

        return (found: true, value: raw is String ? _clean(raw) : null);
      }

      return (found: false, value: null);
    }

    final projectOwner = project.object(project.rootObjectId);

    final inherited = configuration == null
        ? projectOwner == null
              ? null
              : _clean(
                  project.buildSetting(
                    projectOwner,
                    'PRODUCT_BUNDLE_IDENTIFIER',
                  ),
                )
        : lookup(projectOwner, configuration).value;

    String? fallback;

    for (final target in project.nativeTargets) {
      if (target.string('productType') != _applicationProductType) {
        continue;
      }

      final String? targetValue;

      if (configuration == null) {
        targetValue = _clean(
          project.buildSetting(target, 'PRODUCT_BUNDLE_IDENTIFIER'),
        );
      } else {
        final selected = lookup(target, configuration);

        if (!selected.found) continue;

        targetValue = selected.value;
      }

      final bundleId = targetValue ?? inherited;
      if (bundleId == null) continue;

      if (target.string('name') == 'Runner') {
        return bundleId;
      }

      fallback ??= bundleId;
    }

    return fallback;
  }

  // Fallback for projects whose complete pbxproj cannot be parsed.
  // Parse only the XCBuildConfiguration section, where the flavor's
  // PRODUCT_BUNDLE_IDENTIFIER is declared.

  String? _namedConfigurationBundleId(String source, String configuration) {
    const sections = [
      'PBXNativeTarget',
      'XCConfigurationList',
      'XCBuildConfiguration',
    ];

    final contents = StringBuffer();

    for (final section in sections) {
      final begin = '/* Begin $section section */';
      final end = '/* End $section section */';

      final start = source.indexOf(begin);
      if (start < 0) return null;

      final finish = source.indexOf(end, start + begin.length);
      if (finish < 0) return null;

      contents.writeln(source.substring(start + begin.length, finish));
    }

    final PbxProject project;

    try {
      project = PbxProject.parse(
        '{ objects = {\n$contents\n}; }',
        projectDirectory: '',
      );
    } on FormatException catch (error) {
      throw FlutterBuildError(
        'Could not parse Xcode target configurations: $error',
      );
    }

    final applicationIds = <String>{};
    final runnerIds = <String>{};

    for (final target in project.nativeTargets) {
      if (target.string('productType') != _applicationProductType) {
        continue;
      }

      final list = project.object(target.string('buildConfigurationList'));

      for (final id
          in list?.stringList('buildConfigurations') ?? const <String>[]) {
        final config = project.object(id);

        if (config == null ||
            config.isa != 'XCBuildConfiguration' ||
            config.string('name') != configuration) {
          continue;
        }

        final raw = config.map('buildSettings')['PRODUCT_BUNDLE_IDENTIFIER'];

        final bundleId = raw is String ? _clean(raw) : null;
        if (bundleId == null) continue;

        applicationIds.add(bundleId);

        if (target.string('name') == 'Runner') {
          runnerIds.add(bundleId);
        }
      }
    }

    final identifiers = runnerIds.isNotEmpty ? runnerIds : applicationIds;

    if (identifiers.length > 1) {
      throw FlutterBuildError(
        'Ambiguous application bundle identifiers for '
        '"$configuration": ${identifiers.join(', ')}',
      );
    }

    return identifiers.isEmpty ? null : identifiers.single;
  }

  static String? _clean(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty || value.contains(r'$')) {
      return null;
    }
    return value;
  }

  String? _findPbxproj(String projectRoot) {
    final iosPath = paths.join(projectRoot, 'ios');
    final iosDir = fileSystem.directory(iosPath);
    if (!iosDir.existsSync()) return null;

    final runner = paths.join(iosPath, 'Runner.xcodeproj', 'project.pbxproj');
    if (fileSystem.file(runner).existsSync()) return runner;

    for (final entity in iosDir.listSync()) {
      if (entity is! Directory) continue;

      final name = paths.basename(entity.path);
      if (!name.endsWith('.xcodeproj')) continue;

      final candidate = paths.join(entity.path, 'project.pbxproj');
      if (fileSystem.file(candidate).existsSync()) return candidate;
    }

    return null;
  }
}
