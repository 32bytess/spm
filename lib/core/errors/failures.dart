abstract class Failure {
  final String message;
  Failure(this.message);
}

class AnalyzerInitializationFailure extends Failure {
  AnalyzerInitializationFailure(super.message);
}

class AnalysisFailure extends Failure {
  final String? stackTrace;
  AnalysisFailure(super.message, [this.stackTrace]);
}

class FeatureExtractionFailure extends Failure {
  final String? featureName;
  final String? stackTrace;
  FeatureExtractionFailure(super.message, [this.featureName, this.stackTrace]);
}

class InvalidSetStateInstanceFailure extends Failure {
  InvalidSetStateInstanceFailure(super.message);
}

class ComplexityExtractionFailure extends Failure {
  final String? stackTrace;
  ComplexityExtractionFailure(super.message, [this.stackTrace]);
}

class ContextExtractionFailure extends Failure {
  final String? stackTrace;
  ContextExtractionFailure(super.message, [this.stackTrace]);
}

class TreeExtractionFailure extends Failure {
  final String? stackTrace;
  TreeExtractionFailure(super.message, [this.stackTrace]);
}

class UnknownFailure extends Failure {
  final String? stackTrace;
  UnknownFailure(super.message, [this.stackTrace]);
}

class FileWriteFailure extends Failure {
  final String? stackTrace;
  FileWriteFailure(super.message, [this.stackTrace]);
}

class FileNotFoundFailure extends Failure {
  final String? stackTrace;
  FileNotFoundFailure(super.message, [this.stackTrace]);
}

class FileTypeFailure extends Failure {
  final String? stackTrace;
  FileTypeFailure(super.message, [this.stackTrace]);
}

class InjectionFailure extends Failure {
  final String? stackTrace;
  InjectionFailure(super.message, [this.stackTrace]);
}

class MonitoringAlreadyActiveFailure extends Failure {
  MonitoringAlreadyActiveFailure(super.message);
}

class DataflowMonitoringFailure extends Failure {
  final String? stackTrace;
  DataflowMonitoringFailure(super.message, [this.stackTrace]);
}

class PerformanceMonitoringFailure extends Failure {
  final String? stackTrace;
  PerformanceMonitoringFailure(super.message, [this.stackTrace]);
}

class InvalidModeFailure extends Failure {
  InvalidModeFailure(super.message);
}

class RunAppFailure extends Failure {
  final String? stackTrace;
  RunAppFailure(super.message, [this.stackTrace]);
}

class FlutterAnalyzeFailure extends Failure {
  final String? stackTrace;
  FlutterAnalyzeFailure(super.message, [this.stackTrace]);
}

class IsolationFailure extends Failure {
  final String? stackTrace;
  IsolationFailure(super.message, [this.stackTrace]);
}

class ValidationFailure extends Failure {
  final String? stackTrace;
  ValidationFailure(super.message, [this.stackTrace]);
}

class CompoundFailure extends Failure {
  final List<Failure> failures;
  CompoundFailure(this.failures)
    : super(failures.map((f) => f.message).join('\n'));
}
