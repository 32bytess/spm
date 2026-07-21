import 'package:spm/core/types.dart';
import 'package:spm/features/analysis/domain/entities/analysis_event.dart';

abstract class AnalysisDataSource {
  /// Analyzes the repositories located in the specified directories.
  ///
  /// Parameters:
  /// - [repoDirs]: A list of directory paths where the repositories are located.
  ///
  AnalysisEventStream analyzeDirs(RepositoryPaths repoDirs);

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
