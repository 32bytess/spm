import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:test/test.dart';

/// The output has to run, not only analyse.
///
/// Every number `spm isolate` reported used to stop at `errorCount == 0`, and
/// three deliberate decisions guaranteed that a clean-analysing file threw
/// before its first frame: unassigned `late` seeds read from `initState`,
/// stand-in bodies that threw `UnimplementedError`, and unassigned `late dynamic`
/// globals for every name the analyzer never resolved. The clean rate is an
/// upper bound on how many files reach a frame, and reaching a frame is what
/// the comparison actually consumes.
void main() {
  late Directory output;
  late Map<String, String> sources;
  late List<Map<String, dynamic>> rows;

  setUpAll(() async {
    output = Directory.systemTemp.createTempSync('spm_runnable_defaults');
    final jsonl = p.join(output.path, 'map.jsonl');

    await IsolationDataSourceImpl()
        .isolate(
          directories: [p.absolute('test/fixtures/isolation')],
          outputDir: output.path,
          jsonlPath: jsonl,
        )
        .toList();

    sources = {
      for (final file
          in Directory(output.path)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        file.path: file.readAsStringSync(),
    };
    rows = const LineSplitter()
        .convert(File(jsonl).readAsStringSync())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
  });

  tearDownAll(() {
    if (output.existsSync()) output.deleteSync(recursive: true);
  });

  test('no stand-in body throws', () {
    // A call on a stand-in during build used to crash the frame. Nothing here
    // is measured: the features come from the shape of the build tree, and that
    // shape is fixed before any of this executes.
    //
    // Only the emitted regions are checked. Everything above them is source the
    // transplant copied out of the repository, and a throw the code itself
    // wrote is the code's own.
    for (final entry in sources.entries) {
      expect(
        _emitted(entry.value),
        isNot(contains('throw UnimplementedError()')),
        reason: entry.key,
      );
    }
  });

  test('no binding is left unassigned unless the row says so', () {
    // `late` with no initialiser is a LateInitializationError on the first read,
    // and the reads are in `initState` and `build`. Where no value of the
    // binding's type can be built the old form stays, and then the name is
    // reported rather than the file failing anonymously.
    final reported = {
      for (final row in rows)
        row['isolatedPath'] as String:
            (row['unseededBindings'] as List?)?.cast<String>() ?? const [],
    };
    for (final entry in sources.entries) {
      final unseeded = reported[entry.key] ?? const <String>[];
      final dangling = RegExp(
        r'^\s*late [^;]*?\b(\w+);',
        multiLine: true,
      ).allMatches(_emitted(entry.value)).map((m) => m.group(1)!).toSet();
      // Lifted parameter fields are assigned in the generated `initState`, so
      // they are `late` on purpose and are not a binding anyone reads first.
      final unexplained = dangling
          .where((name) => !unseeded.contains(name))
          .where((name) => !entry.value.contains('$name = fixture'))
          .where((name) => !entry.value.contains('$name = ${name}Value'))
          .toSet();
      expect(unexplained, isEmpty, reason: entry.key);
    }
  });

  test('the stub is declared exactly when something used it', () {
    for (final entry in sources.entries) {
      final declares = entry.value.contains('class _Stub {');
      final uses = entry.value.contains('const _Stub()');
      expect(declares, uses, reason: entry.key);
    }
  });

  test('every scope gets a constructor a caller can use', () {
    // The copied constructor is the commit's own, so a scope whose widget
    // declared `required this.arguments` cannot be written as
    // `GeneratedWidget()`. Knowing this scope's field names and building a
    // value for each is a second fix point, outside the fixture block and
    // different for every scope, which is what the fixture constructor removes.
    for (final row in rows) {
      expect(row['fixtureConstructor'], isTrue, reason: '${row["name"]}');
    }
    for (final entry in sources.entries) {
      expect(
        entry.value,
        contains('GeneratedWidget.fixture({super.key})'),
        reason: entry.key,
      );
    }
  });

  test('the copied constructor stays beside it', () {
    // It is part of the commit's source, and the fidelity audit measures
    // against it.
    final withFields = sources.entries.firstWhere(
      (e) => e.key.contains('_WidgetWithFieldsState'),
    );
    expect(withFields.value, contains('const GeneratedWidget({'));
    expect(withFields.value, contains('GeneratedWidget.fixture({super.key})'));
  });

  test('the fixture block says what it is for', () {
    final seeded = sources.values.firstWhere(
      (source) => source.contains('fixtureHeading'),
    );
    expect(seeded, contains('Fixture block.'));
    expect(seeded, contains('Collections are generated empty'));
  });
}

/// The part of an isolated file the emitters wrote.
///
/// Everything above the first banner is source copied out of the repository, so
/// a `late` binding or a throwing body there belongs to the code under study
/// rather than to the transplant.
String _emitted(String source) {
  const banners = [
    '// Fixture block.',
    '// Declaration-only stand-ins for symbols',
    '// Stand-ins for references the analyzer could not resolve',
    '// Stands in for values this file cannot reproduce',
  ];
  var start = source.length;
  for (final banner in banners) {
    final index = source.indexOf(banner);
    if (index >= 0 && index < start) start = index;
  }
  return source.substring(start);
}
