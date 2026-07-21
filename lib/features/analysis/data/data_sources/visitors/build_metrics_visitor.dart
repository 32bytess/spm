import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spm/core/constants/app_constants.dart' show AppConstants;

typedef ChildWidgetRef = ({ClassElement element, int depth});

/// A reference to a widget-returning helper discovered in a body: a direct
/// invocation (`_buildRow()`), a method tear-off (`map(_buildRow)`), or a
/// widget-returning getter (`_header`). [element] is the resolved executable
/// when available; name-based fallback resolution is used when it is null
/// (unresolved fixtures).
typedef HelperRef = ({String name, Element? element});

class BuildMetricsVisitor extends RecursiveAstVisitor<void> {
  int widgetCount = 0;
  int maxDepth = 0;

  /// Non-const widget instantiations inside a per-element scope: a loop body,
  /// a linear-collection-op callback, or the argument list of a lazy
  /// `ListView`/`GridView` constructor (`itemBuilder` runs per element).
  /// The per-element cost multiplier of a rebuild.
  int iterationWidgetCount = 0;

  /// Non-const, non-widget instance creations (`EdgeInsets`, `TextStyle`,
  /// `BoxDecoration`, ...): allocation/GC pressure paid on every rebuild.
  /// `const` value objects are canonicalized and excluded.
  int valueObjectAllocCount = 0;

  /// Most expensive list-rendering strategy seen in this body:
  /// 0 = none, 1 = lazy/viewport-bounded, 2 = eager O(N).
  int listRenderingStrategy = 0;
  bool returnsConst = false;

  int treeConstWidgetCount = 0;
  int helperReferenceCount = 0;
  List<HelperRef> helperRefs = [];

  int treeIterationCount = 0;
  int maxIterationNestingDepth = 0;

  bool usesLayoutDependentBuilder = false;

  List<ChildWidgetRef> customChildWidgets = [];

  int _currentDepth = 0;
  int _iterationDepth = 0;
  int _lazyBuilderDepth = 0;
  int _functionDepth = 0;
  bool _inReturnExpression = false;

  BuildMetricsVisitor();

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Value objects (EdgeInsets, TextStyle, BorderRadius, ...) are not widgets:
    // they carry no per-rebuild widget cost, so they are neither counted nor
    // added to the nesting depth. Still descend into their arguments so any
    // widget nested inside a value-object argument is discovered.
    if (!_isWidgetType(node.staticType)) {
      if (!node.isConst) valueObjectAllocCount++;
      node.argumentList.visitChildren(this);
      return;
    }

    _currentDepth++;
    if (_currentDepth > maxDepth) maxDepth = _currentDepth;

    final typeName = node.constructorName.type.name.lexeme;

    // Const boundary rule: a const subtree is canonicalized and skipped by
    // reconciliation, so it contributes no per-rebuild cost. Count the const
    // widget as a const unit (kept out of the non-const widgetCount), but do
    // not descend into it or recurse into a const custom child's build().
    if (node.isConst) {
      treeConstWidgetCount++;
      _currentDepth--;
      return;
    }

    widgetCount++;
    if (_iterationDepth > 0 || _lazyBuilderDepth > 0) iterationWidgetCount++;

    final element = node.constructorName.type.element;
    if (element is ClassElement && !_isFromSdk(element)) {
      customChildWidgets.add((element: element, depth: _currentDepth));
    }

    if (AppConstants.layoutBuilders.contains(typeName)) {
      usesLayoutDependentBuilder = true;
    }

    final strategy = _classifyListStrategy(node, typeName);
    if (strategy > listRenderingStrategy) listRenderingStrategy = strategy;

    // The arguments of a lazy list constructor (itemBuilder/separatorBuilder)
    // execute once per visible element: widgets inside are per-element cost.
    final lazyBuilder =
        (typeName == 'ListView' || typeName == 'GridView') &&
        _lazyListCtors.contains(node.constructorName.name?.name);
    if (lazyBuilder) _lazyBuilderDepth++;
    node.argumentList.visitChildren(this);
    if (lazyBuilder) _lazyBuilderDepth--;

    _currentDepth--;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (AppConstants.linearCollectionOps.contains(name)) {
      // A linear collection op is never a helper method, even when it yields
      // a Widget (e.g. firstWhere on a List<Widget>).
      treeIterationCount++;
      // The receiver chain runs once (chained ops are sequential, not
      // nested); only the callback arguments execute per element.
      node.target?.accept(this);
      _inIteration(() => node.argumentList.accept(this));
      return;
    }
    // `build` is never a helper: super.build(context) (keep-alive mixin) must
    // not re-enter this class's own build body via helper resolution.
    if ((_currentDepth > 0 || _inReturnExpression) &&
        name != 'build' &&
        _isWidgetType(node.staticType)) {
      helperReferenceCount++;
      helperRefs.add((name: name, element: node.methodName.element));
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _maybeCountHelperReference(node);
    super.visitSimpleIdentifier(node);
  }

  /// Counts invocation-free helper references: method tear-offs
  /// (`itemBuilder: _buildRow`, `items.map(_buildRow)`) and explicit
  /// widget-returning getters (`return _header;`). Direct invocations are
  /// counted in [visitMethodInvocation]; synthetic getters (plain widget
  /// fields) are data, not helpers, and are excluded.
  void _maybeCountHelperReference(SimpleIdentifier node) {
    if (_currentDepth == 0 && !_inReturnExpression) return;

    // The name of a direct invocation is handled by visitMethodInvocation.
    final parent = node.parent;
    if (parent is MethodInvocation && identical(parent.methodName, node)) {
      return;
    }
    // Skip declaration-site and label/constructor identifiers cheaply via the
    // element check below (they never resolve to a non-synthetic executable
    // returning Widget).
    final element = node.element;
    if (element is! ExecutableElement) return;
    // A widget field is represented by an accessor originating from a
    // variable; only explicitly declared getters are helper bodies.
    if (element is PropertyAccessorElement && !element.isOriginDeclaration) {
      return;
    }
    final name = node.name;
    if (name == 'build') return;

    final DartType returnType = element.returnType;
    // Tear-off: the reference's own static type is a function type; what
    // matters is what the executable returns when invoked per element/frame.
    if (!_isWidgetType(returnType)) return;

    helperReferenceCount++;
    helperRefs.add((name: name, element: element));
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Fires for closures and local functions only — a method's own body is
    // not a FunctionExpression. Used to keep closure returns from being
    // mistaken for the build body's root return.
    _functionDepth++;
    super.visitFunctionExpression(node);
    _functionDepth--;
  }

  @override
  void visitForStatement(ForStatement node) {
    treeIterationCount++;
    _inIteration(() => super.visitForStatement(node));
  }

  @override
  void visitForElement(ForElement node) {
    treeIterationCount++;
    _inIteration(() => super.visitForElement(node));
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    treeIterationCount++;
    _inIteration(() => super.visitWhileStatement(node));
  }

  @override
  void visitDoStatement(DoStatement node) {
    treeIterationCount++;
    _inIteration(() => super.visitDoStatement(node));
  }

  void _inIteration(void Function() visit) {
    _iterationDepth++;
    if (_iterationDepth > maxIterationNestingDepth) {
      maxIterationNestingDepth = _iterationDepth;
    }
    visit();
    _iterationDepth--;
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    // Guards: only the body's own root return counts — not a return inside a
    // closure (_functionDepth) or nested in widget arguments (_currentDepth).
    if (_functionDepth > 0) {
      super.visitReturnStatement(node);
      return;
    }
    final expr = node.expression;
    if (_currentDepth == 0 &&
        expr is InstanceCreationExpression &&
        expr.isConst) {
      returnsConst = true;
    }
    _inReturnExpression = true;
    super.visitReturnStatement(node);
    _inReturnExpression = false;
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    // Expression-bodied members (`Widget build(_) => ...;`) have no
    // ReturnStatement; treat the arrow expression as the return. Same guards
    // as visitReturnStatement: closure arrow bodies are not the root return.
    if (_functionDepth > 0) {
      super.visitExpressionFunctionBody(node);
      return;
    }
    final expr = node.expression;
    if (_currentDepth == 0 &&
        expr is InstanceCreationExpression &&
        expr.isConst) {
      returnsConst = true;
    }
    _inReturnExpression = true;
    super.visitExpressionFunctionBody(node);
    _inReturnExpression = false;
  }

  static const _flexLike = {'Column', 'Row', 'Wrap', 'Flex'};
  static const _lazyListCtors = {'builder', 'separated', 'custom'};

  /// Classifies the list-rendering strategy of a single widget instantiation.
  ///
  /// 1 (lazy): `ListView`/`GridView` `.builder`/`.separated`/`.custom`, or a
  /// `SliverList`/`SliverGrid` in any form (viewport-bounded by contract).
  ///
  /// 2 (eager): `ListView`/`GridView` fed a concrete `children:` (all children
  /// built every rebuild, no viewport culling), or a `Column`/`Row`/`Wrap`/
  /// `Flex` whose `children:` is runtime-length — a spread / `for`-element
  /// inside the literal, or any non-literal expression (`items`,
  /// `items.map(...).toList()`, `List.generate(...)`, a helper call, ...).
  /// A fixed-arity literal (`[A, B, if (c) C]`) stays 0: its cost is constant
  /// and already captured by the widget instance count.
  static int _classifyListStrategy(
    InstanceCreationExpression node,
    String typeName,
  ) {
    if (typeName == 'SliverList' || typeName == 'SliverGrid') return 1;

    final isScrollList = typeName == 'ListView' || typeName == 'GridView';
    if (isScrollList &&
        _lazyListCtors.contains(node.constructorName.name?.name)) {
      return 1;
    }

    final children = _namedArgument(node, 'children');
    if (children == null) return 0;

    if (isScrollList) return 2; // eager scroll list: O(N) regardless of shape
    if (_flexLike.contains(typeName) && _isRuntimeLengthList(children)) {
      return 2;
    }
    return 0;
  }

  static Expression? _namedArgument(
    InstanceCreationExpression node,
    String name,
  ) {
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedExpression && arg.name.label.name == name) {
        return arg.expression;
      }
    }
    return null;
  }

  /// Whether a `children:` expression produces a runtime-length widget list.
  /// Shape-based on purpose: enumerating iteration ops (`map`, `where`, ...)
  /// cannot cover bare list variables, helper calls, or spreads — any
  /// expression that is not a fixed-arity list literal is treated as O(N).
  static bool _isRuntimeLengthList(Expression expr) {
    if (expr is! ListLiteral) return true;
    // A const literal is canonicalized with its (const) contents: no
    // per-rebuild cost, so it cannot be the eager case.
    if (expr.isConst) return false;
    return expr.elements.any(_expandsCollection);
  }

  static bool _expandsCollection(CollectionElement element) {
    if (element is SpreadElement || element is ForElement) return true;
    if (element is IfElement) {
      final elseElement = element.elseElement;
      return _expandsCollection(element.thenElement) ||
          (elseElement != null && _expandsCollection(elseElement));
    }
    return false;
  }

  /// Whether [type] is `Widget` or a subtype of it. Used both to detect
  /// widget-returning helper methods and to distinguish real widgets from
  /// value objects (`EdgeInsets`, `TextStyle`, ...) during instance counting.
  static bool _isWidgetType(DartType? type) {
    if (type is! InterfaceType) return false;
    return type.element.name == 'Widget' ||
        type.allSupertypes.any((t) => t.element.name == 'Widget');
  }

  static bool _isFromSdk(ClassElement element) {
    final libraryId = element.library.identifier;
    return libraryId.startsWith('dart:') ||
        libraryId.startsWith('package:flutter/') ||
        !libraryId.contains('.');
  }
}
