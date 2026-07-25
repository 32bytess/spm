import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/injection/cli_service_locator.dart';
import 'package:spm/src/core/loggor/logger.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';

/// CLI command to trigger the isolation process.
///
/// Usage: `spm isolate -o <output-dir> [directories...]`
class IsolateCommand extends Command<int> {
  @override
  final name = 'isolate';

  @override
  final description =
      'Extract rebuild scopes from repositories and transplant them into State classes.';

  IsolateCommand() {
    argParser
      ..addOption(
        'output-dir',
        abbr: 'o',
        help: 'Directory to save isolated State classes.',
        mandatory: true,
      )
      ..addOption(
        'jsonl',
        abbr: 'j',
        help:
            'Output JSONL file for the mapping (original path -> isolated path).',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enable verbose output.',
        negatable: false,
      );
  }

  @override
  Future<int> run() async {
    final directories = argResults!.rest;

    if (directories.isEmpty) {
      usageException('At least one directory must be specified.');
    }

    final repoDirs = directories
        .map((a) => p.normalize(p.absolute(a)))
        .toList();
    final outputDir = p.normalize(
      p.absolute(argResults!['output-dir'] as String),
    );
    final jsonlPath = argResults!['jsonl'] as String?;
    final verbose = argResults!['verbose'] as bool;

    if (verbose) {
      SpmLogger.logMessage('Starting isolation...');
      SpmLogger.logMessage('Repositories: ${repoDirs.join(', ')}');
      SpmLogger.logMessage('Output Directory: $outputDir');
      if (jsonlPath != null) SpmLogger.logMessage('Mapping JSONL: $jsonlPath');
    }

    // Invoke the use case through the service locator
    final stream = IsolationDI.isolationUseCase.call(
      directories: repoDirs,
      outputDir: outputDir,
      jsonlPath: jsonlPath,
    );

    await for (final event in stream) {
      final shouldExit = event.fold(
        (failure) {
          SpmLogger.logMessage(
            'Isolation error: ${failure.message}',
            isError: true,
          );
          return true;
        },
        (isolationEvent) {
          if (isolationEvent is IsolationDataEvent) {
            if (verbose) {
              SpmLogger.logMessage(
                'Isolated ${isolationEvent.name} (${isolationEvent.type}) from ${isolationEvent.originalPath}',
              );
            }
          } else if (isolationEvent is IsolationSummaryEvent) {
            SpmLogger.logMessage(
              'Successfully isolated ${isolationEvent.isolatedCount} scopes into ${isolationEvent.outputDir}',
            );
          }
          return false;
        },
      );

      if (shouldExit) return 1;
    }

    return 0;
  }
}
