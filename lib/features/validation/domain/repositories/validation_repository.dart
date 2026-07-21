import 'package:spm/core/types.dart';

/// Contract for validating that a mutation file is a clean structural
/// variant of its base file.
abstract class ValidationRepository {
  /// Validates the [basePath] ↔ [mutationPath] pair against the frozen
  /// dependency file at [depsPath] (if any).
  ///
  /// [directive] optionally names the mutation operator (e.g. `all_const`)
  /// to enable the expected-feature audit.
  AsyncValidationReport validatePair({
    required String basePath,
    required String mutationPath,
    String? depsPath,
    String? directive,
  });
}
