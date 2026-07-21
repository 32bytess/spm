import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class StateClassFinderVisitor extends RecursiveAstVisitor<void> {
  final String className;
  ClassDeclaration? match;

  StateClassFinderVisitor(this.className);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.namePart.typeName.lexeme == className) {
      match = node;
    }
    super.visitClassDeclaration(node);
  }
}
