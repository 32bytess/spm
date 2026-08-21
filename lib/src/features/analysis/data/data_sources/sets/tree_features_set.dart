typedef TreeFeaturesSet = ({
  int treeNonConstWidgetCount,
  int treeMaxWidgetNestingDepth,

  /// 0 = none, 1 = lazy/viewport-bounded, 2 = eager O(N); max across the tree.
  int treeListRenderingStrategy,
  bool rootBuildReturnsConstWidget,
  int treeConstWidgetCount,
  int helperReferenceCount,
  bool usesLayoutDependentBuilder,
  int treeCyclomaticComplexity,
  int treeIterationCount,
  int treeMaxIterationNestingDepth,

  /// Non-const widgets built per element (loops, collection-op callbacks,
  /// lazy-list builders): the per-element cost multiplier.
  int iterationWidgetCount,

  /// Non-const value-object allocations such as `EdgeInsets` and `TextStyle`,
  /// paid on every rebuild.
  int valueObjectAllocCount,
  int helperWidgetCount,
  int helperMaxWidgetNestingDepth,
});
