import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// A widget the scope builds, declared in a `part` of the same library.
///
/// The element model reports such a declaration against the file that *defines
/// the library*, not the file it is written in. The same-file lookup therefore
/// searched the defining unit, found nothing, and marked the name processed on
/// the way out, so no later reference retried it and the widget was never
/// carried. An undefined child widget is worse than a missing one: the metrics
/// pipeline skips its whole subtree, so the row that comes out is wrong rather
/// than absent.
const String _libSource = '''
import 'package:flutter/material.dart';

part 'tile.dart';

class PartHost extends StatefulWidget {
  const PartHost({super.key});

  @override
  State<PartHost> createState() => PartHostState();
}

class PartHostState extends State<PartHost> {
  @override
  Widget build(BuildContext context) =>
      Column(children: const [_PartTile(label: 'one')]);
}
''';

const String _partSource = '''
part of 'page.dart';

class _PartTile extends StatelessWidget {
  const _PartTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

void main() {
  late TempProject project;
  late String outputDir;
  late String isolated;
  late IsolationSummaryEvent summary;

  setUpAll(() async {
    project = TempProject.create(
      sources: {'page.dart': _libSource, 'tile.dart': _partSource},
      prefix: 'spm_part_file',
    );
    outputDir = Directory.systemTemp.createTempSync('spm_part_file_out').path;

    final events = await IsolationDataSourceImpl()
        .isolate(directories: [project.path], outputDir: outputDir)
        .toList();
    summary = events.last as IsolationSummaryEvent;

    isolated = Directory(p.join(outputDir, 'State'))
        .listSync(recursive: false)
        .whereType<File>()
        .firstWhere((f) => f.path.contains('PartHostState'))
        .readAsStringSync();
  });

  tearDownAll(() {
    project.delete();
    final dir = Directory(outputDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a widget declared in a part file comes across', () {
    expect(isolated, contains('class _PartTile extends StatelessWidget'));
  });

  test('the part file brings its own body, not a stand-in', () {
    // A stand-in would resolve just as cleanly and report an empty subtree,
    // which is the silent half of the same defect.
    expect(isolated, contains('Text(label)'));
  });

  test('nothing carries the part directive into the isolated file', () {
    expect(isolated, isNot(contains('part of')));
    expect(isolated, isNot(contains("part '")));
  });

  test('every isolated file analyses clean', () {
    // The property the whole feature exists for: `spm analyze` skips any file
    // carrying an error-severity diagnostic, so a scope that was written but
    // does not analyse contributes nothing.
    expect(summary.verifiedCount, greaterThan(0));
    expect(
      summary.cleanCount,
      summary.verifiedCount,
      reason: '${summary.errorCount} errors across the isolated files',
    );
  });
}
