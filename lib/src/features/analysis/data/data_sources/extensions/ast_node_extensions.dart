import 'package:analyzer/dart/ast/ast.dart';

import '../visitors/counting_visitor.dart';

extension AstNodeExtensions on AstNode {
  /// Computes the cyclomatic complexity for this [AstNode] .
  ///
  /// This counts control flow structures such as if statements,
  /// loops, switch cases, and logical operators.
  ///
  /// [skip] prunes: a matched node and its whole subtree are left out, which
  /// is what keeps the decision points of an event handler off a rebuild's
  /// score. This node itself is never offered to it, since the walk starts at
  /// the children, so a builder callback cannot prune its own body.
  ///
  /// Returns an integer representing the cyclomatic complexity.
  ///
  int cyclomaticComplexity([bool Function(AstNode)? skip]) {
    var score = 1;
    visitChildren(
      CountingVisitor(skip: skip, (n) {
        // For-in statements are ForStatement wrapping ForEachParts; counting
        // the statement/element nodes (never the parts) keeps every loop form
        // at exactly +1.
        if (n is IfStatement ||
            n is IfElement ||
            n is ForStatement ||
            n is ForElement ||
            n is WhileStatement ||
            n is DoStatement ||
            n is SwitchCase ||
            n is SwitchPatternCase ||
            n is SwitchExpressionCase ||
            n is CatchClause) {
          score++;
        }
        if (n is BinaryExpression) {
          final op = n.operator.lexeme;
          if (op == '&&' || op == '||' || op == '??') score++;
        }
        if (n is ConditionalExpression) score++;
      }),
    );
    return score;
  }
}
