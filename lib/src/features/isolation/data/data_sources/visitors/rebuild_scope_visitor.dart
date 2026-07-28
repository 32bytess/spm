import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:spm/src/core/constants/app_constants.dart';
import 'package:spm/src/features/analysis/data/data_sources/extensions/state_class_detector.dart';
import 'package:spm/src/features/isolation/data/data_sources/sets/isolation_match_set.dart';

/// An AST visitor that identifies rebuild scopes in Flutter code.
///
/// It searches for [State] classes, [ConsumerWidget]s, and common builder-pattern
/// widgets like `BlocBuilder`, `Consumer`, `Observer`, etc.
class RebuildScopeVisitor extends RecursiveAstVisitor<void> {
  /// The analysis result for the unit being visited.
  final ResolvedUnitResult result;

  /// The list of discovered rebuild scopes.
  final List<IsolationMatch> matches = [];

  RebuildScopeVisitor(this.result);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (isFlutterStateSubclass(node)) {
      matches.add((
        originalPath: result.path,
        name: node.namePart.typeName.lexeme,
        scopeNode: node,
        type: AppConstants.stateScopeType,
      ));
    } else if (isConsumerWidgetSubclass(node)) {
      matches.add((
        originalPath: result.path,
        name: node.namePart.typeName.lexeme,
        scopeNode: node,
        type: AppConstants.consumerWidgetScopeType,
      ));
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Handles prefixed types like 'bloc.BlocBuilder'
    final typeName = unprefixedTypeName(node);

    // Supported builder widgets that trigger rebuilds
    if (AppConstants.builderScopeWidgets.contains(typeName)) {
      final builderArg = findBuilderArgument(node, typeName);

      if (builderArg != null) {
        matches.add((
          originalPath: result.path,
          name: '${typeName}_builder',
          scopeNode: builderArg,
          type: typeName,
        ));
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  /// Extracts the relevant AST node representing the body of a function.
  static AstNode extractScopeFromBody(FunctionBody body) {
    if (body is BlockFunctionBody) {
      return body.block;
    } else if (body is ExpressionFunctionBody) {
      return body.expression;
    }
    return body;
  }
}
