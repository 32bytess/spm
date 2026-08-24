import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:test/test.dart';

/// What the image rewrite keeps, and the one thing it still cannot.
void main() {
  late Directory output;
  late String isolated;
  late Map<String, dynamic> row;

  setUpAll(() async {
    output = Directory.systemTemp.createTempSync('spm_image_rewrite');
    final jsonl = p.join(output.path, 'map.jsonl');

    await IsolationDataSourceImpl()
        .isolate(
          directories: [p.absolute('test/fixtures/isolation')],
          outputDir: output.path,
          jsonlPath: jsonl,
        )
        .toList();

    isolated = Directory(p.join(output.path, 'State'))
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.contains('_ImageHostState'))
        .readAsStringSync();
    row = const LineSplitter()
        .convert(File(jsonl).readAsStringSync())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .firstWhere((r) => '${r['isolatedPath']}'.contains('_ImageHostState'));
  });

  tearDownAll(() {
    if (output.existsSync()) output.deleteSync(recursive: true);
  });

  test('an errorBuilder subtree survives the rewrite', () {
    // `errorBuilder` is a widget-returning closure, and in place
    // `BuildMetricsVisitor` walks the argument list and counts what it builds.
    // Replacing the whole node erased it, so a revision that adds an
    // `errorBuilder` produced a nonzero in-place delta and a zero transplant
    // delta: a delta erased.
    expect(isolated, contains('errorBuilder:'));
    expect(isolated, contains('Icon(Icons.error)'));
    expect(isolated, contains("Text('failed')"));
  });

  test('the other arguments of the construction survive too', () {
    expect(isolated, contains('width: 24'));
  });

  test('the source is the only thing substituted', () {
    expect(isolated, isNot(contains('https://example.invalid')));
    // The constructor name and the source argument, and nothing else. The
    // formatter is free to break the call across lines, so the two are matched
    // separately.
    expect(isolated, contains('Image.asset('));
    expect(isolated, isNot(contains('Image.network(')));
    expect(isolated, contains("'assets/placeholder.png'"));
  });

  test('a provider stays a provider', () {
    // `NetworkImage` is an `ImageProvider`, so in place it lands in
    // `valueObjectAllocCount`. Rewritten to `Image.asset(...)` it became a
    // widget: the same source moved into `treeNonConstWidgetCount` and added a
    // level of depth, and two features diverged in opposite directions wherever
    // an image provider appeared. It also put a widget in a provider-typed slot,
    // which `CircleAvatar(backgroundImage:)` rejects.
    expect(
      isolated,
      contains("backgroundImage: const AssetImage('assets/placeholder.png')"),
    );
    expect(isolated, contains('DecorationImage('));
    expect(isolated, contains('fit: BoxFit.cover'));
  });

  test('loadingBuilder is dropped, and says so where it stood', () {
    // `Image.asset` has no such argument. It is the one part of an image
    // construction that still cannot come across, so it is marked in the file
    // and counted on the row rather than lost silently.
    expect(isolated, isNot(contains('loadingBuilder:')));
    expect(isolated, contains('spm: loadingBuilder dropped'));
    expect(row['droppedLoadingBuilders'], 1);
  });

  test('the file still analyses clean', () {
    expect(row['errorCount'], 0);
  });
}
