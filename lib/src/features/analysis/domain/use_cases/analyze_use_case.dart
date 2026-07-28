import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/analysis/domain/repositories/analysis_repository.dart';

class AnalyzeUseCase {
  final AnalysisRepository repository;

  AnalyzeUseCase(this.repository);

  AnalysisStream call(RepositoryPaths repoDirs, {Set<String>? scopeTypes}) {
    return repository.analyze(repoDirs, scopeTypes: scopeTypes);
  }
}
