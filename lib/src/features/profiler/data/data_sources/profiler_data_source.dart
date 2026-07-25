import 'package:flutter/material.dart';
import 'package:spm/src/core/types.dart';

abstract class ProfilerDataSource {
  AsyncVoid monitorPerformance(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic,
  );

  AsyncVoid monitorDataFlow(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic, {
    required BuildContext context,
  });
}
