import 'package:spm/core/types.dart';

abstract class AnalysisRepository {
  /// Analyzes the repositories located in the specified directories.
  ///
  /// Parameters:
  /// - [repoDirs]: A list of directory paths where the repositories are located.
  /// Returns:
  /// - An [AnalysisStream] containing a stream of [AnalysisResultEntity].
  ///
  AnalysisStream analyze(RepositoryPaths repoDirs);

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
