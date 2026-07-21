import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class CountingVisitor extends GeneralizingAstVisitor<void> {
  final void Function(AstNode) onEach;

  CountingVisitor(this.onEach);

  @override
  void visitNode(AstNode node) {
    onEach(node);
    super.visitNode(node);
  }
}
