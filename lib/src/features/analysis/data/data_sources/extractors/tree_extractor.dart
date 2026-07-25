import 'dart:collection';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/analysis/data/data_sources/extensions/ast_node_extensions.dart';

import '../sets/state_class_instance_set.dart';
import '../sets/tree_features_set.dart';
import '../visitors/build_metrics_visitor.dart';

/// A custom child widget discovered during traversal, tagged with the widget
/// nesting depth at its instantiation site (used to compose absolute depth).
typedef _ChildWork = ({ClassElement element, int usageDepth});

/// A helper body queued for analysis, with the class scope its name-based
/// fallback resolution should use.
typedef _HelperWork = ({HelperRef ref, String classId, String libraryUri});

/// Everything the extractor needs from one resolved library:
/// class -> method map (methods AND getters), the raw class declarations
/// (for `extends State<W>` lookup), and top-level widget functions.
typedef _LibraryIndex = ({
  Map<String, Map<String, MethodDeclaration>> classMethods,
  Map<String, ClassDeclaration> classDecls,
  Map<String, FunctionDeclaration> topLevelFunctions,
});

class TreeExtractor {
  /// Cache libraryUri -> [_LibraryIndex]. Holds every method of every class
  /// (not just `build`) plus top-level functions, so helper bodies of recursed
  /// child widgets — and State classes of StatefulWidget children — can be
  /// resolved without re-parsing.
  final _libraryCache = <String, _LibraryIndex?>{};

  Future<TreeFeaturesSet> extract(
    StateClassInstance state, {
    required AnalysisContextCollection collection,
  }) async {
    try {
      final acc = _MetricsAccumulator();

      final buildMethod = state.buildMethod;
      if (buildMethod == null) return acc.toResult();

      // Dedup sets shared across the whole traversal.
      final visitedClasses = <String>{}; // build bodies, keyed libraryUri#class
      final analyzedHelpers = <String>{}; // helper bodies, keyed scope#member
      final queue = Queue<_ChildWork>();

      // --- Root State class: build() body ---
      acc.buildCc += buildMethod.body.cyclomaticComplexity();
      final rootVisitor = BuildMetricsVisitor();
      buildMethod.body.accept(rootVisitor);
      acc.mergeVisitor(rootVisitor, isRoot: true);

      final rootElement = state.classDeclaration.declaredFragment?.element;
      final rootClassId = _classId(rootElement);
      final rootLibraryUri = rootElement?.library.identifier ?? '<unknown>';
      visitedClasses.add(rootClassId);

      // Root helpers (resolved from the root ClassDeclaration AST directly).
      await _analyzeHelpers(
        refs: rootVisitor.helperRefs,
        methodsByName: _methodsOf(state.classDeclaration),
        classId: rootClassId,
        libraryUri: rootLibraryUri,
        collection: collection,
        acc: acc,
        queue: queue,
        analyzedHelpers: analyzedHelpers,
      );

      // Seed the BFS with the root build's direct custom children.
      for (final child in rootVisitor.customChildWidgets) {
        queue.add((element: child.element, usageDepth: child.depth));
      }

      // --- BFS over custom child widget build() bodies ---
      await _aggregateChildMetrics(
        queue: queue,
        collection: collection,
        acc: acc,
        visitedClasses: visitedClasses,
        analyzedHelpers: analyzedHelpers,
      );

      return acc.toResult();
    } on TreeExtractionException {
      rethrow;
    } catch (e, stackTrace) {
      throw TreeExtractionException(
        'Failed to extract tree metrics: $e',
        stackTrace.toString(),
      );
    }
  }

  /// Clears the library cache. Call between unrelated analysis runs.
  void clearCache() => _libraryCache.clear();

  /// Analyzes the widget-returning helpers referenced by one body.
  ///
  /// Each helper body contributes ALL of its cost signals: widgets (const
  /// **included**) into [_MetricsAccumulator.helperWidgetCount], widget depth
  /// into helperMaxDepth, iteration count/depth, list-rendering strategy,
  /// layout-dependent builders, and its decision points (cyclomatic
  /// complexity − 1, so the shared +1 base is not re-added per helper).
  /// Custom child widgets it instantiates are enqueued so their build() trees
  /// still count. Helper→helper chains are followed transitively.
  ///
  /// Resolution: element-based when the reference resolved — methods/getters
  /// of any class (same or other library) and top-level widget functions all
  /// work. Name-in-current-class is the fallback for unresolved references.
  /// Local functions are skipped: their bodies are lexically inside the
  /// visited body and already counted.
  Future<void> _analyzeHelpers({
    required List<HelperRef> refs,
    required Map<String, MethodDeclaration> methodsByName,
    required String classId,
    required String libraryUri,
    required AnalysisContextCollection collection,
    required _MetricsAccumulator acc,
    required Queue<_ChildWork> queue,
    required Set<String> analyzedHelpers,
  }) async {
    final pending = Queue<_HelperWork>();
    for (final ref in refs) {
      pending.add((ref: ref, classId: classId, libraryUri: libraryUri));
    }

    while (pending.isNotEmpty) {
      final work = pending.removeFirst();
      final resolved = await _resolveHelperBody(work, collection);
      if (resolved == null) continue;
      if (!analyzedHelpers.add(resolved.dedupKey)) continue;

      final v = BuildMetricsVisitor();
      resolved.body.accept(v);

      // Helper widget count includes const widgets (the const-in-helper case).
      acc.helperWidgetCount += v.widgetCount + v.treeConstWidgetCount;
      if (v.maxDepth > acc.helperMaxDepth) acc.helperMaxDepth = v.maxDepth;
      acc.treeIterationCount += v.treeIterationCount;
      acc.iterationWidgetCount += v.iterationWidgetCount;
      acc.valueObjectAllocCount += v.valueObjectAllocCount;
      if (v.maxIterationNestingDepth > acc.maxIterationNestingDepth) {
        acc.maxIterationNestingDepth = v.maxIterationNestingDepth;
      }
      if (v.listRenderingStrategy > acc.listRenderingStrategy) {
        acc.listRenderingStrategy = v.listRenderingStrategy;
      }
      acc.layoutBuilder = acc.layoutBuilder || v.usesLayoutDependentBuilder;
      acc.buildCc += resolved.body.cyclomaticComplexity() - 1;

      // Custom widgets built inside a helper still contribute their build tree.
      // Their absolute depth is measured from 0 (helper nesting is tracked
      // separately via helperMaxDepth, not composed into build depth).
      for (final child in v.customChildWidgets) {
        queue.add((element: child.element, usageDepth: 0));
      }

      // Follow helper -> helper chains, scoped to the resolved helper's class.
      for (final ref in v.helperRefs) {
        pending.add((
          ref: ref,
          classId: resolved.scopeClassId,
          libraryUri: resolved.libraryUri,
        ));
      }
    }
  }

  /// Resolves one helper reference to its body. Returns null when the target
  /// is a local function (already counted lexically), is unresolvable, or is
  /// not found in the fallback scope.
  Future<
    ({
      FunctionBody body,
      String dedupKey,
      String scopeClassId,
      String libraryUri,
    })?
  >
  _resolveHelperBody(
    _HelperWork work,
    AnalysisContextCollection collection,
  ) async {
    final element = work.ref.element;
    final name = work.ref.name;

    if (element is LocalFunctionElement) return null;

    if (element is ExecutableElement) {
      final enclosing = element.enclosingElement;
      final targetLibraryUri = element.library.identifier;
      final index = await _indexLibrary(targetLibraryUri, collection);
      if (index == null) return null;

      if (enclosing is InterfaceElement) {
        final className = enclosing.name;
        final method = index.classMethods[className]?[name];
        if (method == null) return null;
        final scopeClassId = '$targetLibraryUri#$className';
        return (
          body: method.body,
          dedupKey: '$scopeClassId#$name',
          scopeClassId: scopeClassId,
          libraryUri: targetLibraryUri,
        );
      }
      // Top-level widget function (or top-level getter).
      final fn = index.topLevelFunctions[name];
      if (fn == null) return null;
      return (
        body: fn.functionExpression.body,
        dedupKey: '$targetLibraryUri##$name',
        scopeClassId: '$targetLibraryUri#',
        libraryUri: targetLibraryUri,
      );
    }

    // Unresolved (standalone fixtures): fall back to a same-class name lookup.
    final index = await _indexLibrary(work.libraryUri, collection);
    final className = work.classId.split('#').last;
    final method = index?.classMethods[className]?[name];
    if (method == null) return null;
    return (
      body: method.body,
      dedupKey: '${work.classId}#$name',
      scopeClassId: work.classId,
      libraryUri: work.libraryUri,
    );
  }

  /// BFS over custom child widgets: each class's `build()` merges into the
  /// non-root metrics, its helpers are analyzed, and its children are enqueued.
  /// A StatefulWidget child has no `build()` of its own — its State class's
  /// `build()` is what reruns on rebuild, so that is what gets analyzed.
  AsyncVoid _aggregateChildMetrics({
    required Queue<_ChildWork> queue,
    required AnalysisContextCollection collection,
    required _MetricsAccumulator acc,
    required Set<String> visitedClasses,
    required Set<String> analyzedHelpers,
  }) async {
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final element = current.element;

      final widgetClassId = _classId(element);
      if (!visitedClasses.add(widgetClassId)) continue;

      final libraryUri = element.library.identifier;
      final index = await _indexLibrary(libraryUri, collection);
      if (index == null) continue;

      final widgetName = element.name;
      var buildClassName = widgetName;
      var buildMethod = index.classMethods[widgetName]?['build'];

      if (buildMethod == null && widgetName != null) {
        // StatefulWidget: find its State class and use that build().
        final stateName = _stateClassNameOf(widgetName, index);
        if (stateName == null) continue;
        final stateClassId = '$libraryUri#$stateName';
        if (!visitedClasses.add(stateClassId)) continue;
        buildClassName = stateName;
        buildMethod = index.classMethods[stateName]?['build'];
      }
      if (buildMethod == null || buildClassName == null) continue;

      final buildScopeId = '$libraryUri#$buildClassName';
      final visitor = BuildMetricsVisitor();
      buildMethod.body.accept(visitor);
      acc.buildCc += buildMethod.body.cyclomaticComplexity();

      acc.mergeVisitor(visitor, isRoot: false);

      // Update max depth with absolute position of this child's subtree.
      final childAbsoluteDepth = current.usageDepth + visitor.maxDepth;
      acc.updateMaxDepth(childAbsoluteDepth);

      // Analyze this child's own helper methods.
      await _analyzeHelpers(
        refs: visitor.helperRefs,
        methodsByName: index.classMethods[buildClassName] ?? const {},
        classId: buildScopeId,
        libraryUri: libraryUri,
        collection: collection,
        acc: acc,
        queue: queue,
        analyzedHelpers: analyzedHelpers,
      );

      // Enqueue grandchildren from this build body.
      for (final grandchild in visitor.customChildWidgets) {
        queue.add((
          element: grandchild.element,
          // [grandchild.depth] is already its exact position in this build
          // body. Adding visitor.maxDepth here would count the parent's
          // deepest (possibly unrelated) branch a second time.
          usageDepth: current.usageDepth + grandchild.depth,
        ));
      }
    }
  }

  /// Finds the State class name of a StatefulWidget: first from the
  /// instantiation inside `createState()` (`=> _FooState();`), then by
  /// scanning the library for a class declared `extends State<Widget>`.
  String? _stateClassNameOf(String widgetName, _LibraryIndex index) {
    final createState = index.classMethods[widgetName]?['createState'];
    if (createState != null) {
      final finder = _InstanceCreationFinder();
      createState.body.accept(finder);
      final created = finder.firstTypeName;
      if (created != null && index.classDecls.containsKey(created)) {
        return created;
      }
    }
    for (final entry in index.classDecls.entries) {
      final superclass = entry.value.extendsClause?.superclass;
      if (superclass == null || superclass.name.lexeme != 'State') continue;
      final args = superclass.typeArguments?.arguments;
      if (args != null &&
          args.whereType<NamedType>().any((t) => t.name.lexeme == widgetName)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Stable identity for a class element (`libraryUri#ClassName`).
  String _classId(ClassElement? element) => element == null
      ? '<unknown>'
      : '${element.library.identifier}#${element.name}';

  /// Builds a `memberName -> MethodDeclaration` map (methods and getters) for
  /// a class AST node.
  Map<String, MethodDeclaration> _methodsOf(ClassDeclaration classDecl) {
    final map = <String, MethodDeclaration>{};
    final body = classDecl.body;
    if (body is! BlockClassBody) return map;
    for (final member in body.members) {
      if (member is MethodDeclaration && !member.isSetter) {
        map[member.name.lexeme] = member;
      }
    }
    return map;
  }

  /// Resolves and indexes a library by URI using cached lookups.
  Future<_LibraryIndex?> _indexLibrary(
    String libraryUri,
    AnalysisContextCollection collection,
  ) async {
    if (_libraryCache.containsKey(libraryUri)) {
      return _libraryCache[libraryUri];
    }

    final filePath = _resolveFilePath(libraryUri, collection);
    if (filePath == null) return _libraryCache[libraryUri] = null;

    try {
      final context = collection.contextFor(filePath);
      final session = context.currentSession;
      final definingUnit = await session.getResolvedUnit(filePath);
      if (definingUnit is! ResolvedUnitResult) {
        return _libraryCache[libraryUri] = null;
      }

      final classMethods = <String, Map<String, MethodDeclaration>>{};
      final classDecls = <String, ClassDeclaration>{};
      final topLevelFunctions = <String, FunctionDeclaration>{};

      // A library element exposes the defining unit and all of its `part`
      // fragments. Resolve only those units individually; resolving the whole
      // library for every lookup is substantially more expensive.
      for (final fragment in definingUnit.libraryElement.fragments) {
        final fragmentPath = fragment.source.fullName;
        final unitResult = fragmentPath == definingUnit.path
            ? definingUnit
            : await session.getResolvedUnit(fragmentPath);
        if (unitResult is! ResolvedUnitResult) continue;

        for (final declaration in unitResult.unit.declarations) {
          if (declaration is ClassDeclaration) {
            final className = declaration.namePart.typeName.lexeme;
            classMethods[className] = _methodsOf(declaration);
            classDecls[className] = declaration;
          } else if (declaration is FunctionDeclaration &&
              !declaration.isSetter) {
            topLevelFunctions[declaration.name.lexeme] = declaration;
          }
        }
      }

      return _libraryCache[libraryUri] = (
        classMethods: classMethods,
        classDecls: classDecls,
        topLevelFunctions: topLevelFunctions,
      );
    } catch (_) {
      // Cache the miss to avoid re-trying failed files.
      return _libraryCache[libraryUri] = null;
    }
  }

  /// Resolves a library URI to an absolute file path.
  String? _resolveFilePath(
    String libraryUri,
    AnalysisContextCollection collection,
  ) {
    // Handle file:// URIs directly.
    if (libraryUri.startsWith('file://')) {
      return Uri.parse(libraryUri).toFilePath();
    }

    // For package: URIs, find the context that can resolve it.
    for (final context in collection.contexts) {
      final uri = Uri.tryParse(libraryUri);
      if (uri == null) continue;

      final source = context.currentSession.uriConverter.uriToPath(uri);
      if (source != null) return source;
    }

    return null;
  }
}

/// Finds the first instance creation in a body (used on `createState()`).
class _InstanceCreationFinder extends RecursiveAstVisitor<void> {
  String? firstTypeName;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    firstTypeName ??= node.constructorName.type.name.lexeme;
  }
}

class _MetricsAccumulator {
  int widgetCount = 0;
  int maxDepth = 0;
  int listRenderingStrategy = 0;
  bool returnsConst = false;
  int treeConstWidgetCount = 0;
  int helperCount = 0;
  bool layoutBuilder = false;
  int buildCc = 0;
  int treeIterationCount = 0;
  int maxIterationNestingDepth = 0;
  int iterationWidgetCount = 0;
  int valueObjectAllocCount = 0;
  int helperWidgetCount = 0;
  int helperMaxDepth = 0;

  void mergeVisitor(BuildMetricsVisitor visitor, {required bool isRoot}) {
    widgetCount += visitor.widgetCount;
    treeConstWidgetCount += visitor.treeConstWidgetCount;
    helperCount += visitor.helperReferenceCount;
    treeIterationCount += visitor.treeIterationCount;
    iterationWidgetCount += visitor.iterationWidgetCount;
    valueObjectAllocCount += visitor.valueObjectAllocCount;
    // Lexical nesting only: depth is taken as the max across build bodies,
    // not composed across instantiation sites (a child created inside a
    // parent loop is not treated as nesting the child's own loops).
    if (visitor.maxIterationNestingDepth > maxIterationNestingDepth) {
      maxIterationNestingDepth = visitor.maxIterationNestingDepth;
    }

    if (visitor.listRenderingStrategy > listRenderingStrategy) {
      listRenderingStrategy = visitor.listRenderingStrategy;
    }
    layoutBuilder = layoutBuilder || visitor.usesLayoutDependentBuilder;

    if (isRoot) {
      maxDepth = visitor.maxDepth;
      returnsConst = visitor.returnsConst;
    }
  }

  void updateMaxDepth(int depth) {
    if (depth > maxDepth) maxDepth = depth;
  }

  TreeFeaturesSet toResult() => (
    treeNonConstWidgetCount: widgetCount,
    treeMaxWidgetNestingDepth: maxDepth,
    treeListRenderingStrategy: listRenderingStrategy,
    rootBuildReturnsConstWidget: returnsConst,
    treeConstWidgetCount: treeConstWidgetCount,
    helperReferenceCount: helperCount,
    usesLayoutDependentBuilder: layoutBuilder,
    treeCyclomaticComplexity: buildCc,
    treeIterationCount: treeIterationCount,
    treeMaxIterationNestingDepth: maxIterationNestingDepth,
    iterationWidgetCount: iterationWidgetCount,
    valueObjectAllocCount: valueObjectAllocCount,
    helperWidgetCount: helperWidgetCount,
    helperMaxWidgetNestingDepth: helperMaxDepth,
  );
}
