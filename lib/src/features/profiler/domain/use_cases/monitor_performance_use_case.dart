import 'package:flutter/material.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/profiler/domain/repositories/profiler_repository.dart';

class MonitorPerformanceUseCase {
  final ProfilerRepository repository;

  MonitorPerformanceUseCase(this.repository);

  AsyncVoidResult call(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic,
  ) => repository.monitorPerformance(instanceId, setStateFunc, logic);
}
