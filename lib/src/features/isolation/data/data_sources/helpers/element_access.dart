import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

/// The element behind an AST node, across the spellings the analyzer has used
/// for it.
///
/// The accessor has been renamed twice within the version range this package
/// supports, and which one exists depends on the analyzer resolved into the
/// consuming project rather than on anything here. So each is probed in turn
/// through `dynamic` and the first that answers wins.
///
/// Order matters and is deliberate: the current spellings come first and the
/// deprecated `staticElement` last, so a node that answers to both is read
/// through the accessor that is not on its way out.
Element? elementOf(Object? node) {
  if (node == null) return null;
  final dynamic n = node;
  try {
    final e = n.element;
    if (e is Element) return e;
  } catch (_) {}
  try {
    final e = n.element2;
    if (e is Element) return e;
  } catch (_) {}
  try {
    final e = n.staticElement;
    if (e is Element) return e;
  } catch (_) {}
  return null;
}

/// The element behind a declaration, on the same terms as [elementOf].
///
/// A declaration answers to its own pair of accessors rather than the ones
/// [elementOf] probes, so it gets its own entry point.
Element? elementOfDeclaration(ClassDeclaration decl) {
  final dynamic d = decl;
  try {
    final e = d.declaredFragment?.element;
    if (e is Element) return e;
  } catch (_) {}
  try {
    final e = d.declaredElement;
    if (e is Element) return e;
  } catch (_) {}
  return null;
}
