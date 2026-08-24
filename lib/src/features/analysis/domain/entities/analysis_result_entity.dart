class AnalysisResultEntity {
  final String instanceId;
  final String filePath;

  /// Class name of the scope, or `'<Widget>_builder'` for a builder callback.
  final String scopeName;

  /// Kind of rebuild scope, such as `State`, `ConsumerWidget` or `BlocBuilder`.
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
  /// lazy-list builders): the per-element cost multiplier of a rebuild.
  final int iterationWidgetCount;

  /// Non-const value-object allocations such as `EdgeInsets` and `TextStyle`,
  /// paid on every rebuild.
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

  /// Files in that closure which could not be read, either unresolvable or resolved
  /// while carrying an error-severity diagnostic.
  ///
  /// Non-empty means the row is INCOMPLETE by an unknown amount: an unreadable
  /// child contributes nothing and its subtree silently vanishes from the
  /// totals, while one that resolves with errors has null types and its widgets
  /// count as value objects. Neither is visible in the scanned/skipped counts,
  /// which guard only the file being scanned. Comparing two revisions where this
  /// differs measures resolution state, not a code change.
  final List<String> unresolvedDependencies;

  /// The resolved version of every package the closure entered, by name.
  ///
  /// A package version became an input to the metrics when the extractor
  /// started reading package libraries, so this is what makes the pin to one
  /// resolved package config auditable: two runs that somehow read different
  /// versions of a package are visible rather than silent.
  final Map<String, String> packageVersions;

  /// The non-SDK classes whose build bodies were walked, as `libraryUri#Name`.
  ///
  /// One half of the agreement check against `spm isolate`, whose mapping row
  /// carries the other under `carriedUiDeclarations`. For every declaration
  /// walked here the transplant has to carry the source, or the two rows
  /// describe different trees and cannot be compared.
  final List<String> walkedWidgetClasses;

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
    this.packageVersions = const {},
    this.walkedWidgetClasses = const [],
  });
}
