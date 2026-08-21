import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// Pre-Dart-3 default-value separators, `{int flex: 2}` and `[double size: 8]`.
///
/// The source is written at run time rather than checked in as a fixture: it
/// does not parse under a modern SDK, so `dart format` over the repository
/// fails on any file that contains it. The parser still recovers and reports
/// the separator token, which is what makes the rewrite exact.
const String _legacySource = '''
import 'package:flutter/material.dart';

class LegacyDefaults extends StatefulWidget {
  const LegacyDefaults({super.key});

  @override
  State<LegacyDefaults> createState() => LegacyDefaultsState();
}

class LegacyDefaultsState extends State<LegacyDefaults> {
  Widget _row(String label, {int flex: 2}) =>
      Expanded(flex: flex, child: Text(label));

  Widget _spacer([double size: 8]) => SizedBox(height: size);

  @override
  Widget build(BuildContext context) =>
      Column(children: [_row('a'), _spacer(), _row('b', flex: 3)]);
}
''';

void main() {
  late TempProject project;
  late String outputDir;
  late String isolated;

  setUpAll(() async {
    project = TempProject.create(
      sources: {'legacy_defaults.dart': _legacySource},
      prefix: 'spm_legacy_syntax',
    );
    outputDir = Directory.systemTemp.createTempSync('spm_legacy_out').path;

    await IsolationDataSourceImpl()
        .isolate(directories: [project.path], outputDir: outputDir)
        .drain();

    isolated = Directory(p.join(outputDir, 'State'))
        .listSync(recursive: false)
        .whereType<File>()
        .firstWhere((f) => f.path.contains('LegacyDefaultsState'))
        .readAsStringSync();
  });

  tearDownAll(() {
    project.delete();
    final dir = Directory(outputDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('rewrites the separator on a named parameter', () {
    // OBSOLETE_COLON_FOR_DEFAULT_VALUE at the use site, which is error
    // severity, which means `spm analyze` skips the whole file.
    expect(isolated, contains('{int flex = 2}'));
    expect(isolated, isNot(contains('{int flex: 2}')));
  });

  test('rewrites the separator on an optional positional parameter', () {
    // WRONG_SEPARATOR_FOR_POSITIONAL_PARAMETER. A different code for the same
    // obsolete syntax, which is why the rewrite keys on the token rather than
    // on the kind of parameter it sits on.
    expect(isolated, contains('[double size = 8]'));
    expect(isolated, isNot(contains('[double size: 8]')));
  });

  test('leaves the rest of the declaration untouched', () {
    expect(isolated, contains('Expanded(flex: flex, child: Text(label))'));
    expect(isolated, contains("_row('b', flex: 3)"));
  });
}
