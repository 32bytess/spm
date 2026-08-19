class AnalysisResultEntity {
  final String instanceId;
  final String filePath;

  /// Class name of the scope, or `'<Widget>_builder'` for a builder callback.
  final String scopeName;

  /// Kind of rebuild scope: `State`, `ConsumerWidget`, `BlocBuilder`, ...
  final String scopeType;

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

  /// Repo-relative files whose contents contributed to the metrics above, the
  /// declaring file included.
  ///
  /// The metrics are not a function of [filePath] alone: helpers resolve across
  /// libraries and custom child widgets have their `build()` merged in, so an
  /// edit in another file moves these numbers. Mining commit history by "touched
  /// the declaring file" therefore misses real changes, and misses them hardest
  /// where child trees are deepest.
  final List<String> dependencyFiles;

  /// Files in that closure which could not be read — unresolvable, or resolved
  /// while carrying an error-severity diagnostic.
  ///
  /// Non-empty means the row is INCOMPLETE by an unknown amount: an unreadable
  /// child contributes nothing and its subtree silently vanishes from the
  /// totals, while one that resolves with errors has null types and its widgets
  /// count as value objects. Neither is visible in the scanned/skipped counts,
  /// which guard only the file being scanned. Comparing two revisions where this
  /// differs measures resolution state, not a code change.
  final List<String> unresolvedDependencies;

  /// Whether every file the metrics depend on was read successfully.
  bool get closureResolved => unresolvedDependencies.isEmpty;

  AnalysisResultEntity({
    required this.instanceId,
    required this.filePath,
    required this.scopeName,
    required this.scopeType,
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
    this.dependencyFiles = const [],
    this.unresolvedDependencies = const [],
  });
}
