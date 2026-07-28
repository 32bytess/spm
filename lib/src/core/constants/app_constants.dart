class AppConstants {
  AppConstants._();

  static const Set<String> builtinMethods = {
    'setState',
    'print',
    'super',
    'toString',
    'hashCode',
    'forEach',
    'map',
    'where',
    'any',
    'every',
    'reduce',
    'fold',
    'expand',
    'generate',
  };

  static const Set<String> listLoopMethods = {
    'forEach',
    'map',
    'where',
    'any',
    'every',
    'reduce',
    'fold',
    'expand',
    'generate',
  };

  static const Set<String> linearCollectionOps = {
    'forEach',
    'map',
    'where',
    'any',
    'every',
    'reduce',
    'fold',
    'expand',
    'generate',
    'sort',
    'firstWhere',
    'lastWhere',
    'singleWhere',
  };

  static const expensiveWidgets = {
    'Opacity',
    'ShaderMask',
    'ClipRRect',
    'ClipOval',
    'ClipPath',
    'BackdropFilter',
  };

  static const layoutBuilders = {
    'LayoutBuilder',
    'CustomMultiChildLayout',
    'Flow',
  };

  /// Widgets whose builder callback is its own rebuild scope: the callback is
  /// re-invoked by the state-management package without the enclosing
  /// `build()` running again.
  static const Set<String> builderScopeWidgets = {
    'Consumer',
    'Selector',
    'BlocBuilder',
    'BlocSelector',
    'BlocConsumer',
    'Obx',
    'GetX',
    'GetBuilder',
    'Observer',
  };

  /// Subset of [builderScopeWidgets] that also accepts the builder as the
  /// first positional argument (e.g. `Obx(() => ...)`).
  static const Set<String> positionalBuilderScopeWidgets = {
    'Obx',
    'GetX',
    'GetBuilder',
    'Observer',
  };

  /// Scope type recorded for Flutter `State` subclasses.
  static const String stateScopeType = 'State';

  /// Scope type recorded for Riverpod/Hooks consumer widgets.
  static const String consumerWidgetScopeType = 'ConsumerWidget';

  /// Every scope type `analyze` and `isolate` can report.
  static const Set<String> rebuildScopeTypes = {
    stateScopeType,
    consumerWidgetScopeType,
    ...builderScopeWidgets,
  };

  static const String spmStateImportLine = "import 'package:spm/spm.dart';";

  static const String spmStateClassName = 'SpmState';

  /// Prefix used for console output to make parsing easier
  static const String consolePrefix = 'SPM_PROFILER:';

  static const String performanceMonitorPrefix = 'SpmProfiler.monitor(';
  static const String dataflowMonitorPrefix = 'SpmProfiler.monitorDataFlow(';

  static const String profilerClassName = 'SpmProfiler';

  /// VM service event name for profiler data
  static const String vmServiceEventName = 'ext.spm.profiler';

  /// Vm service uri regex

  static const String vmServiceUriRegExp =
      r'(?:VM service|Observatory|Flutter application).+?(https?://\S+)';
}
