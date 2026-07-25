import 'package:spm/src/features/injection/domain/entities/run_app_event.dart';

abstract class RunAppDataSource {
  Stream<RunAppEvent> runApp(
    String repoRoot,
    List<String> flutterArgs, {
    String? outputPath,
  });
}
