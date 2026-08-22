import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Decides whether a declaration can contribute widgets to a build tree.
///
/// Two callers ask, from two different vantage points. The transplant's
/// cross-file loop has the declaration's AST in hand and asks
/// [isUiClassDeclaration], [declaresUiMember] or [returnsUi]. The dependency
/// visitor has only the resolved element, because deciding whether to resolve
/// the unit at all is exactly what it is trying to work out, and asks
/// [elementProducesUi].
///
/// Both answers have to agree, since disagreeing means the visitor enqueues a
/// declaration the loop then refuses to inline, which costs a unit resolution
/// and produces the stand-in the visitor could have requested directly.

/// Base class names that identify a UI-related class.
///
/// Used for both the fast direct-superclass check and the resolved supertype
/// scan.
const Set<String> uiBaseClasses = {
  // Widget hierarchy
  'StatelessWidget', 'StatefulWidget', 'State',
  'InheritedWidget', 'InheritedNotifier', 'InheritedModel',
  'RenderObjectWidget', 'LeafRenderObjectWidget',
  'SingleChildRenderObjectWidget', 'MultiChildRenderObjectWidget',
  'ProxyWidget', 'ParentDataWidget',
  // Painting & clipping
  'CustomPainter', 'CustomClipper',
  // Decoration & shapes
  'Decoration', 'ShapeBorder', 'BoxBorder', 'OutlinedBorder',
  'GradientTransform',
  // Text / inline content
  'InlineSpan',
  // Animation
  'Animatable',
  // Navigation
  'Route',
  // Riverpod / hooks
  'HookWidget', 'HookConsumerWidget', 'ConsumerWidget',
};

/// Return-type substrings that indicate a UI-building function.
const Set<String> uiReturnTypes = {
  'Widget',
  'CustomPainter',
  'CustomClipper',
  'Decoration',
  'BoxDecoration',
  'ShapeDecoration',
  'ShapeBorder',
  'OutlinedBorder',
  'InputDecoration',
  'InlineSpan',
  'TextSpan',
  'WidgetSpan',
  'Animatable',
  'Tween',
  'Animation',
  'Route',
  'PageRoute',
  'PreferredSizeWidget',
};

/// Whether [decl] is a UI-related class (widget, painter, decoration, etc.).
bool isUiClassDeclaration(ClassDeclaration decl) {
  // Fast path: direct superclass name is in the known set.
  final superName = decl.extendsClause?.superclass.name.lexeme;
  if (superName != null && uiBaseClasses.contains(superName)) return true;

  // Slow path: walk the resolved supertype chain to catch transitive subclasses
  // (e.g. `class MyCard extends BaseCard` where BaseCard extends
  // StatelessWidget, or `class MyPainter extends _BasePainter` where
  // _BasePainter extends CustomPainter).
  final element = _elementOfDeclaration(decl);
  if (element is InterfaceElement) return _hasUiSupertype(element);
  return false;
}

/// Whether [decl] is a `StatefulWidget`, so its companion `State` is worth
/// looking for.
bool isStatefulWidgetDeclaration(ClassDeclaration decl) {
  final superName = decl.extendsClause?.superclass.name.lexeme;
  if (superName == 'StatefulWidget') return true;
  final element = _elementOfDeclaration(decl);
  if (element is! InterfaceElement) return false;
  return element.allSupertypes.any((t) => t.element.name == 'StatefulWidget');
}

/// Whether [decl] hands out UI without being a widget itself.
///
/// A theme or helper class such as `AppStyles` is not a widget, so
/// [isUiClassDeclaration] rejects it. But `tree_extractor` walks the body of
/// every widget-returning helper a scope calls, so `AppStyles.buildDivider()`
/// contributes real widgets to the recorded features. Reducing such a class to
/// a stand-in reports zero widgets where analyzing the original project counted
/// a subtree, so it is inlined whole instead.
///
/// Matching is syntactic, on the declared return or field type. A member with
/// no annotation is not treated as UI-producing: inferring it would mean
/// resolving every member of every skipped class, and the miss is the same one
/// [returnsUi] already accepts for top-level functions.
bool declaresUiMember(ClassDeclaration decl) {
  final body = decl.body;
  if (body is! BlockClassBody) return false;
  for (final member in body.members) {
    String type = '';
    if (member is MethodDeclaration) {
      type = member.returnType?.toSource() ?? '';
    } else if (member is FieldDeclaration) {
      type = member.fields.type?.toSource() ?? '';
    }
    if (type.isEmpty || type == 'void') continue;
    if (uiReturnTypes.any(type.contains)) return true;
  }
  return false;
}

/// Whether [decl] is a function that builds UI (widgets, decorations,
/// painters, spans, routes, etc.).
bool returnsUi(FunctionDeclaration decl) {
  final returnType = decl.returnType?.toSource() ?? '';
  if (returnType.isEmpty || returnType == 'void') return false;
  return uiReturnTypes.any(returnType.contains);
}

/// The element-model counterpart of the three predicates above.
///
/// Answers the same question without an AST, so the dependency visitor can
/// decide whether a reference is worth resolving a unit for. It is deliberately
/// a little more generous than the syntactic form: an inferred return type has
/// a real type here, where `toSource()` had nothing to match against.
bool elementProducesUi(Element? element) {
  if (element == null) return false;
  if (element is EnumElement) return false;
  if (element is InterfaceElement) {
    if (_hasUiSupertype(element)) return true;
    return _declaresUiMemberElement(element);
  }
  if (element is ExecutableElement &&
      element.enclosingElement is LibraryElement) {
    return _isUiType(element.returnType);
  }
  return false;
}

/// Whether [element] or anything it extends, implements or mixes in is named in
/// [uiBaseClasses].
bool _hasUiSupertype(InterfaceElement element) {
  if (uiBaseClasses.contains(element.name)) return true;
  try {
    return element.allSupertypes.any(
      (t) => uiBaseClasses.contains(t.element.name),
    );
  } catch (_) {
    return false;
  }
}

/// Whether any declared member of [element] hands out UI.
///
/// Only the declared surface is walked, not the inherited one. An inherited
/// widget-returning member comes from a supertype, and if that supertype is
/// itself UI then [_hasUiSupertype] has already answered yes.
bool _declaresUiMemberElement(InterfaceElement element) {
  try {
    for (final method in element.methods) {
      if (_isUiType(method.returnType)) return true;
    }
    for (final field in element.fields) {
      if (field.isEnumConstant) continue;
      if (_isUiType(field.type)) return true;
    }
  } catch (_) {}
  return false;
}

/// Whether [type] is one of the UI types, or derives from one.
///
/// The supertype walk is what makes this stricter than the syntactic form in
/// the useful direction: a method declared to return `Column` matches through
/// `Widget`, where `uiReturnTypes.any(type.contains)` would have missed it.
bool _isUiType(DartType? type) {
  if (type is! InterfaceType) return false;
  final name = type.element.name;
  if (name == null || name == 'Object') return false;
  if (uiReturnTypes.contains(name)) return true;
  try {
    return type.allSupertypes.any((t) {
      final superName = t.element.name;
      return superName != null && uiReturnTypes.contains(superName);
    });
  } catch (_) {
    return false;
  }
}

/// The element behind a declaration, across the spellings the analyzer has used
/// for it.
Element? _elementOfDeclaration(ClassDeclaration decl) {
  try {
    final element = (decl as dynamic).declaredFragment?.element;
    if (element is Element) return element;
  } catch (_) {}
  try {
    final element = (decl as dynamic).declaredElement;
    if (element is Element) return element;
  } catch (_) {}
  return null;
}
