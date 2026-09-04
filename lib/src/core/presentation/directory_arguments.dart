import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Reads the positional directory arguments shared by `analyze` and `isolate`.
///
/// Both take one or more directories as the rest of the command line, and both
/// want them absolute and normalised before anything downstream sees them. The
/// existence check used to live in `analyze` alone, so `isolate` accepted a
/// path that was not there and failed later, further from the typo that caused
/// it.
mixin DirectoryArguments on Command<int> {
  /// The rest arguments as absolute, normalised paths.
  ///
  /// Calls [usageException] when none were given or when any of them does not
  /// exist, which prints the usage text and exits. [label] names the arguments
  /// in that second message, since each command has its own word for them.
  List<String> readDirectories({String label = 'Directories'}) {
    final directories = argResults!.rest;

    if (directories.isEmpty) {
      usageException('At least one directory must be specified.');
    }

    final repoDirs = directories
        .map((a) => p.normalize(p.absolute(a)))
        .toList();

    final missingDirs = repoDirs.where((path) => !Directory(path).existsSync());
    if (missingDirs.isNotEmpty) {
      usageException('$label do not exist: ${missingDirs.join(', ')}');
    }

    return repoDirs;
  }
}
