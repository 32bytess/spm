import 'package:dartz/dartz.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_event.dart';
import 'package:spm/src/features/injection/domain/entities/run_app_event.dart';
import 'package:spm/src/features/injection/domain/entities/run_with_injection_event.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';
import 'package:spm/src/features/validation/domain/entities/validation_report.dart';
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
typedef AnalysisDataEventStream = Stream<AnalysisDataEvent>;

// Isolation Events
typedef IsolationEventStream = Stream<IsolationEvent>;

// Repository Layer
typedef AnalysisStream = StreamResult<AnalysisEvent>;
typedef IsolationStream = StreamResult<IsolationEvent>;
typedef SaveResult = AsyncResult<void>;
typedef AsyncVoidResult = AsyncResult<void>;

// Input/Output
typedef RepositoryPaths = List<String>;
typedef OutputPath = String;

// Injection
typedef AsyncRunAppEventStream = AsyncResult<Stream<RunAppEvent>>;

// Validation
typedef AsyncValidationReport = AsyncResult<ValidationReport>;
typedef RunWithInjectionEventStream = StreamResult<RunWithInjectionEvent>;
