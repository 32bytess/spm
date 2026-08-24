import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class CountingVisitor extends GeneralizingAstVisitor<void> {
  final void Function(AstNode) onEach;

  /// Nodes whose whole subtree is out of scope. Suppressing the count of the
  /// matched node alone would leave everything inside it counted, which is how
  /// a predicate matching a callback would still charge the callback's body.
  final bool Function(AstNode)? skip;

  CountingVisitor(this.onEach, {this.skip});

  @override
  void visitNode(AstNode node) {
    if (skip?.call(node) ?? false) return;
    onEach(node);
    super.visitNode(node);
  }
}
