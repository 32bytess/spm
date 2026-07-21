class PerformanceMetricsEntity {
  final String timestamp;
  final String event = 'performance_metric';
  final String instanceId;
  final int buildSpan;

  PerformanceMetricsEntity({
    required this.instanceId,
    required this.buildSpan,
  }) : timestamp = DateTime.now().toIso8601String();
}
