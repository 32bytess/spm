import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:spm/core/injection/injection_di.dart';
import 'package:spm/core/loggor/logger.dart';
import 'package:spm/features/injection/domain/entities/injection_mode.dart';

class InjectCommand extends Command<int> {
  @override
  final name = 'inject';

  @override
  final description =
      'Inject SpmState base class and instanceId into a Flutter project to collect runtime performance metrics.';

  InjectCommand() {
    argParser.addOption(
      'mode',
      abbr: 'm',
      help: 'Injection mode: inject or remove.',
      defaultsTo: 'inject',
      allowed: ['inject', 'remove'],
    );
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Enable verbose output.',
      negatable: false,
    );
    argParser.addOption(
      'jsonl',
      abbr: 'j',
      help: 'Path to the input JSONL file with analysis results.',
      mandatory: true,
    );
  }

  @override
  Future<int> run() async {
    final arguments = argResults!.rest;
    if (arguments.length != 1) {
      usageException('spm inject requires exactly one argument: <repo_root>');
    }

    final repoRoot = p.normalize(p.absolute(arguments[0]));
    final jsonPath = argResults!['jsonl'] as String;
    final mode = InjectionMode.fromCli(argResults!['mode'] as String);
    final verbose = argResults!['verbose'] as bool;

    if (!Directory(repoRoot).existsSync()) {
      usageException('Repository directory not found: $repoRoot');
    }
    if (!File(jsonPath).existsSync()) {
      usageException('Input file not found: $jsonPath');
    }

    if (verbose) {
      SpmLogger.logMessage('Starting SpmState Profiler Injection...');
      SpmLogger.logMessage('Repo: $repoRoot');
      SpmLogger.logMessage('Mode: ${mode.name.toUpperCase()}');
      SpmLogger.logMessage('Input file: $jsonPath');
    }

    final result = await InjectionDI.injectUseCase.call(
      repoRoot,
      jsonPath,
      mode,
    );

    return result.fold(
      (failure) {
        SpmLogger.logMessage(
          'Error during injection: ${failure.message}',
          isError: true,
        );
        return 1;
      },
      (_) {
        final message = mode == InjectionMode.remove
            ? 'Successfully removed injected code.'
            : 'Successfully injected code.';
        SpmLogger.logMessage(message);
        return 0;
      },
    );
  }
}
