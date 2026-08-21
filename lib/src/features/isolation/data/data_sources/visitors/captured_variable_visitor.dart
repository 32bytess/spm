import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

/// A name a rebuild scope reads without declaring it.
class CapturedVariable {
  /// The identifier as it appears in the scope.
  final String name;

  /// The declared type, rendered for use in a field declaration.
  final String type;

  /// Offset of the binding's declaration, used to keep source order stable.
  final int order;

  const CapturedVariable(this.name, this.type, this.order);
}

/// Collects the variables a rebuild scope captures from its surroundings.
///
/// A builder callback such as `BlocBuilder(builder: (context, state) {})`
/// may read parameters and locals of the method it sits in, or members it
/// inherits from a base class supplied by a package. Neither binding travels
/// with the scope when it is transplanted, so the isolated file ends up
/// referencing names that nothing declares.
///
/// Two kinds are collected:
///
///  * **Enclosing locals and parameters**, resolved to a [LocalVariableElement]
///    or [FormalParameterElement] whose declaration sits outside the scope's
///    source range. `bool onlyNKN` on the method wrapping a `BlocBuilder` is
///    the canonical case.
///  * **Members inherited from a foreign supertype**: a getter or field whose
///    enclosing class lives outside the project, as `controller` does on
///    `GetView` from `package:get`. The transplant never emits such a class, so
///    the member has to become a field of its own.
///
/// Names declared inside the scope, members of the enclosing class (the
/// transplant copies those verbatim) and top-level declarations (the dependency
/// extractor already follows those) are all left alone.
class CapturedVariableVisitor extends RecursiveAstVisitor<void> {
  /// [scopeOffset] and [scopeEnd] bound the transplanted source range.
  CapturedVariableVisitor(
    this.result,
    this.scopeOffset,
    this.scopeEnd, {
    Set<String> ignore = const {},
  }) : _ignore = ignore;

  /// Analysis result for the file the scope was found in.
  final ResolvedUnitResult result;

  /// Start offset of the scope being transplanted.
  final int scopeOffset;

  /// End offset of the scope being transplanted.
  final int scopeEnd;

  /// Names already emitted by the caller, such as lifted parameters and
  /// `context`.
  final Set<String> _ignore;

  final Map<String, CapturedVariable> _found = {};
  final Map<String, CapturedVariable> _globals = {};

  /// Captured variables in declaration order, deduplicated by name.
  List<CapturedVariable> get captured {
    final list = _found.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// Top-level variables the scope reads from another file in the project.
  ///
  /// These are mutable application-wide handles, of which nMobile's
  /// `application` service locator is the recurring case. The extractor drops
  /// because they are not widgets, so the isolated file has to seed them
  /// itself. They are not lifted to fields: the declaration stays top-level, so
  /// only an assignment is needed.
  ///
  /// The declared type travels with the name because the isolated file may have
  /// to declare the handle as well as seed it, and nothing else in the
  /// transplant knows what type `application` had.
  List<CapturedVariable> get capturedGlobals {
    final list = _globals.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);

    if (node.inDeclarationContext()) return;
    final name = node.name;
    if (name.isEmpty || name == 'context' || _ignore.contains(name)) return;
    if (_found.containsKey(name)) return;

    // A qualified reference (`foo.bar`, `foo.bar()`) says nothing about `bar`
    // being free. Only the target matters, and it is visited separately.
    if (_isQualifiedTail(node)) return;

    final element = _elementOf(node);
    if (element == null) return;

    if (element is LocalVariableElement || element is FormalParameterElement) {
      final offset = _declarationOffset(element);
      // Declared inside the scope: it travels with the transplanted code.
      if (offset != null && offset >= scopeOffset && offset < scopeEnd) return;
      final type = _typeOf(element);
      if (type == null) return;
      _found[name] = CapturedVariable(name, type, offset ?? scopeOffset);
      return;
    }

    if (_isForeignInstanceMember(element)) {
      final type = _typeOf(element);
      if (type == null) return;
      _found[name] = CapturedVariable(name, type, _found.length);
      return;
    }

    if (_isCrossFileProjectGlobal(element)) {
      // An uninformative type drops a lifted field above, because a field
      // pinned to nothing is not worth emitting. A global cannot be dropped
      // the same way: the generated `initState` assigns to it either way, so
      // it has to be declared, and `dynamic` is the honest declaration.
      //
      // `order` goes unused, because [capturedGlobals] sorts by name, but the
      // record is shared with lifted fields, which do rely on it.
      _globals[name] = CapturedVariable(
        name,
        _typeOf(element) ?? 'dynamic',
        _globals.length,
      );
    }
  }

  /// True for a top-level variable declared in another file of this project.
  ///
  /// Same-file top-level declarations are copied across verbatim by the
  /// dependency extractor, so those need no seeding.
  bool _isCrossFileProjectGlobal(Element element) {
    Element? target = element;
    if (target is PropertyAccessorElement) {
      final enclosing = target.enclosingElement;
      // A getter on a class is a member, not a global.
      if (enclosing is InterfaceElement) return false;
      target = target.variable;
    }
    if (target is! TopLevelVariableElement) return false;

    // Only mutable handles need seeding. A `final`/`const` top-level carries
    // its value in its own declaration, so whoever supplies the declaration
    // supplies the value too. Assigning to it would not even compile.
    if (target.isFinal || target.isConst) return false;

    final uri = _libraryUri(target);
    if (uri == null) return false;
    if (uri.startsWith('dart:') || uri.startsWith('package:flutter')) {
      return false;
    }
    if (!_isProjectLocal(uri)) return false;

    return _resolveToPath(uri) != result.path;
  }

  /// True when [node] is the trailing name of a qualified expression, i.e. the
  /// `bar` of `foo.bar`, a named-argument label, or a named constructor.
  bool _isQualifiedTail(SimpleIdentifier node) {
    final parent = node.parent;
    if (parent is PropertyAccess && identical(parent.propertyName, node)) {
      return true;
    }
    if (parent is PrefixedIdentifier && identical(parent.identifier, node)) {
      return true;
    }
    if (parent is MethodInvocation &&
        identical(parent.methodName, node) &&
        parent.realTarget != null) {
      return true;
    }
    if (parent is Label) return true;
    if (parent is ConstructorName) return true;
    if (parent is NamedType) return true;
    return false;
  }

  /// True for a getter or field inherited from a third-party class, something
  /// the transplant will never emit, such as `GetView.controller`.
  ///
  /// Members from `package:flutter` and `dart:` are excluded: the isolated file
  /// imports those, so `widget`, `mounted` and `context` on [State] resolve
  /// there and must not be shadowed by a field. Members of project classes are
  /// excluded too, since the dependency extractor already copies those.
  bool _isForeignInstanceMember(Element element) {
    final bool isMember =
        element is PropertyAccessorElement || element is FieldElement;
    if (!isMember) return false;

    final enclosing = element.enclosingElement;
    if (enclosing is! InterfaceElement) return false;

    final uri = _libraryUri(enclosing);
    if (uri == null) return false;
    if (uri.startsWith('dart:') || uri.startsWith('package:flutter')) {
      return false;
    }
    return !_isProjectLocal(uri);
  }

  /// Whether [libraryUri] resolves to a file inside the analysed project.
  ///
  /// A project library is routinely reached through its own `package:` URI, so
  /// the session's URI converter has to run before the path comparison.
  /// Otherwise every `package:` import looks third-party.
  bool _isProjectLocal(String libraryUri) {
    final path = _resolveToPath(libraryUri);
    if (path == null) return false;
    final root = result.session.analysisContext.contextRoot.root.path;
    return p.isWithin(root, path) || p.equals(root, path);
  }

  /// Maps a library URI to a file path, resolving `package:` through the
  /// session's converter. Returns null when it cannot be resolved.
  String? _resolveToPath(String libraryUri) {
    if (libraryUri.startsWith('/')) return libraryUri;
    if (libraryUri.startsWith('file:')) {
      return Uri.parse(libraryUri).toFilePath();
    }
    if (libraryUri.startsWith('package:')) {
      try {
        final dynamic converter = (result.session as dynamic).uriConverter;
        return converter?.uriToPath(Uri.parse(libraryUri)) as String?;
      } catch (_) {}
    }
    return null;
  }

  /// Canonical URI of the library declaring [element] (`package:get/get.dart`,
  /// `dart:ui`, or an absolute path for a file not reached through a package).
  String? _libraryUri(Element element) {
    try {
      return element.library?.identifier;
    } catch (_) {
      return null;
    }
  }

  /// Offset of an element's own declaration, or null when unavailable.
  int? _declarationOffset(Element element) {
    try {
      return (element as dynamic).firstFragment?.nameOffset as int?;
    } catch (_) {
      return null;
    }
  }

  /// Renders an element's type for use in a field declaration.
  ///
  /// A getter's `type` is its *function* type (`Controller Function()`), not
  /// the value it yields, so accessors have to be read through `returnType`.
  /// Reading `type` first would send every inherited getter into the
  /// `Function` guard below and drop it silently, with `GetView`'s
  /// `T get controller` the common casualty.
  String? _typeOf(Element element) {
    try {
      final dynamic typed = element;
      final dynamic type = element is PropertyAccessorElement
          ? typed.returnType
          : (typed.type ?? typed.returnType);
      if (type == null) return null;
      final display = type.getDisplayString() as String;
      // These carry no information worth pinning a field to.
      if (display.isEmpty ||
          display == 'dynamic' ||
          display == 'Object' ||
          display == 'Object?' ||
          display == 'void' ||
          display.contains('Function')) {
        return null;
      }
      return display;
    } catch (_) {
      return null;
    }
  }

  Element? _elementOf(SimpleIdentifier node) {
    final dynamic n = node;
    try {
      final e = n.element;
      if (e != null) return e as Element;
    } catch (_) {}
    try {
      final e = n.staticElement;
      if (e != null) return e as Element;
    } catch (_) {}
    return null;
  }
}
