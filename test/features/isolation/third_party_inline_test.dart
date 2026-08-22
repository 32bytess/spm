import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// Exercises the default: a third-party widget's own tree is carried into the
/// isolated file rather than stood in for.
///
/// The reason it is the default is that a stand-in widget has an empty `build`,
/// so an isolated file full of them describes a tree the app never built and
/// cannot be read or run as the scope it came from.
///
/// It is NOT for agreement with `spm analyze` on the original project, which is
/// the obvious guess and the wrong one. `TreeExtractor._indexLibrary` asks
/// `AnalysisContextCollection.contextFor` for the child's file and that throws
/// for anything under the pub cache, so the in-place row never counted a
/// package widget's subtree either. Carrying it makes the isolated row larger
/// than the in-place one, not equal to it.
///
/// The scope is written at run time for the same reason as the shim suite: a
/// checked-in file importing `package:ui_kit` resolves for nobody but this
/// test.
const String _scopeSource = '''
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class InlineHost extends StatefulWidget {
  const InlineHost({super.key});

  @override
  State<InlineHost> createState() => InlineHostState();
}

class InlineHostState extends State<InlineHost> {
  static const FancySpec _spec = FancySpec(weight: 2);
  final FancyController _controller = FancyController();

  @override
  void initState() {
    super.initState();
    _controller.tap();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const FancyButton(label: 'go'),
      const FancyPanel(),
      Text('\${_spec.weight}'),
    ],
  );
}
''';

void main() {
  late TempProject project;
  late String outputDir;
  late String jsonlPath;
  late String isolated;
  late Map<String, dynamic> row;
  late IsolationSummaryEvent summary;

  setUpAll(() async {
    final fixtures = p.absolute('test/fixtures/isolation_third_party');
    project = TempProject.create(
      sources: {'scope.dart': _scopeSource},
      extraPackages: {'ui_kit': p.join(fixtures, 'ui_kit')},
      prefix: 'spm_third_party_inline',
    );
    outputDir = Directory.systemTemp
        .createTempSync('spm_third_party_inline_out')
        .path;
    jsonlPath = p.join(outputDir, 'map.jsonl');

    final events = await IsolationDataSourceImpl()
        .isolate(
          directories: [project.path],
          outputDir: outputDir,
          jsonlPath: jsonlPath,
        )
        .toList();
    summary = events.last as IsolationSummaryEvent;

    isolated = Directory(p.join(outputDir, 'State'))
        .listSync(recursive: false)
        .whereType<File>()
        .firstWhere((f) => f.path.contains('InlineHostState'))
        .readAsStringSync();

    row = File(jsonlPath)
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .firstWhere((r) => r['name'] == 'InlineHostState');
  });

  tearDownAll(() {
    project.delete();
    final dir = Directory(outputDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('still never imports the third-party package back', () {
    // Carrying the code is not the same as depending on the package. The
    // isolated file is meant to stand alone against the Flutter SDK, and that
    // has not changed.
    expect(isolated, isNot(contains('package:ui_kit')));
  });

  test('a third-party widget brings its real build body', () {
    // The whole point. `FancyButton.build` returns `FancyRow(label: label)`,
    // and an isolated file that says `SizedBox.shrink()` instead is not a copy
    // of this scope, it is a copy of a different one.
    expect(isolated, contains('class FancyButton extends StatelessWidget'));
    expect(isolated, contains('FancyRow(label: label)'));
  });

  test('the crawl recurses into what an inlined widget builds', () {
    // `FancyRow` is reached only from `FancyButton`'s body, so it comes across
    // only if an inlined third-party widget is walked the way a repo-local one
    // is. Stopping at the first hop would leave `FancyRow` undefined.
    expect(isolated, contains('class FancyRow extends StatelessWidget'));
    expect(isolated, contains('Text(label)'));
  });

  test('a private class in the package file comes across', () {
    // The same-file lookup used to be gated on the declaring file being inside
    // the project, which a package unit fails even while it is the unit being
    // walked. `_FancyDot` is reachable no other way.
    expect(isolated, contains('class _FancyDot extends StatelessWidget'));
  });

  test('a third-party StatefulWidget brings its State', () {
    // `TreeExtractor` measures the `State`'s build body, not the widget's, so a
    // `StatefulWidget` carried without its companion contributes nothing and
    // names a type nothing declares.
    expect(isolated, contains('class FancyPanel extends StatefulWidget'));
    expect(
      isolated,
      contains('class _FancyPanelState extends State<FancyPanel>'),
    );
    expect(isolated, contains("Text('panel"));
  });

  test('a name material exports is stood in for, not carried', () {
    // `ui_kit` declares its own `Divider`. Inlining it would put a body behind
    // a name the transplanted code may have meant Flutter's, and that body is
    // then counted under every `Divider()` in the scope. Under-counting a name
    // clash is recoverable; inventing widgets under one is not.
    expect(isolated, isNot(contains("Text('ui_kit divider')")));
  });

  test('a third-party value object is still stood in for', () {
    // Inlining follows what builds UI. A value object builds nothing, so
    // carrying it would be pure output size.
    expect(isolated, contains('class FancySpec'));
    expect(isolated, isNot(contains('class FancySpec extends')));
    expect(isolated, contains('int get weight'));
  });

  test(
    'a large third-party type still carries only what the scope reaches',
    () {
      // The stand-in path is unchanged for everything that is not UI, including
      // the member-scoped rule that keeps a forty-member controller small.
      expect(isolated, contains('class FancyController'));
      expect(isolated, contains('void tap()'));
      expect(isolated, isNot(contains('void pad0()')));
    },
  );

  test('the row records how much third-party source it carried', () {
    // A row that carried a package's widgets and one that stood them in are
    // different measurements. Nothing else in the JSONL says which happened.
    expect(row['inlinedThirdPartyDeclarations'], isA<int>());
    expect(row['inlinedThirdPartyDeclarations'], greaterThan(0));
    expect(row.containsKey('thirdPartyInlineTruncated'), isFalse);
  });

  test('every isolated file analyses clean', () {
    // The guard rail. `spm analyze` skips any file carrying an error-severity
    // diagnostic, so inlining that produces unanalysable output is worse than
    // the stand-in it replaced.
    expect(summary.verifiedCount, greaterThan(0));
    expect(
      summary.cleanCount,
      summary.verifiedCount,
      reason: '${summary.errorCount} errors across the isolated files',
    );
  });
}
