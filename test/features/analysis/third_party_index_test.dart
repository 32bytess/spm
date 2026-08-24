@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/analysis/data/data_sources/analysis_data_source_impl.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_event.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import '../isolation/utils/temp_project.dart';

/// A package widget's subtree, counted in place.
///
/// `TreeExtractor._indexLibrary` resolved a third-party library URI to a path in
/// the pub cache without trouble, and then `contextFor` threw `StateError` for
/// any path outside the analyzed roots. The throw was swallowed, the entry
/// cached as a miss, and the child dropped along with its whole subtree. So a
/// transplant that carried a package widget counted more than the in-place row
/// for the same scope, which is a systematic difference inside the very
/// comparison the work exists to make.
const String _scopeSource = '''
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class PackageHost extends StatefulWidget {
  const PackageHost({super.key});

  @override
  State<PackageHost> createState() => PackageHostState();
}

class PackageHostState extends State<PackageHost> {
  @override
  Widget build(BuildContext context) =>
      Column(children: [FancyButton(label: 'go')]);
}
''';

Future<List<AnalysisResultEntity>> _analyze(
  String directory, {
  String? packageConfigFile,
}) async {
  final rows = <AnalysisResultEntity>[];
  final events = AnalysisDataSourceImpl().analyzeDirs([
    directory,
  ], packageConfigFile: packageConfigFile);
  await for (final event in events) {
    if (event is AnalysisDataEvent) rows.add(event.result);
  }
  return rows;
}

/// A copy of the fake package under a pub-cache style `name-version` directory.
///
/// The version lives nowhere else the extractor can see it: a hosted package
/// resolves to `<cache>/hosted/<host>/<name>-<version>/lib`, and that path
/// segment is the only record of which source the numbers were computed from.
String _versionedCopy(String name, String version) {
  final root = Directory.systemTemp.createTempSync('spm_versioned');
  final target = Directory(p.join(root.path, '$name-$version', 'lib'))
    ..createSync(recursive: true);
  File(p.join(target.path, '$name.dart')).writeAsStringSync(
    File(
      p.join(
        p.absolute('test/fixtures/isolation_third_party'),
        'ui_kit',
        'lib',
        'ui_kit.dart',
      ),
    ).readAsStringSync(),
  );
  return p.dirname(target.path);
}

void main() {
  late TempProject project;
  late AnalysisResultEntity scope;

  setUpAll(() async {
    project = TempProject.create(
      sources: {'host.dart': _scopeSource},
      extraPackages: {'ui_kit': _versionedCopy('ui_kit', '9.9.9')},
      prefix: 'spm_package_index',
    );
    final rows = await _analyze(
      project.path,
      packageConfigFile: p.join(
        project.path,
        '.dart_tool',
        'package_config.json',
      ),
    );
    scope = rows.firstWhere((row) => row.scopeName == 'PackageHostState');
  });

  tearDownAll(() => project.delete());

  test('the package widget contributes its own build tree', () {
    // `Column` and `FancyButton` from the scope's own body, then `FancyRow`
    // from FancyButton's build, then `Row`, `Text`, `_FancyDot` and `Divider`
    // from that one. Anything at or below three means the walk stopped at the
    // package boundary.
    expect(scope.treeNonConstWidgetCount, greaterThan(3));
    expect(scope.treeMaxWidgetNestingDepth, greaterThan(2));
  });

  test('the package library is not reported as unresolved', () {
    // The old behaviour cached the failed `contextFor` as a miss, so the
    // library came back unreadable and the row was short by an unknown amount.
    expect(scope.unresolvedDependencies, isEmpty);
    expect(scope.closureResolved, isTrue);
  });

  test('the package file does not leak a machine path into the row', () {
    // A package file enters the closure and does not survive onto the row. Its
    // absolute path names a pub cache on one machine, and a row carrying it
    // could not be compared with one produced anywhere else. What the row needs
    // from a package is its version, and `packageVersions` carries that.
    expect(
      scope.dependencyFiles.any((path) => p.isAbsolute(path)),
      isFalse,
      reason: '${scope.dependencyFiles}',
    );
  });

  test('the classes walked in place are reported', () {
    // The other half of the symmetry check against `spm isolate`: for every
    // declaration walked here, the transplant of the same scope has to carry
    // the source, or the two rows describe different trees.
    expect(
      scope.walkedWidgetClasses.any((id) => id.endsWith('#FancyRow')),
      isTrue,
      reason: '${scope.walkedWidgetClasses}',
    );
  });

  test('the resolved package version is on the row', () {
    // A package version became an input to the metrics the moment the extractor
    // started reading package libraries, so two revisions of one repository
    // whose pubspec.lock moved can show a feature delta with no source edit
    // between them. The answer is to analyse every revision against one
    // resolved package config, and this is what makes that pin auditable: a
    // pair that somehow read two different versions is visible rather than
    // silent.
    expect(scope.packageVersions['ui_kit'], '9.9.9');
  });

  test('the framework boundary still holds', () {
    // Stopping at `dart:` and `package:flutter/` is a correctness decision
    // rather than a cost one: the visitor counts every branch of a build body
    // rather than the branch that ran, so walking `_ScaffoldState.build` would
    // make a `Scaffold` carrying only a `body:` count identically to one
    // carrying everything a Scaffold can ever show.
    expect(
      scope.walkedWidgetClasses.any((id) => id.startsWith('package:flutter/')),
      isFalse,
    );
  });
}
