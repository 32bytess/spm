import 'package:spm/src/core/types.dart';

abstract class FlutterAnalyzeRepository {
  AsyncVoidResult analyze(String repoRoot);
}
