import 'package:spm/features/validation/data/data_sources/validation_data_source.dart';
import 'package:spm/features/validation/data/data_sources/validation_data_source_impl.dart';
import 'package:spm/features/validation/data/repositories/validation_repository_impl.dart';
import 'package:spm/features/validation/domain/repositories/validation_repository.dart';
import 'package:spm/features/validation/domain/use_cases/validate_pair_use_case.dart';

/// Static dependency injection for the validation feature.
class ValidationDI {
  ValidationDI._();

  static ValidationDataSource? _dataSource;
  static ValidationRepository? _repository;
  static ValidatePairUseCase? _validatePairUseCase;

  static ValidationDataSource get dataSource =>
      _dataSource ??= ValidationDataSourceImpl();

  static ValidationRepository get repository =>
      _repository ??= ValidationRepositoryImpl(dataSource);

  static ValidatePairUseCase get validatePairUseCase =>
      _validatePairUseCase ??= ValidatePairUseCase(repository);

  /// Resets all cached instances. Use in tests to ensure a clean slate.
  static void reset() {
    _dataSource = null;
    _repository = null;
    _validatePairUseCase = null;
  }
}
