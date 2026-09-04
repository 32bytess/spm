import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Whether [type] is the class named [name] or derives from it.
///
/// Both commands ask this, and they used to ask it with their own copy of the
/// same three lines: `analyze` to tell a real widget from a value object such
/// as `EdgeInsets` while counting, `isolate` to decide whether a stand-in has
/// to be shaped like a widget. Two copies of one predicate is two chances for
/// the two commands to disagree about what a widget is, and a row from each is
/// meant to describe the same tree.
///
/// A non-[InterfaceType] answers false: a type variable, a function type or an
/// unresolved reference has no supertype chain to walk.
bool isTypeNamed(DartType? type, String name) {
  if (type is! InterfaceType) return false;
  return type.element.name == name ||
      type.allSupertypes.any((t) => t.element.name == name);
}

/// The element-model counterpart of [isTypeNamed].
///
/// Answers the same question one step earlier, where only the element is in
/// hand and resolving a type would cost a unit resolution.
bool hasSupertypeNamed(InterfaceElement element, String name) {
  if (element.name == name) return true;
  return element.allSupertypes.any((t) => t.element.name == name);
}
