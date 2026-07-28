import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_event.dart';

abstract class AnalysisDataSource {
  /// Analyzes the repositories located in the specified directories.
  ///
  /// Parameters:
  /// - [repoDirs]: A list of directory paths where the repositories are located.
  /// - [scopeTypes]: Rebuild scope types to keep; null keeps every type.
  ///
  AnalysisEventStream analyzeDirs(
    RepositoryPaths repoDirs, {
    Set<String>? scopeTypes,
  });

  /// Saves the analysis results to a specified file path.
  ///
  /// Parameters:
  /// - [analysisResult]: A stream of [AnalysisDataEvent] to be saved.
  /// - [filePath]: The file path where the results should be saved.
  ///
  AsyncVoid saveResults(
    AnalysisDataEventStream analysisResult,
    OutputPath filePath,
  );
}
