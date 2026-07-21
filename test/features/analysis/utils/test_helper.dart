import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:spm/core/injection/cli_service_locator.dart';

import 'package:spm/features/analysis/domain/entities/analysis_event.dart';
import 'package:spm/features/analysis/domain/entities/analysis_result_entity.dart';

/// Runs the analyzer on a specific fixture file or folder and returns results.
Future<List<AnalysisResultEntity>> getResultsForFixture(
  String relativePath,
) async {
  final fullPath = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'analysis',
    relativePath,
  );

  final isFile = File(fullPath).existsSync();
  final isDir = Directory(fullPath).existsSync();
  if (!isFile && !isDir) {
    throw Exception('Fixture not found (file or directory): $fullPath');
  }

  final analyzeUseCase = AnalysisDI.analyzeUseCase;

  final results = <AnalysisResultEntity>[];
  await for (final event in analyzeUseCase.call([fullPath])) {
    event.fold((failure) {}, (result) {
      if (result is AnalysisDataEvent) {
        results.add(result.result);
      }
    });
  }

  return results;
}
