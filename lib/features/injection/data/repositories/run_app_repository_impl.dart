import 'package:dartz/dartz.dart';
import 'package:spm/core/errors/exceptions.dart';
import 'package:spm/core/errors/failures.dart';
import 'package:spm/core/types.dart';
import 'package:spm/features/injection/data/data_sources/run_app_data_source.dart';
import 'package:spm/features/injection/domain/repositories/run_app_repository.dart';

class RunAppRepositoryImpl implements RunAppRepository {
  final RunAppDataSource dataSource;

  RunAppRepositoryImpl(this.dataSource);

  @override
  AsyncRunAppEventStream runApp(
    String repoRoot,
    List<String> flutterArgs, {
    String? outputPath,
  }) async {
    try {
      final stream = dataSource.runApp(
        repoRoot,
        flutterArgs,
        outputPath: outputPath,
      );
      return Right(stream);
    } on RunAppException catch (e) {
      return Left(RunAppFailure(e.message, e.stackTrace));
    } catch (e, st) {
      return Left(RunAppFailure(e.toString(), st.toString()));
    }
  }
}
