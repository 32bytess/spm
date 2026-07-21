import 'package:flutter/material.dart';
import 'package:spm/core/types.dart';
import 'package:spm/features/profiler/domain/repositories/profiler_repository.dart';

class MonitorPerformanceUseCase {
  final ProfilerRepository repository;

  MonitorPerformanceUseCase(this.repository);

  AsyncVoidResult call(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic,
  ) => repository.monitorPerformance(instanceId, setStateFunc, logic);
}
