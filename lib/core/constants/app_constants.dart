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

  static const String importLine =
      "import 'package:spm/features/profiler/presentation/spm_profiler.dart';";

  static const String spmStateImportLine =
      "import 'package:spm/features/profiler/presentation/spm_state.dart';";

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
