import 'package:spm/src/core/types.dart';

abstract class AnalysisRepository {
  /// Analyzes the repositories located in the specified directories.
  ///
  /// Parameters:
  /// - [repoDirs]: A list of directory paths where the repositories are located.
  /// - [scopeTypes]: Rebuild scope types to keep; null keeps every type.
  /// Returns:
  /// - An [AnalysisStream] containing a stream of [AnalysisResultEntity].
  ///
  AnalysisStream analyze(RepositoryPaths repoDirs, {Set<String>? scopeTypes});

  /// Saves the analysis results to a specified file path.
  ///
  /// Parameters:
  /// - [analysisResult]: A stream of [AnalysisResultEntity] to be saved.
  /// - [filePath]: The file path where the results should be saved.
  ///
  SaveResult saveResults(
    AnalysisDataEventStream analysisResult,
    OutputPath filePath,
  );
}
