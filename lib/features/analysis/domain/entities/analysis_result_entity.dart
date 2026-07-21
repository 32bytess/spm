class AnalysisResultEntity {
  final String instanceId;
  final String filePath;
  final String stateClassName;

  final int treeNonConstWidgetCount;
  final int treeMaxWidgetNestingDepth;

  /// Most expensive list-rendering strategy reachable from build():
  /// 0 = none, 1 = lazy/viewport-bounded, 2 = eager O(N).
  final int treeListRenderingStrategy;
  final bool rootBuildReturnsConstWidget;
  final int treeConstWidgetCount;
  final int helperReferenceCount;
  final bool usesLayoutDependentBuilder;
  final int treeCyclomaticComplexity;
  final int treeIterationCount;
  final int treeMaxIterationNestingDepth;

  /// Non-const widgets built per element (loops, collection-op callbacks,
  /// lazy-list builders) — the per-element cost multiplier of a rebuild.
  final int iterationWidgetCount;

  /// Non-const value-object allocations (EdgeInsets, TextStyle, ...) paid on
  /// every rebuild.
  final int valueObjectAllocCount;
  final int helperWidgetCount;
  final int helperMaxWidgetNestingDepth;

  AnalysisResultEntity({
    required this.instanceId,
    required this.filePath,
    required this.stateClassName,
    required this.treeNonConstWidgetCount,
    required this.treeMaxWidgetNestingDepth,
    required this.treeListRenderingStrategy,
    required this.rootBuildReturnsConstWidget,
    required this.treeConstWidgetCount,
    required this.helperReferenceCount,
    required this.usesLayoutDependentBuilder,
    required this.treeCyclomaticComplexity,
    required this.treeIterationCount,
    required this.treeMaxIterationNestingDepth,
    required this.iterationWidgetCount,
    required this.valueObjectAllocCount,
    required this.helperWidgetCount,
    required this.helperMaxWidgetNestingDepth,
  });
}
