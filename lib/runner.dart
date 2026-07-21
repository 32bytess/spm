import 'package:args/command_runner.dart';
import 'package:spm/core/loggor/logger.dart';
import 'package:spm/features/analysis/presentation/analysis_command.dart';
import 'package:spm/features/isolation/presentation/isolate_command.dart';
import 'package:spm/features/injection/presentation/inject_command.dart';
import 'package:spm/features/injection/presentation/run_with_injection_command.dart';
import 'package:spm/features/validation/presentation/validate_command.dart';

class SpmRunner extends CommandRunner<int> {
  SpmRunner()
    : super(
        'spm',
        'A CLI tool for analyzing rebuild triggers in Flutter State classes.',
      ) {
    addCommand(AnalysisCommand());
    addCommand(IsolateCommand());
    addCommand(InjectCommand());
    addCommand(RunWithInjectionCommand());
    addCommand(ValidateCommand());
  }

  @override
  Future<int?> run(Iterable<String> args) async {
    try {
      return await super.run(args) ?? 0;
    } on UsageException catch (_) {
      printUsage();
      return 64;
    } catch (e) {
      SpmLogger.logMessage('Error: $e', isError: true);
      return 1;
    }
  }
}
