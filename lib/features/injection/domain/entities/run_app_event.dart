/// Events emitted during a Flutter app run with profiler data collection.
sealed class RunAppEvent {}

/// Emitted when the CLI connects (or fails to connect) to the Dart VM service.
class VmServiceConnectionEvent extends RunAppEvent {
  final bool connected;
  VmServiceConnectionEvent({required this.connected});
}

/// Emitted each time a profiler event is captured from the VM service.
class ProfilerDataEvent extends RunAppEvent {
  final Map<String, dynamic> data;
  ProfilerDataEvent(this.data);
}

/// Final event with run metadata, emitted just before the stream closes.
class RunCompletedEvent extends RunAppEvent {
  /// Number of profiler events captured via the VM service.
  final int eventCount;

  /// Whether the CLI successfully connected to the Dart VM service.
  final bool vmServiceConnected;

  /// The output file path where profiler data was saved, if any.
  final String? outputPath;

  /// The exit code of the Flutter process.
  final int exitCode;

  RunCompletedEvent({
    required this.eventCount,
    required this.vmServiceConnected,
    this.outputPath,
    required this.exitCode,
  });
}
