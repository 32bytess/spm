import 'package:spm/features/analysis/data/data_sources/analysis_data_source.dart';
import 'package:spm/features/analysis/data/data_sources/analysis_data_source_impl.dart';
import 'package:spm/features/analysis/data/repositories/analysis_repository_impl.dart';
import 'package:spm/features/analysis/domain/repositories/analysis_repository.dart';
import 'package:spm/features/analysis/domain/use_cases/analyze_use_case.dart';
import 'package:spm/features/analysis/domain/use_cases/save_result_use_case.dart';

/// Static dependency injection for the analysis feature.
class AnalysisDI {
  AnalysisDI._();

  static AnalysisDataSource? _dataSource;
  static AnalysisRepository? _repository;
  static AnalyzeUseCase? _analyzeUseCase;
  static SaveResultUseCase? _saveResultUseCase;

  static AnalysisDataSource get dataSource =>
      _dataSource ??= AnalysisDataSourceImpl();

  static AnalysisRepository get repository =>
      _repository ??= AnalysisRepositoryImpl(dataSource);

  static AnalyzeUseCase get analyzeUseCase =>
      _analyzeUseCase ??= AnalyzeUseCase(repository);

  static SaveResultUseCase get saveResultUseCase =>
      _saveResultUseCase ??= SaveResultUseCase(repository);

  /// Resets all cached instances. Use in tests to ensure a clean slate.
  static void reset() {
    _dataSource = null;
    _repository = null;
    _analyzeUseCase = null;
    _saveResultUseCase = null;
  }
}
