import 'package:dartz/dartz.dart';
import 'package:spm/core/errors/exceptions.dart';
import 'package:spm/core/errors/failures.dart';
import 'package:spm/core/types.dart';
import 'package:spm/features/analysis/domain/repositories/analysis_repository.dart';

import '../data_sources/analysis_data_source.dart';

class AnalysisRepositoryImpl implements AnalysisRepository {
  AnalysisDataSource analysisDataSource;

  AnalysisRepositoryImpl(this.analysisDataSource);

  @override
  AnalysisStream analyze(RepositoryPaths repoDirs) async* {
    try {
      final result = analysisDataSource.analyzeDirs(repoDirs);
      await for (final event in result) {
        yield Right(event);
      }
    } on AnalyzerInitializationException catch (e) {
      yield Left(AnalyzerInitializationFailure(e.message));
    } on ComplexityExtractionException catch (e, stackTrace) {
      yield Left(ComplexityExtractionFailure(e.message, stackTrace.toString()));
    } on ContextExtractionException catch (e, stackTrace) {
      yield Left(ContextExtractionFailure(e.message, stackTrace.toString()));
    } on TreeExtractionException catch (e, stackTrace) {
      yield Left(TreeExtractionFailure(e.message, stackTrace.toString()));
    } catch (e, stackTrace) {
      yield Left(UnknownFailure(e.toString(), stackTrace.toString()));
    }
  }

  @override
  SaveResult saveResults(
    AnalysisDataEventStream analysisResult,
    OutputPath filePath,
  ) async {
    try {
      await analysisDataSource.saveResults(analysisResult, filePath);
      return Right(null);
    } on FileWriteException catch (e, stackTrace) {
      return Left(FileWriteFailure(e.message, stackTrace.toString()));
    } catch (e, stackTrace) {
      return Left(UnknownFailure(e.toString(), stackTrace.toString()));
    }
  }
}
