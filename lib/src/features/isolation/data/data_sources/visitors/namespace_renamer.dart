import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/flutter_namespace.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/skeletonizer.dart';

/// Renames declarations that would shadow a name `package:flutter/material.dart`
/// exports, and every reference that resolves to one.
///
/// Every isolated file imports material, so a top-level declaration sharing a
/// name with something material exports wins for the whole file, silently. The
/// old answer was to refuse to carry such a declaration and emit an empty
/// stand-in instead, which stopped the shadow carrying a body at the cost of
/// the subtree under it. Carrying it under [FlutterNamespace.mangle] keeps both:
/// the tree comes across, and `Card(...)` in the transplanted body still means
/// Flutter's `Card` unless it resolved to the other one.
///
/// The rename is keyed on the resolved element, never on the name, which is
/// what makes it safe: two `Card`s in one file are different elements, and only
/// the shadowing one is rewritten.
class NamespaceRenamer extends SourceRewriter {
  NamespaceRenamer(this._flutterNames, {required bool Function(String) isLocal})
    : _isProjectLocal = isLocal;

  final FlutterNamespace _flutterNames;

  /// Whether a path belongs to the project being isolated.
  ///
  /// A repository's own `Card` shadows Flutter's just as thoroughly, but it is
  /// the code under study: renaming it would put a name in the output that
  /// appears in no commit, and the fidelity audit compares the output against
  /// `git show`. Only a third-party declaration is renamed.
  final bool Function(String) _isProjectLocal;

  @override
  final List<Replacement> replacements = [];

  /// The names this rewriter has renamed so far, across every traversal.
  ///
  /// Not cleared by [reset], which drops edits rather than history: the caller
  /// reports this on the row, and it has to survive the whole transplant.
  final Set<String> renamed = {};

  @override
  void reset() => replacements.clear();

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _renameToken(node.namePart.typeName, _elementOf(node));
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _renameToken(node.name, _elementOf(node));
    super.visitMixinDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _renameToken(node.namePart.typeName, _elementOf(node));
    super.visitEnumDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _renameToken(node.name, _elementOf(node));
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _renameToken(node.name, node.element);
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // A member name is not a top-level name, so `widget.child` is left alone
    // even where a class called `child` would not be.
    final parent = node.parent;
    if (parent is PropertyAccess && parent.propertyName == node) return;
    if (parent is MethodInvocation && parent.methodName == node) {
      if (parent.target != null) return;
    }
    _renameToken(node.token, node.element);
  }

  void _renameToken(Token token, Element? element) {
    if (element == null) return;
    final name = element.name;
    if (name == null || name != token.lexeme) return;
    final libraryUri = _libraryUriOf(element);
    if (!_flutterNames.shadows(name, libraryUri)) return;
    final path = _sourcePathOf(element);
    if (path == null || _isProjectLocal(path)) return;

    final mangled = FlutterNamespace.mangle(name);
    renamed.add(name);
    replacements.add(Replacement(token.offset, token.length, mangled));
  }

  static Element? _elementOf(AstNode node) {
    try {
      final element = (node as dynamic).declaredFragment?.element;
      if (element is Element) return element;
    } catch (_) {}
    return null;
  }

  static String? _libraryUriOf(Element element) {
    try {
      return element.library?.identifier;
    } catch (_) {
      return null;
    }
  }

  static String? _sourcePathOf(Element element) {
    try {
      return element.firstFragment.libraryFragment?.source.fullName;
    } catch (_) {
      return null;
    }
  }
}
