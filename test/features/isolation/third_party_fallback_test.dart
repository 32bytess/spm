import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// What happens when carrying a package's code is the worse answer.
///
/// Inlining is right often enough to be the default and not often enough to be
/// unconditional. A package's own generics are the recurring reason it fails:
/// `FancyTypedBox<T extends FancyModel>` type-checks in the app because the
/// class passed for `T` really does implement `FancyModel`, and in an isolated
/// file that class is a stand-in with no supertype at all.
///
/// Rather than guess which packages behave this way, the run analyses both
/// answers and keeps the one with fewer errors. That makes the guarantee exact:
/// no scope ends up worse off than standing everything in would have left it,
/// which is what matters, because `spm analyze` skips any file carrying an
/// error.
/// In a file of its own, which is what makes it a stand-in.
///
/// A class in the scope's own file is copied across whole, `implements` clause
/// and all, and would satisfy the bound. Across a file boundary the transplant
/// applies its UI filter, this builds nothing, and what lands in the output is
/// `class LocalModel {}` with no supertype at all. That is the same thing that
/// happens to the `ChangeNotifier` subclasses a real app hands to `provider`.
const String _modelSource = '''
import 'package:ui_kit/ui_kit.dart';

class LocalModel implements FancyModel {
  const LocalModel();

  @override
  String get title => 'local';
}
''';

const String _scopeSource = '''
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import 'model.dart';

class FallbackHost extends StatefulWidget {
  const FallbackHost({super.key});

  @override
  State<FallbackHost> createState() => FallbackHostState();
}

class FallbackHostState extends State<FallbackHost> {
  @override
  Widget build(BuildContext context) => const Column(
    children: [FancyTypedBox<LocalModel>(value: LocalModel())],
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
      sources: {'scope.dart': _scopeSource, 'model.dart': _modelSource},
      extraPackages: {'ui_kit': p.join(fixtures, 'ui_kit')},
      prefix: 'spm_third_party_fallback',
    );
    outputDir = Directory.systemTemp
        .createTempSync('spm_third_party_fallback_out')
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
        .firstWhere((f) => f.path.contains('FallbackHostState'))
        .readAsStringSync();

    row = File(jsonlPath)
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .firstWhere((r) => r['name'] == 'FallbackHostState');
  });

  tearDownAll(() {
    project.delete();
    final dir = Directory(outputDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('the file that is kept is the one that analyses', () {
    expect(row['errorCount'], 0);
    expect(summary.cleanCount, summary.verifiedCount);
  });

  test('the row says the tree was given up to get there', () {
    // A reverted row measures a smaller tree than the same scope does in place.
    // The count alone would not show it, because a reverted row carries none.
    expect(row['thirdPartyInlineReverted'], isTrue);
    expect(row.containsKey('inlinedThirdPartyDeclarations'), isFalse);
  });

  test('the kept file is the stand-in version, not a patched inline', () {
    // Reverting means re-extracting with the flag off, not editing the inlined
    // output until it compiles. A half-carried tree would measure something
    // neither version measures.
    expect(isolated, contains('const SizedBox.shrink()'));
    expect(isolated, isNot(contains('Text(value.title)')));
  });
}
