import 'package:dartz/dartz.dart';
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/core/errors/failures.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/inline_budget.dart';
import '../../domain/repositories/isolation_repository.dart';
import '../data_sources/isolation_data_source.dart';

/// Implementation of [IsolationRepository] that delegates to a [IsolationDataSource].
class IsolationRepositoryImpl implements IsolationRepository {
  /// The data source used for isolation.
  final IsolationDataSource dataSource;

  IsolationRepositoryImpl(this.dataSource);

  @override
  IsolationStream isolate({
    required List<String> directories,
    required String outputDir,
    String? jsonlPath,
    bool inlineThirdParty = true,
    int inlineMaxDeclarations = InlineBudget.defaultMaxDeclarations,
    int inlineMaxCharacters = InlineBudget.defaultMaxCharacters,
    bool pruneNonRebuild = true,
  }) async* {
    try {
      final result = dataSource.isolate(
        directories: directories,
        outputDir: outputDir,
        jsonlPath: jsonlPath,
        inlineThirdParty: inlineThirdParty,
        inlineMaxDeclarations: inlineMaxDeclarations,
        inlineMaxCharacters: inlineMaxCharacters,
        pruneNonRebuild: pruneNonRebuild,
      );
      await for (final event in result) {
        yield Right(event);
      }
    } on IsolationException catch (e) {
      yield Left(IsolationFailure(e.message, e.stackTrace));
    } catch (e, st) {
      yield Left(IsolationFailure(e.toString(), st.toString()));
    }
  }
}
