import 'package:spm/features/profiler/domain/entities/dataflow_metrics_entity.dart';

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

  factory DataflowMetricsModel.fromEntity(DataFlowMetricsEntity entity) =>
      DataflowMetricsModel(
        instanceId: entity.instanceId,
        taintedRebuildCount: entity.taintedRebuildCount,
        totalWidgetCount: entity.totalWidgetCount,
        maxNestingDepth: entity.maxNestingDepth,
        taintedRatio: entity.taintedRatio,
        opacityRebuildCount: entity.opacityRebuildCount,
        shaderMaskRebuildCount: entity.shaderMaskRebuildCount,
        clipRRectRebuildCount: entity.clipRRectRebuildCount,
        clipOvalRebuildCount: entity.clipOvalRebuildCount,
        clipPathRebuildCount: entity.clipPathRebuildCount,
        backdropFilterRebuildCount: entity.backdropFilterRebuildCount,
      );

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
