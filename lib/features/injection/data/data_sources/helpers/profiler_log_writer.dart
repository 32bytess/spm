import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/core/types.dart';

/// Writes profiler JSON events to a JSONL output file.
///
/// Usage:
/// ```dart
/// final writer = ProfilerLogWriter('output.jsonl');
/// writer.write({'timestamp': '...', 'metric': 42});
/// await writer.close();
/// ```
///
class ProfilerLogWriter {
  final String outputPath;
  final IOSink _sink;
  int _eventCount = 0;

  ProfilerLogWriter(this.outputPath) : _sink = _openSink(outputPath);

  static IOSink _openSink(String outputPath) {
    Directory(p.dirname(outputPath)).createSync(recursive: true);
    return File(outputPath).openWrite();
  }

  /// Number of events written so far.
  int get eventCount => _eventCount;

  /// Writes a single profiler event as a JSON line.
  void write(Map<String, dynamic> data) {
    _sink.writeln(jsonEncode(data));
    _eventCount++;
  }

  /// Flushes and closes the underlying file.
  AsyncVoid close() async {
    await _sink.flush();
    await _sink.close();
  }
}
