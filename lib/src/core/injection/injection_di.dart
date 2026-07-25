import 'package:spm/src/features/injection/data/data_sources/flutter_analyze_data_source.dart';
import 'package:spm/src/features/injection/data/data_sources/flutter_analyze_data_source_impl.dart';
import 'package:spm/src/features/injection/data/data_sources/injection_data_source.dart';
import 'package:spm/src/features/injection/data/data_sources/injection_data_source_impl.dart';
import 'package:spm/src/features/injection/data/data_sources/run_app_data_source.dart';
import 'package:spm/src/features/injection/data/data_sources/run_app_data_source_impl.dart';
import 'package:spm/src/features/injection/data/repositories/flutter_analyze_repository_impl.dart';
import 'package:spm/src/features/injection/data/repositories/injection_repository_impl.dart';
import 'package:spm/src/features/injection/data/repositories/run_app_repository_impl.dart';
import 'package:spm/src/features/injection/domain/repositories/flutter_analyze_repository.dart';
import 'package:spm/src/features/injection/domain/repositories/injection_repository.dart';
import 'package:spm/src/features/injection/domain/repositories/run_app_repository.dart';
import 'package:spm/src/features/injection/domain/use_cases/flutter_analyze_use_case.dart';
import 'package:spm/src/features/injection/domain/use_cases/inject_use_case.dart';
import 'package:spm/src/features/injection/domain/use_cases/run_with_injection_use_case.dart';

/// Static dependency injection for the injection feature.
class InjectionDI {
  InjectionDI._();

  static FlutterAnalyzeDataSource? _flutterAnalyzeDataSource;
  static FlutterAnalyzeRepository? _flutterAnalyzeRepository;
  static FlutterAnalyzeUseCase? _flutterAnalyzeUseCase;
  static InjectionDataSource? _dataSource;
  static InjectionRepository? _repository;
  static InjectUseCase? _injectUseCase;
  static RunAppDataSource? _runAppDataSource;
  static RunAppRepository? _runAppRepository;
  static RunWithInjectionUseCase? _runWithInjectionUseCase;

  static FlutterAnalyzeDataSource get flutterAnalyzeDataSource =>
      _flutterAnalyzeDataSource ??= FlutterAnalyzeDataSourceImpl();

  static FlutterAnalyzeRepository get flutterAnalyzeRepository =>
      _flutterAnalyzeRepository ??= FlutterAnalyzeRepositoryImpl(
        flutterAnalyzeDataSource,
      );

  static FlutterAnalyzeUseCase get flutterAnalyzeUseCase =>
      _flutterAnalyzeUseCase ??= FlutterAnalyzeUseCase(
        flutterAnalyzeRepository,
      );

  static InjectionDataSource get dataSource =>
      _dataSource ??= InjectionDataSourceImpl();

  static InjectionRepository get repository =>
      _repository ??= InjectionRepositoryImpl(dataSource);

  static InjectUseCase get injectUseCase =>
      _injectUseCase ??= InjectUseCase(repository);

  static RunAppDataSource get runAppDataSource =>
      _runAppDataSource ??= RunAppDataSourceImpl();

  static RunAppRepository get runAppRepository =>
      _runAppRepository ??= RunAppRepositoryImpl(runAppDataSource);

  static RunWithInjectionUseCase get runWithInjectionUseCase =>
      _runWithInjectionUseCase ??= RunWithInjectionUseCase(
        flutterAnalyzeRepository,
        repository,
        runAppRepository,
      );

  /// Resets all cached instances. Use in tests to ensure a clean slate.
  static void reset() {
    _flutterAnalyzeDataSource = null;
    _flutterAnalyzeRepository = null;
    _flutterAnalyzeUseCase = null;
    _dataSource = null;
    _repository = null;
    _injectUseCase = null;
    _runAppDataSource = null;
    _runAppRepository = null;
    _runWithInjectionUseCase = null;
  }
}
