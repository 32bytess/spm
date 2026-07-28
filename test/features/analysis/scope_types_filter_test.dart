import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/core/injection/cli_service_locator.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_event.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

void main() {
  final fixtureDir = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'analysis',
    'rebuild_scopes',
  );

  late AnalysisSummaryEvent? summary;

  Future<List<AnalysisResultEntity>> analyze({Set<String>? scopeTypes}) async {
    summary = null;
    final rows = <AnalysisResultEntity>[];
    await for (final event in AnalysisDI.analyzeUseCase.call([
      fixtureDir,
    ], scopeTypes: scopeTypes)) {
      event.fold((failure) => fail(failure.message), (result) {
        if (result is AnalysisDataEvent) rows.add(result.result);
        if (result is AnalysisSummaryEvent) summary = result;
      });
    }
    return rows;
  }

  tearDown(AnalysisDI.reset);

  test('no filter keeps every scope type', () async {
    final rows = await analyze();
    expect(
      rows.map((r) => r.scopeType).toSet(),
      equals({'State', 'ConsumerWidget', 'BlocBuilder', 'Obx'}),
    );
  });

  test('a filter keeps only the requested types', () async {
    final rows = await analyze(scopeTypes: {'State'});
    expect(rows.map((r) => r.scopeType).toSet(), equals({'State'}));
    expect(rows.map((r) => r.scopeName), equals(['_BuilderHostState']));
  });

  test('the summary reports discovery before filtering', () async {
    final rows = await analyze(scopeTypes: {'BlocBuilder', 'Obx'});

    expect(summary, isNotNull);
    expect(rows, hasLength(3));
    expect(summary!.keptRows, equals(3));
    expect(
      summary!.scopesFound,
      equals(5),
      reason: 'filtering must not hide what the scan actually found',
    );
    expect(
      summary!.scopesByType,
      equals({'ConsumerWidget': 1, 'State': 1, 'BlocBuilder': 2, 'Obx': 1}),
    );
  });
}
