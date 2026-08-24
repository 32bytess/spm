import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/inline_budget.dart';
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
  /// [inlineThirdParty]: whether a third-party widget's own tree is carried
  /// into the output rather than stood in for.
  /// [inlineMaxDeclarations] and [inlineMaxCharacters]: how much third-party
  /// source one scope may carry.
  IsolationStream call({
    required List<String> directories,
    required String outputDir,
    String? jsonlPath,
    bool inlineThirdParty = true,
    int inlineMaxDeclarations = InlineBudget.defaultMaxDeclarations,
    int inlineMaxCharacters = InlineBudget.defaultMaxCharacters,
    bool pruneNonRebuild = true,
  }) {
    return repository.isolate(
      directories: directories,
      outputDir: outputDir,
      jsonlPath: jsonlPath,
      inlineThirdParty: inlineThirdParty,
      inlineMaxDeclarations: inlineMaxDeclarations,
      inlineMaxCharacters: inlineMaxCharacters,
      pruneNonRebuild: pruneNonRebuild,
    );
  }
}
