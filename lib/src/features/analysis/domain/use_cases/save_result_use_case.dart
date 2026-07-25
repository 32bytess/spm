import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/analysis/domain/repositories/analysis_repository.dart';

class SaveResultUseCase {
  final AnalysisRepository repository;

  SaveResultUseCase(this.repository);

  SaveResult call({
    required AnalysisDataEventStream analysisResult,
    required String filePath,
  }) => repository.saveResults(analysisResult, filePath);
}
