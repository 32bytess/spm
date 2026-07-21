import 'package:spm/features/isolation/data/data_sources/isolation_data_source.dart';
import 'package:spm/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/features/isolation/data/repositories/isolation_repository_impl.dart';
import 'package:spm/features/isolation/domain/repositories/isolation_repository.dart';
import 'package:spm/features/isolation/domain/use_cases/isolation_use_case.dart';

/// Static dependency injection for the isolation feature.
class IsolationDI {
  IsolationDI._();

  static IsolationDataSource? _dataSource;
  static IsolationRepository? _repository;
  static IsolationUseCase? _isolationUseCase;

  static IsolationDataSource get dataSource =>
      _dataSource ??= IsolationDataSourceImpl();

  static IsolationRepository get repository =>
      _repository ??= IsolationRepositoryImpl(dataSource);

  static IsolationUseCase get isolationUseCase =>
      _isolationUseCase ??= IsolationUseCase(repository);

  /// Resets all cached instances. Use in tests to ensure a clean slate.
  static void reset() {
    _dataSource = null;
    _repository = null;
    _isolationUseCase = null;
  }
}
