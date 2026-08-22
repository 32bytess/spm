import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/extractors/transplant_extractor.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/inline_budget.dart';
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// What happens when a scope reaches more third-party UI than it may carry.
///
/// Repo-local inlining has never needed a cap, because its closure is bounded
/// by the repository. Third-party inlining has no such bound: a widget whose
/// supertype chain is UI gets carried, and from there the crawl walks into the
/// package's own machinery. The cap is what keeps a scope holding one
/// `BlocBuilder` from emitting the package.
///
/// Truncation is not silent. A truncated row describes a smaller tree than the
/// code it came from builds, which is the thing the feature exists to avoid, so
/// the row says it happened.
const String _scopeSource = '''
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class BudgetHost extends StatefulWidget {
  const BudgetHost({super.key});

  @override
  State<BudgetHost> createState() => BudgetHostState();
}

class BudgetHostState extends State<BudgetHost> {
  @override
  Widget build(BuildContext context) => Column(
    children: [const FancyButton(label: 'go'), const FancyPanel()],
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
      prefix: 'spm_third_party_budget',
    );
    outputDir = Directory.systemTemp
        .createTempSync('spm_third_party_budget_out')
        .path;
    jsonlPath = p.join(outputDir, 'map.jsonl');

    // One declaration is all this scope may carry, so the second widget it
    // reaches has to take the stand-in path.
    final events =
        await IsolationDataSourceImpl(
              extractor: TransplantExtractor(
                newBudget: () => InlineBudget(maxDeclarations: 1),
              ),
            )
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
        .firstWhere((f) => f.path.contains('BudgetHostState'))
        .readAsStringSync();

    row = File(jsonlPath)
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .firstWhere((r) => r['name'] == 'BudgetHostState');
  });

  tearDownAll(() {
    project.delete();
    final dir = Directory(outputDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('the row says the closure was cut short', () {
    expect(row['thirdPartyInlineTruncated'], isTrue);
    expect(row['inlinedThirdPartyDeclarations'], 1);
  });

  test('what fits is still carried whole', () {
    expect(isolated, contains('class FancyButton extends StatelessWidget'));
    expect(isolated, contains('FancyRow(label: label)'));
  });

  test('what does not fit falls back to a stand-in', () {
    // A hollowed-out widget, not a broken file. The stand-in still reads as a
    // widget, so the allocation is counted where it always was.
    expect(isolated, isNot(contains("Text('panel")));
    expect(isolated, contains('class FancyPanel extends StatelessWidget'));
  });

  test('the budget never reopens once it is spent', () {
    // `InlineBudget.take` latches, so a small declaration arriving after a
    // large one blew the cap cannot slip through. Without that, the output
    // depends on the order the crawl happened to reach things in.
    expect(row['inlinedThirdPartyDeclarations'], 1);
  });

  test('a truncated run still analyses clean', () {
    expect(summary.verifiedCount, greaterThan(0));
    expect(
      summary.cleanCount,
      summary.verifiedCount,
      reason: '${summary.errorCount} errors across the isolated files',
    );
  });
}
