import 'package:spm/src/features/isolation/data/data_sources/helpers/inline_budget.dart';
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
        'inline-third-party',
        help:
            'Carry a third-party widget\'s own tree into the isolated file '
            'instead of standing it in. On by default: a stand-in widget has '
            'an empty build, so the isolated file otherwise describes a tree '
            'the app never built. Note that `analyze` cannot reach a package '
            'widget\'s body in place, so a carried row counts more than the '
            'in-place row for the same scope. Pass --no-inline-third-party for '
            'smaller output and shorter runs.',
        defaultsTo: true,
      )
      ..addOption(
        'inline-max-declarations',
        help:
            'How many third-party declarations one scope may carry. The cap is '
            'a reporting number rather than a limit to aim at: `analyze` now '
            'walks a package library in place with no cap at all, so a scope '
            'that exhausts this one undercounts against the row it is compared '
            'with, and it is marked with thirdPartyInlineTruncated so it can be '
            'screened out.',
        defaultsTo: '${InlineBudget.defaultMaxDeclarations}',
      )
      ..addOption(
        'inline-max-characters',
        help:
            'How much third-party source, in characters, one scope may carry.',
        defaultsTo: '${InlineBudget.defaultMaxCharacters}',
      )
      ..addFlag(
        'prune-non-rebuild',
        help:
            'Leave out the code a rebuild cannot run: the body of an '
            'onPressed, onChanged or validator closure, and any member of the '
            'scope\'s class that build() cannot reach. On by default, because '
            '`analyze` already prunes exactly this before it counts anything, '
            'so none of it can move a feature. Carrying it makes the crawl '
            'pull in whole navigation targets and stand in for the services '
            'they call, and a file that then fails to analyse is skipped '
            'outright. What initState and didChangeDependencies seeded moves '
            'to the fixture block, so the values survive the drop. Pass '
            '--no-prune-non-rebuild to reproduce the output of earlier '
            'versions.',
        defaultsTo: true,
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
    final inlineThirdParty = argResults!['inline-third-party'] as bool;
    final inlineMaxDeclarations = _positiveInt(
      argResults!['inline-max-declarations'] as String,
      InlineBudget.defaultMaxDeclarations,
    );
    final inlineMaxCharacters = _positiveInt(
      argResults!['inline-max-characters'] as String,
      InlineBudget.defaultMaxCharacters,
    );
    final pruneNonRebuild = argResults!['prune-non-rebuild'] as bool;

    if (verbose) {
      SpmLogger.logMessage('Starting isolation...');
      SpmLogger.logMessage('Repositories: ${repoDirs.join(', ')}');
      SpmLogger.logMessage('Output Directory: $outputDir');
      if (jsonlPath != null) SpmLogger.logMessage('Mapping JSONL: $jsonlPath');
      SpmLogger.logMessage(
        inlineThirdParty
            ? 'Third-party widget trees: carried'
            : 'Third-party widget trees: stood in for',
      );
      SpmLogger.logMessage(
        pruneNonRebuild
            ? 'Code a rebuild cannot run: pruned'
            : 'Code a rebuild cannot run: carried',
      );
    }

    // Invoke the use case through the service locator
    final stream = IsolationDI.isolationUseCase.call(
      directories: repoDirs,
      outputDir: outputDir,
      jsonlPath: jsonlPath,
      inlineThirdParty: inlineThirdParty,
      inlineMaxDeclarations: inlineMaxDeclarations,
      inlineMaxCharacters: inlineMaxCharacters,
      pruneNonRebuild: pruneNonRebuild,
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
            if (isolationEvent.verifiedCount > 0) {
              // The count that decides whether the output is usable: `spm
              // analyze` skips any file carrying an error.
              SpmLogger.logMessage(
                '${isolationEvent.cleanCount} of ${isolationEvent.verifiedCount} '
                'analyse clean (${isolationEvent.errorCount} errors in total).',
              );
            }
            if (isolationEvent.revertedCount > 0) {
              // Said out loud because each of these describes a smaller tree
              // than the same scope does in place.
              SpmLogger.logMessage(
                '${isolationEvent.revertedCount} scopes gave back the '
                'third-party source they carried, so each measures a smaller '
                'tree than the code it came from builds.',
              );
            }
          }
          return false;
        },
      );

      if (shouldExit) return 1;
    }

    return 0;
  }

  /// Reads a cap, falling back to [fallback] on anything unusable.
  ///
  /// A mistyped cap must not silently become zero, which would stand every
  /// third-party declaration in and look like a change in the emitter.
  static int _positiveInt(String value, int fallback) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      SpmLogger.logMessage(
        'Ignoring unusable cap "$value"; using $fallback.',
        isError: true,
      );
      return fallback;
    }
    return parsed;
  }
}
