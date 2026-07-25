import 'package:flutter/material.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/profiler/domain/repositories/profiler_repository.dart';

class MonitorDataflowUseCase {
  final ProfilerRepository repository;

  MonitorDataflowUseCase(this.repository);

  AsyncVoidResult call(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic, {
    required BuildContext context,
  }) => repository.monitorDataFlow(
    instanceId,
    setStateFunc,
    logic,
    context: context,
  );
}
