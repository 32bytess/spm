import 'package:spm/src/core/types.dart';

/// Interface for the repository that handles isolating rebuild scopes.
abstract class IsolationRepository {
  /// Isolates rebuild scopes from the specified [directories] and saves them to [outputDir].
  ///
  /// Optionally, a [jsonlPath] can be provided to save a mapping of original to isolated files.
  IsolationStream isolate({
    required List<String> directories,
    required String outputDir,
    String? jsonlPath,
  });
}
