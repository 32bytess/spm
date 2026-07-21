import 'package:spm/features/validation/domain/entities/validation_report.dart';

/// Data source contract for base↔mutation validation. May throw; the
/// repository layer maps exceptions to failures.
abstract class ValidationDataSource {
  Future<ValidationReport> validatePair({
    required String basePath,
    required String mutationPath,
    String? depsPath,
    String? directive,
  });
}
