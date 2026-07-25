import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'spm_profiler.dart';

/// Base [State] class used by SPM-instrumented Flutter widgets.
///
/// Import this class with `package:spm/spm.dart`.
abstract class SpmState<T extends StatefulWidget> extends State<T> {
  /// Unique ID for this state instance.
  String get instanceId;

  @override
  void setState(VoidCallback fn) {
    print('setState $instanceId');
    if (kProfileMode) {
      SpmProfiler.monitor(instanceId, super.setState, fn);
    } else if (kDebugMode) {
      SpmProfiler.monitorDataFlow(
        instanceId,
        super.setState,
        fn,
        context: context,
      );
    } else {
      super.setState(fn);
    }
  }
}
