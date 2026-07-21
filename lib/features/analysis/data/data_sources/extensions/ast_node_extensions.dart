import 'package:analyzer/dart/ast/ast.dart';

import '../visitors/counting_visitor.dart';

extension AstNodeExtensions on AstNode {
  /// Computes the cyclomatic complexity for this [AstNode] .
  ///
  /// This counts control flow structures such as if statements,
  /// loops, switch cases, and logical operators.
  ///
  /// Returns an integer representing the cyclomatic complexity.
  ///
  int cyclomaticComplexity([bool Function(AstNode)? skip]) {
    var score = 1;
    visitChildren(
      CountingVisitor((n) {
        if (skip?.call(n) ?? false) return;
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
