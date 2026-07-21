import 'package:spm/features/profiler/data/data_sources/profiler_data_source.dart';
import 'package:spm/features/profiler/data/data_sources/profiler_data_source_impl.dart';
import 'package:spm/features/profiler/data/repositories/profiler_repository_impl.dart';
import 'package:spm/features/profiler/domain/repositories/profiler_repository.dart';
import 'package:spm/features/profiler/domain/use_cases/monitor_dataflow_use_case.dart';
import 'package:spm/features/profiler/domain/use_cases/monitor_performance_use_case.dart';

/// Static dependency injection for the profiler feature.
class ProfilerDI {
  ProfilerDI._();

  static ProfilerDataSource? _dataSource;
  static ProfilerRepository? _repository;
  static MonitorPerformanceUseCase? _monitorPerformanceUseCase;
  static MonitorDataflowUseCase? _monitorDataflowUseCase;

  static ProfilerDataSource get dataSource =>
      _dataSource ??= ProfilerDataSourceImpl();

  static ProfilerRepository get repository =>
      _repository ??= ProfilerRepositoryImpl(dataSource);

  static MonitorPerformanceUseCase get monitorPerformanceUseCase =>
      _monitorPerformanceUseCase ??= MonitorPerformanceUseCase(repository);

  static MonitorDataflowUseCase get monitorDataflowUseCase =>
      _monitorDataflowUseCase ??= MonitorDataflowUseCase(repository);
}
