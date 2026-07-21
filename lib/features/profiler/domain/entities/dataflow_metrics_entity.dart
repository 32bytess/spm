class DataFlowMetricsEntity {
  final String event = 'dataflow-metric';
  final String timestamp;
  final String instanceId;
  final int taintedRebuildCount;
  final int totalWidgetCount;
  final int maxNestingDepth;
  final double taintedRatio;

  // Expensive widget rebuild counts
  final int opacityRebuildCount;
  final int shaderMaskRebuildCount;
  final int clipRRectRebuildCount;
  final int clipOvalRebuildCount;
  final int clipPathRebuildCount;
  final int backdropFilterRebuildCount;

  DataFlowMetricsEntity({
    required this.instanceId,
    required this.taintedRebuildCount,
    required this.totalWidgetCount,
    required this.maxNestingDepth,
    required this.taintedRatio,
    required this.opacityRebuildCount,
    required this.shaderMaskRebuildCount,
    required this.clipRRectRebuildCount,
    required this.clipOvalRebuildCount,
    required this.clipPathRebuildCount,
    required this.backdropFilterRebuildCount,
  }) : timestamp = DateTime.now().toIso8601String();
}
