import 'package:spm/src/core/types.dart';
import '../repositories/validation_repository.dart';

/// Use case for validating a base↔mutation pair.
class ValidatePairUseCase {
  final ValidationRepository repository;

  ValidatePairUseCase(this.repository);

  /// Executes the validation.
  ///
  /// [basePath]: The base `.dart` file.
  /// [mutationPath]: The mutation `.dart` file to compare against the base.
  /// [depsPath]: Optional frozen `dependencies.dart` file.
  /// [directive]: Optional mutation-operator name for the feature audit.
  AsyncValidationReport call({
    required String basePath,
    required String mutationPath,
    String? depsPath,
    String? directive,
  }) {
    return repository.validatePair(
      basePath: basePath,
      mutationPath: mutationPath,
      depsPath: depsPath,
      directive: directive,
    );
  }
}
