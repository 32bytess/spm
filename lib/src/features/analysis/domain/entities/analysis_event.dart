import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';

sealed class AnalysisEvent {}

class AnalysisDataEvent extends AnalysisEvent {
  final AnalysisResultEntity result;

  AnalysisDataEvent({required this.result});
}

class AnalysisSummaryEvent extends AnalysisEvent {
  final int filesScanned;

  /// Files skipped because they contain compile errors: their unresolved
  /// types would silently zero out every feature, so no rows are emitted.
  final int filesSkipped;
  final int stateClassesFound;
  final int keptRows;

  AnalysisSummaryEvent({
    required this.filesScanned,
    required this.filesSkipped,
    required this.stateClassesFound,
    required this.keptRows,
  });
}
