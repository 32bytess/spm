import 'package:spm/src/features/profiler/domain/entities/dataflow_metrics_entity.dart';

class DataflowMetricsModel extends DataFlowMetricsEntity {
  DataflowMetricsModel({
    required super.instanceId,
    required super.taintedRebuildCount,
    required super.totalWidgetCount,
    required super.maxNestingDepth,
    required super.taintedRatio,
    required super.opacityRebuildCount,
    required super.shaderMaskRebuildCount,
    required super.clipRRectRebuildCount,
    required super.clipOvalRebuildCount,
    required super.clipPathRebuildCount,
    required super.backdropFilterRebuildCount,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'event': event,
    'instanceId': instanceId,
    'taintedRebuildCount': taintedRebuildCount,
    'totalWidgetCount': totalWidgetCount,
    'maxNestingDepth': maxNestingDepth,
    'taintedRatio': taintedRatio,
    'opacityRebuildCount': opacityRebuildCount,
    'shaderMaskRebuildCount': shaderMaskRebuildCount,
    'clipRRectRebuildCount': clipRRectRebuildCount,
    'clipOvalRebuildCount': clipOvalRebuildCount,
    'clipPathRebuildCount': clipPathRebuildCount,
    'backdropFilterRebuildCount': backdropFilterRebuildCount,
  };
}
