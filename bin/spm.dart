import 'dart:io';

import 'package:spm/core/types.dart';
import 'package:spm/runner.dart';

AsyncVoid main(List<String> args) async {
  final runner = SpmRunner();
  final exitCode = await runner.run(args) ?? 0;
  exit(exitCode);
}
