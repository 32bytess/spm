import 'package:spm/src/core/types.dart';

abstract class RunAppRepository {
  AsyncRunAppEventStream runApp(
    String repoRoot,
    List<String> flutterArgs, {
    String? outputPath,
  });
}
