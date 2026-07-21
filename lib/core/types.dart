import 'package:dartz/dartz.dart';
import 'package:spm/features/analysis/domain/entities/analysis_event.dart';
import 'package:spm/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:spm/features/isolation/domain/entities/isolation_event.dart';
import 'package:spm/features/injection/domain/entities/run_app_event.dart';
import 'package:spm/features/injection/domain/entities/run_with_injection_event.dart';
import 'package:spm/features/profiler/domain/entities/dataflow_metrics_entity.dart';
import 'package:spm/features/profiler/domain/entities/performance_metrics_entity.dart';
import 'package:spm/features/validation/domain/entities/validation_report.dart';
import 'errors/failures.dart';

// Core
typedef Result<T> = Either<Failure, T>;
typedef AsyncResult<T> = Future<Result<T>>;
typedef StreamResult<T> = Stream<Result<T>>;
typedef AsyncVoid = Future<void>;

// JSON / Data
typedef JsonRecord = Map<String, dynamic>;

// Analysis Events
typedef AnalysisEventStream = Stream<AnalysisEvent>;
typedef AnalysisResultStream = Stream<AnalysisResultEntity>;
typedef AnalysisDataEventStream = Stream<AnalysisDataEvent>;
typedef AnalysisSummaryEventStream = Stream<AnalysisSummaryEvent>;

// Isolation Events
typedef IsolationEventStream = Stream<IsolationEvent>;
typedef IsolationDataEventStream = Stream<IsolationDataEvent>;
typedef IsolationSummaryEventStream = Stream<IsolationSummaryEvent>;

// Repository Layer
typedef AnalysisStream = StreamResult<AnalysisEvent>;
typedef IsolationStream = StreamResult<IsolationEvent>;
typedef SaveResult = AsyncResult<void>;
typedef AsyncVoidResult = AsyncResult<void>;

// Input/Output
typedef RepositoryPaths = List<String>;
typedef OutputPath = String;

// Handlers & Callbacks
typedef OnAnalysisEvent = void Function(AnalysisEvent event);
typedef OnAnalysisData = void Function(AnalysisResultEntity result);
typedef OnAnalysisError = void Function(Failure failure);
typedef OnAnalysisComplete = void Function(AnalysisSummaryEvent summary);

// Profiler
typedef AsyncPerformanceMetrics = AsyncResult<PerformanceMetricsEntity>;
typedef AsyncDataFlowMetrics = AsyncResult<DataFlowMetricsEntity>;

// Injection
typedef AsyncRunAppEventStream = AsyncResult<Stream<RunAppEvent>>;

// Validation
typedef AsyncValidationReport = AsyncResult<ValidationReport>;
typedef RunWithInjectionEventStream = StreamResult<RunWithInjectionEvent>;
