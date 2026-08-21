import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/injection/cli_service_locator.dart';
import 'package:spm/src/core/loggor/logger.dart';
import 'package:spm/src/features/validation/domain/entities/validation_report.dart';

/// CLI command that checks a mutation file is a clean structural variant
/// of its base: only the widget-tree structure may differ.
///
/// Usage:
/// `spm validate --base base.dart --mutation mutation.dart`
/// `[--deps dependencies.dart] [--directive name] [--json] [--strict]`
class ValidateCommand extends Command<int> {
  @override
  final name = 'validate';

  @override
  final description =
      'Validate that a mutation is a clean structural variant of its base '
      '(imports, seeds, rendered content and workload frozen).';

  ValidateCommand() {
    argParser
      ..addOption(
        'base',
        abbr: 'b',
        help: 'Path to the base .dart file.',
        mandatory: true,
      )
      ..addOption(
        'mutation',
        abbr: 'm',
        help: 'Path to the mutation .dart file.',
        mandatory: true,
      )
      ..addOption(
        'deps',
        abbr: 'd',
        help:
            'Frozen dependency file '
            '(default: dependencies.dart next to --base, if present).',
      )
      ..addOption(
        'directive',
        help:
            'Mutation-operator name (e.g. all_const); enables the '
            'expected-feature audit.',
      )
      ..addFlag(
        'json',
        help: 'Emit a machine-readable JSON report to stdout.',
        negatable: false,
      )
      ..addFlag(
        'strict',
        help: 'Treat soft violations as failures too.',
        negatable: false,
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
    // The args package throws a plain ArgumentError (exit 1) when a
    // mandatory option is read but missing; surface it as a usage error.
    for (final option in const ['base', 'mutation']) {
      if (!argResults!.wasParsed(option)) {
        usageException('Option --$option is mandatory.');
      }
    }

    final basePath = _requireFile('base');
    final mutationPath = _requireFile('mutation');
    final depsPath = _resolveDeps(basePath);
    final directive = argResults!['directive'] as String?;
    final asJson = argResults!['json'] as bool;
    final strict = argResults!['strict'] as bool;
    final verbose = argResults!['verbose'] as bool;

    if (verbose && !asJson) {
      SpmLogger.logMessage('Validating $mutationPath against $basePath');
      if (depsPath != null) SpmLogger.logMessage('Frozen deps: $depsPath');
    }

    final result = await ValidationDI.validatePairUseCase.call(
      basePath: basePath,
      mutationPath: mutationPath,
      depsPath: depsPath,
      directive: directive,
    );

    return result.fold(
      (failure) {
        SpmLogger.logMessage(
          'Validation error: ${failure.message}',
          isError: true,
        );
        return 1;
      },
      (report) {
        if (asJson) {
          // Raw JSON on stdout, the machine interface consumed by
          // the mutation pipeline; SpmLogger prefixes would break parsing.
          stdout.writeln(jsonEncode(report.toJson(strict: strict)));
        } else {
          _render(report, strict: strict);
        }
        return report.exitCode(strict: strict);
      },
    );
  }

  String _requireFile(String option) {
    final path = p.normalize(p.absolute(argResults![option] as String));
    if (!File(path).existsSync()) {
      usageException('--$option file not found: $path');
    }
    return path;
  }

  String? _resolveDeps(String basePath) {
    final explicit = argResults!['deps'] as String?;
    if (explicit != null) {
      final path = p.normalize(p.absolute(explicit));
      if (!File(path).existsSync()) {
        usageException('--deps file not found: $path');
      }
      return path;
    }
    final sibling = p.join(p.dirname(basePath), 'dependencies.dart');
    return File(sibling).existsSync() ? sibling : null;
  }

  void _render(ValidationReport report, {required bool strict}) {
    for (final v in report.violations) {
      SpmLogger.logMessage(
        '[${v.severity.name}] ${v.code.name}: ${v.detail}',
        isError: v.severity == Severity.hard || strict,
      );
    }
    final valid = report.isValid(strict: strict);
    SpmLogger.logMessage(
      valid
          ? 'PASS: mutation is a clean structural variant of the base.'
          : 'FAIL: ${report.violations.length} violation(s) found.',
      isError: !valid,
    );
  }
}
