import 'package:analyzer/dart/ast/ast.dart';

/// Every top-level name [decl] introduces.
///
/// Most declarations introduce exactly one name, but a
/// [TopLevelVariableDeclaration] is a single node covering a whole variable
/// list, so `const a = 1, b = 2;` declares two. Callers that reduced a
/// declaration to one name had to carry a separate branch for that case, and
/// the same-file and cross-file resolution paths each grew their own copy of
/// it. Returning the set removes the special case rather than duplicating it.
///
/// Returns an empty set for a declaration that introduces no name of its own,
/// such as a `part` directive body.
Set<String> declaredNames(CompilationUnitMember decl) {
  if (decl is ClassDeclaration) return {decl.namePart.typeName.lexeme};
  if (decl is EnumDeclaration) return {decl.namePart.typeName.lexeme};
  if (decl is ExtensionTypeDeclaration) {
    // The name of an extension type sits on its primary constructor, which is
    // a `ClassNamePart`; there is no `name` on the declaration in analyzer 13.
    return {decl.primaryConstructor.typeName.lexeme};
  }
  if (decl is FunctionDeclaration) return {decl.name.lexeme};
  if (decl is MixinDeclaration) return {decl.name.lexeme};
  if (decl is GenericTypeAlias) return {decl.name.lexeme};
  if (decl is ClassTypeAlias) return {decl.name.lexeme};
  if (decl is TopLevelVariableDeclaration) {
    return {for (final v in decl.variables.variables) v.name.lexeme};
  }
  return const {};
}
