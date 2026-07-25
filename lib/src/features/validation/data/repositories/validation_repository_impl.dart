import 'package:dartz/dartz.dart';
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/core/errors/failures.dart';
import 'package:spm/src/core/types.dart';
import '../../domain/repositories/validation_repository.dart';
import '../data_sources/validation_data_source.dart';

/// Implementation of [ValidationRepository] that delegates to a
/// [ValidationDataSource] and maps exceptions to failures.
class ValidationRepositoryImpl implements ValidationRepository {
  final ValidationDataSource dataSource;

  ValidationRepositoryImpl(this.dataSource);

  @override
  AsyncValidationReport validatePair({
    required String basePath,
    required String mutationPath,
    String? depsPath,
    String? directive,
  }) async {
    try {
      final report = await dataSource.validatePair(
        basePath: basePath,
        mutationPath: mutationPath,
        depsPath: depsPath,
        directive: directive,
      );
      return Right(report);
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message, e.stackTrace));
    } catch (e, st) {
      return Left(ValidationFailure(e.toString(), st.toString()));
    }
  }
}
