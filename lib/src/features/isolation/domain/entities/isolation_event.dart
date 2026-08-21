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

  /// How many isolated files were analysed after being written.
  ///
  /// Zero when the run had no package config to resolve `package:flutter`
  /// with, in which case nothing was verified rather than everything passing.
  final int verifiedCount;

  /// How many of the verified files carry no error-severity diagnostic.
  ///
  /// This is the number that decides whether the output is usable: `spm
  /// analyze` skips any file with an error, so a scope that was written but
  /// does not analyse contributes nothing.
  final int cleanCount;

  /// Total error-severity diagnostics across the verified files.
  final int errorCount;

  IsolationSummaryEvent({
    required this.isolatedCount,
    required this.outputDir,
    this.verifiedCount = 0,
    this.cleanCount = 0,
    this.errorCount = 0,
  });
}
