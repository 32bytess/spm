import 'package:spm/core/types.dart';

abstract class FlutterAnalyzeRepository {
  AsyncVoidResult analyze(String repoRoot);
}
