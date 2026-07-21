import 'package:spm/core/types.dart';
import 'package:spm/features/injection/domain/repositories/flutter_analyze_repository.dart';

class FlutterAnalyzeUseCase {
  final FlutterAnalyzeRepository repository;

  FlutterAnalyzeUseCase(this.repository);

  AsyncVoidResult call(String repoRoot) => repository.analyze(repoRoot);
}
