import 'package:flutter/material.dart';
import 'package:spm/src/core/injection/profiler_service_locator.dart';
import 'package:spm/src/core/types.dart';

class SpmProfiler {
  /// Main profiler class for monitoring Flutter widget performance.
  ///
  /// Provides methods to monitor both performance metrics (frame timings)
  /// and dataflow metrics (widget rebuilds and tree structure).
  SpmProfiler._();

  /// Runs standard performance monitoring (Time).
  ///
  /// Monitors frame timings including total span, build duration, and
  /// raster duration. Results are logged via [SpmLogger].
  ///
  /// [instanceId] - Identifier for this monitoring session
  /// [setStateFunc] - The setState function to trigger state changes
  /// [logic] - The logic to execute that triggers the state change
  /// The in-flight performance monitor, published so an integration-test driver can
  /// await one rebuild's measurement before triggering the next. `SpmState.setState`
  /// is `void` and cannot return this future, so it is exposed here instead. Without
  /// serialising on it, a rapid second `setState` collides with the still-active
  /// monitor (`MonitoringAlreadyActiveFailure`) and that rebuild is never measured.
  static Future<void>? _current;
  static Future<void>? get current => _current;

  static AsyncVoid monitor(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic,
  ) {
    final future = _runMonitor(instanceId, setStateFunc, logic);
    _current = future;
    return future;
  }

  static AsyncVoid _runMonitor(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic,
  ) async {
    final monitorPerformanceUseCase = ProfilerDI.monitorPerformanceUseCase;
    final result = await monitorPerformanceUseCase(
      instanceId,
      setStateFunc,
      logic,
    );

    result.fold(
      (failure) {
        debugPrint(
          '[spm] Error (${failure.runtimeType}) for $instanceId: ${failure.message}',
        );
      },
      (_) {
        debugPrint('[spm] Performance monitoring completed for $instanceId');
      },
    );
  }

  /// Runs dataflow monitoring (Structure & Rebuilds).
  ///
  /// Analyzes widget tree structure and counts rebuilds triggered by
  /// state changes.
  ///
  /// [instanceId] - Identifier for this monitoring session
  /// [setStateFunc] - The setState function to trigger state changes
  /// [logic] - The logic to execute that triggers the state change
  /// [context] - BuildContext required to analyze the widget tree
  static AsyncVoid monitorDataFlow(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic, {
    required BuildContext context,
  }) async {
    final monitorDataflowUseCase = ProfilerDI.monitorDataflowUseCase;
    final result = await monitorDataflowUseCase(
      instanceId,
      setStateFunc,
      logic,
      context: context,
    );
    result.fold(
      (failure) {
        debugPrint(
          '[spm] Error (${failure.runtimeType}) for $instanceId: ${failure.message}',
        );
      },
      (_) {
        debugPrint('[spm] Dataflow monitoring completed for $instanceId');
      },
    );
  }
}
