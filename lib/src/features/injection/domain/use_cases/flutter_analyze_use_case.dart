import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/injection/domain/repositories/flutter_analyze_repository.dart';

class FlutterAnalyzeUseCase {
  final FlutterAnalyzeRepository repository;

  FlutterAnalyzeUseCase(this.repository);

  AsyncVoidResult call(String repoRoot) => repository.analyze(repoRoot);
}
