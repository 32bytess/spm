import 'package:spm/src/core/types.dart';
import '../repositories/isolation_repository.dart';

/// Use case for isolation rebuild scopes from target repositories.
class IsolationUseCase {
  final IsolationRepository repository;

  IsolationUseCase(this.repository);

  /// Executes the isolation operation.
  ///
  /// [directories]: List of repository paths to analyze.
  /// [outputDir]: Where to save the generated Flutter State classes.
  /// [jsonlPath]: Optional path to write a JSONL mapping of the isolation.
  IsolationStream call({
    required List<String> directories,
    required String outputDir,
    String? jsonlPath,
  }) {
    return repository.isolate(
      directories: directories,
      outputDir: outputDir,
      jsonlPath: jsonlPath,
    );
  }
}
