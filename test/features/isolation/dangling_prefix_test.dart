import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// A prefix from a package the isolated file may not import.
///
/// The rescan at the end of the transplant restores an `as` prefix whose import
/// the isolated file is allowed to keep, and `dart:math as math` qualifies while
/// `package:path/path.dart as pp` does not. The prefix was then left dangling in
/// the output, which is an undefined name and error severity.
///
/// Dropping the SDK filter would be the wrong repair. The output is analysed and
/// compiled against a package config supplying `package:flutter` and nothing
/// else, so a restored `import 'package:path/path.dart' as pp;` is
/// `uri_does_not_exist`: still error severity, still skipped by `spm analyze`,
/// and it would spend the one clear result that no isolated file reports an
/// unresolved import.
const String _scopeSource = '''
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pp;

class PrefixHost extends StatefulWidget {
  const PrefixHost({super.key});

  @override
  State<PrefixHost> createState() => PrefixHostState();
}

class PrefixHostState extends State<PrefixHost> {
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(pp.join('a', 'b')),
      Text('\${math.max(1, 2)}'),
    ],
  );
}
''';

void main() {
  late TempProject project;
  late Directory output;
  late String isolated;
  late Map<String, dynamic> row;

  setUpAll(() async {
    project = TempProject.create(
      sources: {'prefixes.dart': _scopeSource},
      prefix: 'spm_dangling_prefix',
    );
    output = Directory.systemTemp.createTempSync('spm_dangling_prefix_out');
    final jsonl = p.join(output.path, 'map.jsonl');

    await IsolationDataSourceImpl()
        .isolate(
          directories: [project.path],
          outputDir: output.path,
          jsonlPath: jsonl,
        )
        .toList();

    isolated = Directory(
      p.join(output.path, 'State'),
    ).listSync().whereType<File>().single.readAsStringSync();
    row =
        jsonDecode(
              const LineSplitter()
                  .convert(File(jsonl).readAsStringSync())
                  .first,
            )
            as Map<String, dynamic>;
  });

  tearDownAll(() {
    project.delete();
    if (output.existsSync()) output.deleteSync(recursive: true);
  });

  test('an SDK prefix is still restored as an import', () {
    expect(isolated, contains("import 'dart:math' as math;"));
  });

  test('a package prefix becomes a stand-in rather than an import', () {
    // A dynamic receiver makes `pp.join(...)` compile with no import at all,
    // which is what every other unresolved third-party name already does.
    expect(isolated, isNot(contains("import 'package:path/path.dart'")));
    expect(isolated, contains('dynamic pp = const _Stub();'));
  });

  test('the file still reports no unresolved import', () {
    // The result the SDK filter exists to protect, and the one a restored
    // import would have spent.
    expect(row['unresolvedImports'], isNull);
    expect(row['verified'], isTrue);
    expect(row['errorCount'], 0);
  });
}
