import 'package:dartz/dartz.dart';
import 'package:spm/core/errors/exceptions.dart';
import 'package:spm/core/errors/failures.dart';
import 'package:spm/core/types.dart';
import 'package:spm/features/injection/data/data_sources/injection_data_source.dart';
import 'package:spm/features/injection/domain/entities/injection_mode.dart';
import 'package:spm/features/injection/domain/repositories/injection_repository.dart';

class InjectionRepositoryImpl implements InjectionRepository {
  final InjectionDataSource dataSource;

  InjectionRepositoryImpl(this.dataSource);

  @override
  AsyncVoidResult inject(
    String repoRoot,
    String jsonPath,
    InjectionMode mode,
  ) async {
    try {
      await dataSource.inject(repoRoot, jsonPath, mode);
      return const Right(null);
    } on FileNotFoundException catch (e) {
      return Left(FileNotFoundFailure(e.message));
    } on FileTypeException catch (e) {
      return Left(FileTypeFailure(e.message));
    } catch (e, st) {
      return Left(InjectionFailure(e.toString(), st.toString()));
    }
  }
}
