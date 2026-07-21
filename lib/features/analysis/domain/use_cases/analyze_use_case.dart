import 'package:spm/core/types.dart';
import 'package:spm/features/analysis/domain/repositories/analysis_repository.dart';

class AnalyzeUseCase {
  final AnalysisRepository repository;

  AnalyzeUseCase(this.repository);

  AnalysisStream call(RepositoryPaths repoDirs) {
    return repository.analyze(repoDirs);
  }
}
