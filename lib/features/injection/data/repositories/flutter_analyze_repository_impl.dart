import 'package:dartz/dartz.dart';
import 'package:spm/core/errors/exceptions.dart';
import 'package:spm/core/errors/failures.dart';
import 'package:spm/core/types.dart';
import 'package:spm/features/injection/data/data_sources/flutter_analyze_data_source.dart';
import 'package:spm/features/injection/domain/repositories/flutter_analyze_repository.dart';

class FlutterAnalyzeRepositoryImpl implements FlutterAnalyzeRepository {
  final FlutterAnalyzeDataSource dataSource;

  FlutterAnalyzeRepositoryImpl(this.dataSource);

  @override
  AsyncVoidResult analyze(String repoRoot) async {
    try {
      await dataSource.analyze(repoRoot);
      return const Right(null);
    } on FlutterAnalyzeException catch (e) {
      return Left(FlutterAnalyzeFailure(e.message));
    } catch (e, st) {
      return Left(FlutterAnalyzeFailure(e.toString(), st.toString()));
    }
  }
}
