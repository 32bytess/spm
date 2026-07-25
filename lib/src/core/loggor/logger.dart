import 'dart:io';

import 'package:spm/src/core/errors/failures.dart';

class SpmLogger {
  static void logFailure(Failure failure, [String? instanceId]) {
    final data = {
      'error_type': failure.runtimeType.toString(),
      'message': failure.message,
    };
    if (instanceId != null) {
      data['instance_id'] = instanceId;
    }
    log(data, isError: true);
  }

  static void log(Map<String, dynamic> data, {bool isError = false}) {
    final output = isError ? stderr : stdout;
    output.writeln('[spm]: ===============================');
    output.writeln('timestamp: ${DateTime.now().toIso8601String()}');
    data.forEach((key, value) {
      output.writeln('$key: $value');
    });
    output.writeln('======================================');
  }

  static void logMessage(String message, {bool isError = false}) {
    final output = isError ? stderr : stdout;
    output.writeln("[spm]: $message");
  }
}
