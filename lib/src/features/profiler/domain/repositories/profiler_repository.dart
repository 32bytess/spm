import 'package:flutter/material.dart';
import 'package:spm/src/core/types.dart';

abstract class ProfilerRepository {
  AsyncVoidResult monitorPerformance(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logicCallback,
  );

  AsyncVoidResult monitorDataFlow(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic, {
    required BuildContext context,
  });
}
