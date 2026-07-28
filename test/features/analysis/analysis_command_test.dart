import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartz/dartz.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/errors/failures.dart';
import 'package:spm/src/core/injection/cli_service_locator.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/analysis/domain/repositories/analysis_repository.dart';
import 'package:spm/src/features/analysis/domain/use_cases/analyze_use_case.dart';
import 'package:spm/src/features/analysis/domain/use_cases/save_result_use_case.dart';
import 'package:spm/src/features/analysis/presentation/analysis_command.dart';
import 'package:spm/src/runner.dart';
import 'package:test/test.dart';

void main() {
  setUp(AnalysisDI.reset);
  tearDown(AnalysisDI.reset);

  test('rejects a missing analysis directory', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'spm_analysis_command_',
    );
    try {
      final missingInput = p.join(tempDir.path, 'missing');
      final output = p.join(tempDir.path, 'result.jsonl');

      final exitCode = await SpmRunner().run([
        'analyze',
        '--output',
        output,
        missingInput,
      ]);

      expect(exitCode, equals(64));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('returns non-zero when analysis fails but saving succeeds', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'spm_analysis_failure_',
    );
    final repository = _FailingAnalysisRepository();
    final runner = CommandRunner<int>('spm', 'test')
      ..addCommand(
        AnalysisCommand(
          analyzeUseCase: AnalyzeUseCase(repository),
          saveResultUseCase: SaveResultUseCase(repository),
        ),
      );

    try {
      final exitCode = await runner.run([
        'analyze',
        '--output',
        p.join(tempDir.path, 'result.jsonl'),
        tempDir.path,
      ]);

      expect(exitCode, equals(1));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}

class _FailingAnalysisRepository implements AnalysisRepository {
  @override
  AnalysisStream analyze(
    RepositoryPaths repoDirs, {
    Set<String>? scopeTypes,
  }) async* {
    yield Left(AnalysisFailure('synthetic analysis failure'));
  }

  @override
  SaveResult saveResults(
    AnalysisDataEventStream analysisResult,
    OutputPath filePath,
  ) async {
    await analysisResult.drain<void>();
    return const Right(null);
  }
}
