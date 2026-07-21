import 'package:spm/core/types.dart';

/// Data source interface for isolation operations.
abstract class IsolationDataSource {
  /// Scans [directories] for rebuild scopes and saves isolated results to [outputDir].
  ///
  /// A [jsonlPath] can be provided to record the mapping between original and isolated paths.
  IsolationEventStream isolate({
    required List<String> directories,
    required String outputDir,
    String? jsonlPath,
  });
}
