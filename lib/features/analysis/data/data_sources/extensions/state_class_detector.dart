import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

bool isFlutterStateSubclass(ClassDeclaration decl) {
  if (decl.extendsClause == null) return false;

  final superType = decl.extendsClause!.superclass.type;
  if (superType is! InterfaceType) {
    // Fallback for unresolved types (common in standalone test fixtures)
    final superName = decl.extendsClause!.superclass.name.lexeme;
    return superName == 'State';
  }

  return [superType, ...superType.element.allSupertypes].any(
    (t) =>
        t.element.name == 'State' &&
        t.element.library.identifier.startsWith('package:flutter/'),
  );
}
