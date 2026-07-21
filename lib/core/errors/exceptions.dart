class AnalyzerInitializationException implements Exception {
  final String message;
  final String? stackTrace;
  AnalyzerInitializationException(this.message, [this.stackTrace]);
}

class AnalysisException implements Exception {
  final String message;
  final String? stackTrace;
  AnalysisException(this.message, [this.stackTrace]);
}

class FeatureExtractionException implements Exception {
  final String message;
  final String? featureName;
  final String? stackTrace;
  FeatureExtractionException(this.message, [this.featureName, this.stackTrace]);
}

class InvalidSetStateInstanceException implements Exception {
  final String message;
  InvalidSetStateInstanceException(this.message);
}

class ComplexityExtractionException implements Exception {
  final String message;
  final String? stackTrace;
  ComplexityExtractionException(this.message, [this.stackTrace]);
}

class ContextExtractionException implements Exception {
  final String message;
  final String? stackTrace;
  ContextExtractionException(this.message, [this.stackTrace]);
}

class TreeExtractionException implements Exception {
  final String message;
  final String? stackTrace;
  TreeExtractionException(this.message, [this.stackTrace]);
}

class FileWriteException implements Exception {
  final String message;
  final String? stackTrace;
  FileWriteException(this.message, [this.stackTrace]);
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
}

class FileTypeException implements Exception {
  final String message;
  FileTypeException(this.message);
}

class MonitoringAlreadyActiveException implements Exception {
  final String message;
  MonitoringAlreadyActiveException(this.message);
}

class DataflowMonitoringException implements Exception {
  final String message;
  final String? stackTrace;
  DataflowMonitoringException(this.message, [this.stackTrace]);
}

class PerformanceMonitoringException implements Exception {
  final String message;
  final String? stackTrace;
  PerformanceMonitoringException(this.message, [this.stackTrace]);
}

class InvalidModeException implements Exception {
  final String message;
  InvalidModeException(this.message);
}

class RunAppException implements Exception {
  final String message;
  final String? stackTrace;
  RunAppException(this.message, [this.stackTrace]);
}

class FlutterAnalyzeException implements Exception {
  final String message;
  FlutterAnalyzeException(this.message);
}

class StateClassNotFoundException implements Exception {
  final String message;
  StateClassNotFoundException(this.message);
}

class ValidationException implements Exception {
  final String message;
  final String? stackTrace;
  ValidationException(this.message, [this.stackTrace]);
}

class IsolationException implements Exception {
  final String message;
  final String? stackTrace;
  IsolationException(this.message, [this.stackTrace]);
}
