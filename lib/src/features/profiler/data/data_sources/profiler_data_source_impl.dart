import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:spm/src/core/constants/app_constants.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/profiler/data/data_sources/helpers/profiler_helper.dart';
import 'package:spm/src/features/profiler/data/models/dataflow_metrics_model.dart';

import 'package:spm/src/features/profiler/data/models/performance_metrics_model.dart';
import 'package:spm/src/core/errors/exceptions.dart';

import 'profiler_data_source.dart';

class ProfilerDataSourceImpl implements ProfilerDataSource {
  final ProfilerHelper _helper = ProfilerHelper();
  bool _isMonitoring = false;

  @override
  AsyncVoid monitorDataFlow(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic, {
    required BuildContext context,
  }) async {
    if (!kDebugMode) {
      throw InvalidModeException(
        'DataFlow monitoring requires debug mode. '
        'Run with "flutter run" (without --profile) to use dataflow monitoring.',
      );
    }

    if (_isMonitoring) {
      throw MonitoringAlreadyActiveException(
        'DataFlow monitor is already running. Please wait for it to finish before starting a new one.',
      );
    }

    _isMonitoring = true;
    final completer = Completer<void>();
    int rebuildCount = 0;
    // Keyed by widget type name so the tally follows
    // [AppConstants.expensiveWidgets] rather than restating it. A name added to
    // that set is counted here without touching this method.
    final Map<String, int> expensiveRebuildCounts = {};
    final RebuildDirtyWidgetCallback? prevCallback = debugOnRebuildDirtyWidget;
    final Element rootElement = context as Element;

    try {
      final structMetrics = _helper.analyzeSubtree(rootElement);

      debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
        if (_helper.isDescendantOf(e, rootElement)) {
          rebuildCount++;
          final typeName = e.widget.runtimeType.toString();
          if (AppConstants.expensiveWidgets.contains(typeName)) {
            expensiveRebuildCounts.update(
              typeName,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }
        }
        if (prevCallback != null) {
          prevCallback(e, builtOnce);
        }
      };

      setStateFunc(() {
        logic();
      });

      SchedulerBinding.instance.addPostFrameCallback((_) {
        try {
          debugOnRebuildDirtyWidget = prevCallback;
          final double ratio = structMetrics.totalCount > 0
              ? rebuildCount / structMetrics.totalCount
              : 0.0;

          final data = DataflowMetricsModel(
            instanceId: instanceId,
            taintedRebuildCount: rebuildCount,
            totalWidgetCount: structMetrics.totalCount,
            maxNestingDepth: structMetrics.maxDepth,
            taintedRatio: ratio,
            opacityRebuildCount: expensiveRebuildCounts['Opacity'] ?? 0,
            shaderMaskRebuildCount: expensiveRebuildCounts['ShaderMask'] ?? 0,
            clipRRectRebuildCount: expensiveRebuildCounts['ClipRRect'] ?? 0,
            clipOvalRebuildCount: expensiveRebuildCounts['ClipOval'] ?? 0,
            clipPathRebuildCount: expensiveRebuildCounts['ClipPath'] ?? 0,
            backdropFilterRebuildCount:
                expensiveRebuildCounts['BackdropFilter'] ?? 0,
          );
          _helper.logEvent(data.toJson());

          _isMonitoring = false;
          completer.complete();
        } catch (e, st) {
          debugOnRebuildDirtyWidget = prevCallback;
          _isMonitoring = false;
          completer.completeError(
            DataflowMonitoringException(
              'Failed to compute dataflow metrics.\n Error: $e',
              st.toString(),
            ),
          );
        }
      });
    } catch (e, stackTrace) {
      debugOnRebuildDirtyWidget = prevCallback;
      _isMonitoring = false;
      throw DataflowMonitoringException(
        'DataFlow monitor failed to execute.\n Error: $e',
        stackTrace.toString(),
      );
    }

    return completer.future;
  }

  @override
  AsyncVoid monitorPerformance(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic,
  ) async {
    if (!kProfileMode) {
      throw InvalidModeException(
        'Performance monitoring requires profile mode. '
        'Run with "flutter run --profile" to use performance monitoring.',
      );
    }

    if (_isMonitoring) {
      throw MonitoringAlreadyActiveException(
        'Performance monitor is already running. Please wait for it to finish before starting a new one.',
      );
    }

    _isMonitoring = true;
    final completer = Completer<void>();
    int? targetFrameNumber;
    Timer? timeoutTimer;
    bool resolved = false;

    late void Function(List<FrameTiming>) timingCallback;

    void cleanup() {
      timeoutTimer?.cancel();
      SchedulerBinding.instance.removeTimingsCallback(timingCallback);
      _isMonitoring = false;
    }

    timingCallback = (List<FrameTiming> timings) {
      if (resolved) return;
      if (targetFrameNumber == null) return;

      for (final t in timings) {
        if (t.frameNumber != targetFrameNumber) continue;

        try {
          resolved = true;
          final data = PerformanceMetricsModel(
            instanceId: instanceId,
            buildSpan: t.buildDuration.inMicroseconds,
          );
          _helper.logEvent(data.toJson());
          debugPrint('[SPM:perf] $instanceId  buildSpan: ${data.buildSpan}µs');
          cleanup();
          completer.complete();
        } catch (e, st) {
          cleanup();
          completer.completeError(
            PerformanceMonitoringException(
              'Failed to compute performance metrics.\n Error: $e',
              st.toString(),
            ),
          );
        }
        return;
      }
    };

    try {
      SchedulerBinding.instance.addTimingsCallback(timingCallback);

      timeoutTimer = Timer(const Duration(seconds: 5), () {
        if (resolved) return;
        resolved = true;
        final data = PerformanceMetricsModel(
          instanceId: instanceId,
          buildSpan: 0,
        );
        _helper.logEvent(data.toJson());
        debugPrint('[SPM:perf] $instanceId  buildSpan: 0µs (timeout)');
        cleanup();
        completer.complete();
      });

      setStateFunc(() {
        logic();
      });

      // Fires at the end of the rebuild frame's build/layout/paint phase;
      // captures that frame's number so the timings callback can pick the
      // matching FrameTiming instead of guessing.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        targetFrameNumber =
            WidgetsBinding.instance.platformDispatcher.frameData.frameNumber;
      });
    } catch (e, st) {
      cleanup();
      throw PerformanceMonitoringException(
        'Performance monitor failed to execute.',
        st.toString(),
      );
    }

    return completer.future;
  }
}
