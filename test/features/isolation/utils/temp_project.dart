import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A throwaway analysable project, for isolation cases the checked-in fixture
/// tree cannot express.
///
/// Two of them cannot. A dependency outside the project is what the import gate
/// in `dependency_extractor_visitor.dart` keys on, and every checked-in fixture
/// is project-local or `package:flutter`. Pre-Dart-3 source is the other case:
/// it does not parse, so `dart format` over the repository fails on any file
/// holding it. That is real repository code the transplant has to handle, but
/// not something that can sit in `test/`.
class TempProject {
  TempProject._(this.dir);

  /// The project root.
  final Directory dir;

  String get path => dir.path;

  /// Creates a project holding [sources] (path under `lib/` → contents) that
  /// resolves everything this repo resolves, plus [extraPackages] (package name
  /// → package root directory).
  ///
  /// The package config is written rather than resolved by `pub get`: the
  /// project is temporary and has no pubspec of its own, and
  /// `IsolationDataSourceImpl` leaves an existing config alone.
  factory TempProject.create({
    required Map<String, String> sources,
    Map<String, String> extraPackages = const {},
    String prefix = 'spm_isolation_project',
  }) {
    final dir = Directory.systemTemp.createTempSync(prefix);
    for (final entry in sources.entries) {
      final file = File(p.join(dir.path, 'lib', entry.key))
        ..parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    _writePackageConfig(dir.path, extraPackages);
    return TempProject._(dir);
  }

  void delete() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  static void _writePackageConfig(
    String projectDir,
    Map<String, String> extraPackages,
  ) {
    final hostConfigPath = p.absolute('.dart_tool', 'package_config.json');
    final host =
        jsonDecode(File(hostConfigPath).readAsStringSync())
            as Map<String, Object?>;
    final hostDir = p.dirname(hostConfigPath);

    String absoluteRoot(String rootUri) {
      final uri = Uri.parse(rootUri);
      final resolved = uri.hasScheme
          ? uri.toFilePath()
          : p.normalize(p.join(hostDir, uri.toFilePath()));
      return Uri.directory(resolved).toString();
    }

    final packages = <Map<String, Object?>>[
      for (final entry
          in (host['packages'] as List).cast<Map<String, Object?>>())
        {...entry, 'rootUri': absoluteRoot(entry['rootUri']! as String)},
      for (final entry in extraPackages.entries)
        {
          'name': entry.key,
          'rootUri': Uri.directory(entry.value).toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.0',
        },
    ];

    File(p.join(projectDir, '.dart_tool', 'package_config.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': packages,
          'generator': 'spm-test',
        }),
      );
  }
}
