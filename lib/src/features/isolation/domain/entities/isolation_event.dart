/// Base class for all isolation events.
sealed class IsolationEvent {}

/// Event emitted when a new scope is successfully isolated.
class IsolationDataEvent extends IsolationEvent {
  /// The path to the original file.
  final String originalPath;

  /// The path to the isolated file.
  final String isolatedPath;

  /// The type of the scope (e.g., 'State', 'BlocBuilder').
  final String type;

  /// The name of the isolated scope.
  final String name;

  IsolationDataEvent({
    required this.originalPath,
    required this.isolatedPath,
    required this.type,
    required this.name,
  });
}

/// Event emitted when the isolation process is complete.
class IsolationSummaryEvent extends IsolationEvent {
  /// Total number of scopes isolated.
  final int isolatedCount;

  /// The output directory where results were saved.
  final String outputDir;

  IsolationSummaryEvent({required this.isolatedCount, required this.outputDir});
}
