import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/flutter/errors.dart';
import 'package:xml/xml.dart';

/// Fedora prototype: compile the selected .appiconset and stage it before
/// the final app bundle is signed. Does not modify the Flutter source tree.
final class IosAppIconStager {
  static Future<void> stage({
    required String projectRoot,
    required String bundleDir,
    required String? flavor,
  }) async {
    if (flavor == null || flavor.isEmpty) return;

    final iconName = 'AppIcon-$flavor';
    final iconSet = Directory(
      p.join(
        projectRoot,
        'ios',
        'Runner',
        'Assets.xcassets',
        '$iconName.appiconset',
      ),
    );
    if (!iconSet.existsSync()) return;

    final script = Platform.environment['XCROSS_ICON_COMPILER_SCRIPT'];
    if (script == null || !File(script).existsSync()) {
      throw FlutterBuildError(
        'Icon set $iconName exists, but XCROSS_ICON_COMPILER_SCRIPT does not '
        'point to the working icon compiler compile.sh.',
      );
    }

    final result = await Process.run('bash', [script, projectRoot, flavor]);
    if (result.exitCode != 0) {
      throw FlutterBuildError(
        'Failed to compile $iconName (exit ${result.exitCode}):\n'
        '${result.stdout}\n${result.stderr}',
      );
    }

    await stageCompiled(
      compiledDir: p.join(projectRoot, 'build', 'xcross-icon-preview', flavor),
      bundleDir: bundleDir,
    );
  }

  /// Stage previously compiled resources; independently unit-testable.
  static Future<void> stageCompiled({
    required String compiledDir,
    required String bundleDir,
  }) async {
    final compiled = Directory(compiledDir);
    final car = File(p.join(compiledDir, 'Assets.car'));
    final additions = File(p.join(compiledDir, 'IconPlistAdditions.plist'));
    final appPlist = File(p.join(bundleDir, 'Info.plist'));

    if (!compiled.existsSync() ||
        !car.existsSync() ||
        car.lengthSync() == 0 ||
        !additions.existsSync() ||
        !appPlist.existsSync()) {
      throw FlutterBuildError(
        'Incomplete compiled icon resources or missing app Info.plist: '
        '$compiledDir / $bundleDir',
      );
    }

    final appXml = await appPlist.readAsString();
    final additionsXml = await additions.readAsString();
    final appDict = XmlDocument.parse(appXml).rootElement.getElement('dict');
    final iconDict = XmlDocument.parse(
      additionsXml,
    ).rootElement.getElement('dict');
    if (appDict == null || iconDict == null) {
      throw FlutterBuildError('Invalid app or generated icon plist structure.');
    }

    const iconKeys = {
      'CFBundleIconName',
      'CFBundleIconFiles',
      'CFBundleIcons',
      'CFBundleIcons~ipad',
    };
    final existing = appDict
        .findElements('key')
        .map((key) => key.innerText.trim())
        .where(iconKeys.contains)
        .toList();
    if (existing.isNotEmpty) {
      throw FlutterBuildError(
        'The app already declares icon metadata (${existing.join(', ')}). '
        'Merge those keys instead of adding duplicates.',
      );
    }

    final additionsBody = iconDict.children
        .map((child) => child.toXmlString())
        .join();
    final end = appXml.lastIndexOf('</dict>');
    if (end < 0) throw FlutterBuildError('App Info.plist has no closing dict.');
    final merged =
        '${appXml.substring(0, end)}\n'
        '$additionsBody\n'
        '${appXml.substring(end)}';
    XmlDocument.parse(merged); // Validate before writing.

    for (final item in compiled.listSync(followLinks: false)) {
      if (item is! File) continue;
      final name = p.basename(item.path);
      if (name != 'Assets.car' && !name.endsWith('.png')) continue;
      // Copy bytes, not Linux SELinux/xattr metadata.
      await File(
        p.join(bundleDir, name),
      ).writeAsBytes(await item.readAsBytes(), flush: true);
    }
    await appPlist.writeAsString(merged);
  }
}
