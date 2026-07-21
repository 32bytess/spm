import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:spm/core/errors/failures.dart';
import 'package:spm/core/injection/injection_di.dart';
import 'package:spm/core/loggor/logger.dart';
import 'package:spm/features/injection/domain/entities/injection_mode.dart';
import 'package:spm/features/injection/domain/entities/run_app_event.dart';
import 'package:spm/features/injection/domain/entities/run_with_injection_event.dart';
import 'package:spm/features/injection/domain/entities/run_with_injection_step.dart';

class RunWithInjectionCommand extends Command<int> {
  @override
  final argParser = ArgParser(allowTrailingOptions: false);

  @override
  final name = 'run';

  @override
  final description =
      'Inject SpmState into a Flutter project and run the app in --profile mode.\n'
      'Use -o/--output to specify where profiler data is saved (JSONL).\n'
      'Use --flutter to pass the flutter command and arguments.\n'
      'Examples:\n'
      '  spm run -j test.json\n'
      '  spm run -j test.json -o profiler.jsonl\n'
      '  spm run -j test.json --flutter drive --target=integration_test\n'
      '  spm run -j test.jsonl --flutter drive --driver=test_driver/integration_driver.dart'
      '  --target=integration_test/integration_test.dart --no-dds\n'
      '  spm run -j test.json -r ./my-app --flutter run -d android-device-id';

  RunWithInjectionCommand() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Enable verbose output.',
      negatable: false,
    );
    argParser.addOption(
      'jsonl',
      abbr: 'j',
      help:
          'Path to the input JSONL file with analysis results.\n'
          'Required unless --no-inject is set.',
    );
    argParser.addOption(
      'repo',
      abbr: 'r',
      help: 'Path to the Flutter project root directory (defaults to cwd).',
      defaultsTo: '.',
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help:
          'Path to the output JSONL file for profiler data.\n'
          'Defaults to spm/<mode>_<timestamp>.jsonl inside the current directory.',
    );
    argParser.addFlag(
      'no-inject',
      help:
          'Skip injection and revert steps — assumes the project is already instrumented.',
      negatable: false,
    );
    argParser.addFlag(
      'flutter',
      help:
          'Separator: everything after --flutter is passed to the Flutter CLI.',
      negatable: false,
    );
  }

  @override
  Future<int> run() async {
    final repoRoot = p.normalize(p.absolute(argResults!['repo'] as String));
    final verbose = argResults!['verbose'] as bool;
    final outputPath = argResults!['output'] as String? ?? _defaultOutputPath();
    final skipInjection = argResults!['no-inject'] as bool;
    final jsonPath = argResults!['jsonl'] as String?;
    if (!skipInjection && jsonPath == null) {
      usageException('-j/--jsonl is required unless --no-inject is set.');
    }

    if (!Directory(repoRoot).existsSync()) {
      usageException('Repository directory not found: $repoRoot');
    }
    if (jsonPath != null && !File(jsonPath).existsSync()) {
      usageException('Input file not found: $jsonPath');
    }

    // Everything after --flutter goes into argResults!.rest.
    final userFlutterArgs = argResults!.rest;

    // Build flutter args: subcommand + --profile flag + any extra args.
    final resolvedFlutterArgs = userFlutterArgs.isEmpty
        ? ['run', '--profile']
        : [userFlutterArgs.first, '--profile', ...userFlutterArgs.skip(1)];

    if (verbose) {
      SpmLogger.logMessage('Repository: $repoRoot');
      if (jsonPath != null) SpmLogger.logMessage('Input file: $jsonPath');
      SpmLogger.logMessage('Output file: $outputPath');
      SpmLogger.logMessage(
        'Flutter command: flutter ${resolvedFlutterArgs.join(' ')}',
      );
    }

    var exitCode = 0;

    final eventStream = InjectionDI.runWithInjectionUseCase.call(
      repoRoot,
      jsonPath ?? '',
      InjectionMode.inject,
      resolvedFlutterArgs,
      outputPath: outputPath,
      skipInjection: skipInjection,
    );

    await for (final either in eventStream) {
      either.fold(
        (failure) {
          _printFailure(failure);
          exitCode = 1;
        },
        (event) {
          switch (event) {
            case StepChangedEvent(:final step):
              _logStep(step);
            case AppRunEvent(event: VmServiceConnectionEvent(:final connected)):
              if (connected) {
                SpmLogger.logMessage('Connected to Dart VM service.');
              } else {
                SpmLogger.logMessage(
                  'Could not connect to Dart VM service - '
                  'profiler data will not be captured.',
                  isError: true,
                );
              }
            case AppRunEvent(event: ProfilerDataEvent()):
              SpmLogger.logMessage('ProfilerData event received.');
            case AppRunEvent(
              event: RunCompletedEvent(
                :final eventCount,
                :final vmServiceConnected,
                :final outputPath,
                exitCode: final code,
              ),
            ):
              exitCode = code;
              if (vmServiceConnected && outputPath != null) {
                SpmLogger.logMessage(
                  'Saved $eventCount profiler events to $outputPath',
                );
              } else if (!vmServiceConnected) {
                SpmLogger.logMessage(
                  'VM service was not connected - no profiler data captured.',
                  isError: true,
                );
              }
          }
        },
      );
    }

    return exitCode;
  }

  void _logStep(RunWithInjectionStep step) {
    switch (step) {
      case RunWithInjectionStep.analyzing:
        SpmLogger.logMessage('Running flutter analyze...');
      case RunWithInjectionStep.injecting:
        SpmLogger.logMessage('Injecting profiler code...');
      case RunWithInjectionStep.running:
        SpmLogger.logMessage('Starting app...');
      case RunWithInjectionStep.reverting:
        SpmLogger.logMessage('Reverting injection...');
    }
  }

  void _printFailure(Failure failure) {
    if (failure is CompoundFailure) {
      for (final f in failure.failures) {
        SpmLogger.logFailure(f);
      }
    } else {
      SpmLogger.logFailure(failure);
    }
  }

  static String _defaultOutputPath() {
    final now = DateTime.now();
    final ts =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return p.join('spm', 'profiler_$ts.jsonl');
  }
}
