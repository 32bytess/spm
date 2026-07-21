import 'package:spm/features/profiler/domain/entities/performance_metrics_entity.dart';

class PerformanceMetricsModel extends PerformanceMetricsEntity {
  PerformanceMetricsModel({
    required super.instanceId,
    required super.buildSpan,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'event': event,
    'instanceId': instanceId,
    'buildSpan': buildSpan,
  };
}
