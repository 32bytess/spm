import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/constants/app_constants.dart';
import 'package:spm/src/core/errors/failures.dart';
import 'package:spm/src/core/injection/cli_service_locator.dart';
import 'package:spm/src/core/loggor/logger.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_event.dart';
import 'package:spm/src/features/analysis/domain/use_cases/analyze_use_case.dart';
import 'package:spm/src/features/analysis/domain/use_cases/save_result_use_case.dart';

class AnalysisCommand extends Command<int> {
  final AnalyzeUseCase? _analyzeUseCase;
  final SaveResultUseCase? _saveResultUseCase;

  @override
  final name = 'analyze';

  @override
  final description = 'Analyze Dart files and extract rebuild scope metrics.';
  AnalysisCommand({
    AnalyzeUseCase? analyzeUseCase,
    SaveResultUseCase? saveResultUseCase,
  }) : _analyzeUseCase = analyzeUseCase,
       _saveResultUseCase = saveResultUseCase {
    argParser
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enable verbose output.',
        negatable: false,
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output file path for JSONL results (required).',
        mandatory: true,
      )
      ..addMultiOption(
        'scope-types',
        abbr: 's',
        help:
            'Rebuild scope types to extract. Defaults to all of: '
            '${AppConstants.rebuildScopeTypes.join(', ')}.',
        allowed: AppConstants.rebuildScopeTypes,
      );
  }

  @override
  Future<int> run() async {
    SpmLogger.logMessage('Starting analysis...');

    final directories = argResults!.rest;

    if (directories.isEmpty) {
      usageException('At least one directory must be specified.');
    }

    final repoDirs = directories
        .map((a) => p.normalize(p.absolute(a)))
        .toList();
    final missingDirs = repoDirs.where((path) => !Directory(path).existsSync());
    if (missingDirs.isNotEmpty) {
      usageException(
        'Analysis directories do not exist: ${missingDirs.join(', ')}',
      );
    }
    final verbose = argResults!['verbose'] as bool;
    final outputPath = argResults!['output'] as String;
    final selectedTypes = argResults!['scope-types'] as List<String>;
    // No selection means every scope type; an explicit list narrows it.
    final scopeTypes = selectedTypes.isEmpty ? null : selectedTypes.toSet();

    if (verbose) {
      SpmLogger.logMessage('Analyzing directories: ${repoDirs.join(', ')}');
      SpmLogger.logMessage('Writing results to: $outputPath');
      SpmLogger.logMessage('Scope types: ${scopeTypes?.join(', ') ?? 'all'}');
    }

    final analyzer = _analyzeUseCase ?? AnalysisDI.analyzeUseCase;
    final save = _saveResultUseCase ?? AnalysisDI.saveResultUseCase;
    final dataController = StreamController<AnalysisDataEvent>();
    final pendingSave = save.call(
      analysisResult: dataController.stream,
      filePath: outputPath,
    );
    var analysisFailed = false;

    await for (final event in analyzer.call(repoDirs, scopeTypes: scopeTypes)) {
      event.fold(
        (Failure failure) {
          analysisFailed = true;
          SpmLogger.logMessage(
            'Analysis error: ${failure.message}',
            isError: true,
          );
        },
        (result) {
          if (result is AnalysisSummaryEvent) {
            SpmLogger.logMessage(
              'Scanned ${result.filesScanned} files '
              '(${result.filesSkipped} skipped with compile errors); '
              'found ${result.scopesFound} rebuild scopes '
              '(${_formatScopeBreakdown(result.scopesByType)}); '
              'kept ${result.keptRows} rows.',
            );
          } else if (result is AnalysisDataEvent) {
            if (verbose) {
              SpmLogger.logMessage(
                'Extracted data for instance ${result.result.instanceId} in file ${result.result.filePath}',
              );
            }
            dataController.add(result);
          }
        },
      );
    }

    await dataController.close();

    // The sink is flushed after the stream's done event; the save future
    // must complete before main() calls exit() or rows are lost.
    final saveOutcome = await pendingSave;
    return saveOutcome.fold((Failure failure) {
      SpmLogger.logMessage(
        'Failed to write results: ${failure.message}',
        isError: true,
      );
      return 1;
    }, (_) => analysisFailed ? 1 : 0);
  }

  /// `State: 12, BlocBuilder: 3`, most frequent type first.
  String _formatScopeBreakdown(Map<String, int> scopesByType) {
    if (scopesByType.isEmpty) return 'none';
    final entries = scopesByType.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }
}
