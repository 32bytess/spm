import 'dart:convert';
import 'dart:io';

import 'package:spm/core/errors/exceptions.dart';
import 'package:spm/core/types.dart';
import 'package:spm/features/injection/data/data_sources/flutter_analyze_data_source.dart';

class FlutterAnalyzeDataSourceImpl implements FlutterAnalyzeDataSource {
  @override
  AsyncVoid analyze(String repoRoot) async {
    final process = await Process.start('flutter', [
      'analyze',
      'lib',
    ], workingDirectory: repoRoot);

    bool hasErrors = false;

    // pipe stdout live and scan each line for errors
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdout.writeln(line);
          if (line.trimLeft().startsWith('error •')) hasErrors = true;
        })
        .asFuture<void>();

    final stderrDone = process.stderr.listen(stderr.add).asFuture<void>();

    await Future.wait([stdoutDone, stderrDone]);
    await process.exitCode;

    if (hasErrors) {
      throw FlutterAnalyzeException(
        'flutter analyze reported errors. Fix them before running.',
      );
    }
  }
}
