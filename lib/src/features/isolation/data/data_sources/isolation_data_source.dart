import 'package:spm/src/core/types.dart';

/// Data source interface for isolation operations.
abstract class IsolationDataSource {
  /// Scans [directories] for rebuild scopes and saves isolated results to [outputDir].
  ///
  /// A [jsonlPath] can be provided to record the mapping between original and isolated paths.
  ///
  /// [inlineThirdParty] carries a third-party widget's own tree into the output
  /// instead of standing it in. See [IsolateCommand] for what it costs.
  IsolationEventStream isolate({
    required List<String> directories,
    required String outputDir,
    String? jsonlPath,
    bool inlineThirdParty,
  });
}
