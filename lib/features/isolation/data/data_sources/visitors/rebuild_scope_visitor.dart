import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:spm/features/analysis/data/data_sources/extensions/state_class_detector.dart';
import 'package:spm/features/isolation/data/data_sources/sets/isolation_match_set.dart';

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
        type: 'State',
      ));
    } else if (_isConsumerWidget(node)) {
      matches.add((
        originalPath: result.path,
        name: node.namePart.typeName.lexeme,
        scopeNode: node,
        type: 'ConsumerWidget',
      ));
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructorType = node.constructorName.type;
    String typeName = constructorType.name.lexeme;
    // Handle prefixed types like 'bloc.BlocBuilder'
    if (typeName.contains('.')) {
      typeName = typeName.split('.').last;
    }

    // List of supported builder widgets that trigger rebuilds
    if (['Consumer', 'Selector', 'BlocBuilder', 'BlocSelector', 'BlocConsumer', 'Obx', 'GetX', 'GetBuilder', 'Observer']
        .contains(typeName)) {
      Expression? builderArg;
      // Most widgets use a named 'builder' parameter
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression && arg.name.label.name == 'builder') {
          builderArg = arg.expression;
          break;
        }
      }
      // Some widgets (like Obx) take the builder as the first positional argument
      if (builderArg == null &&
          (typeName == 'Obx' || typeName == 'Observer' || typeName == 'GetBuilder' || typeName == 'GetX') &&
          node.argumentList.arguments.isNotEmpty) {
        builderArg = node.argumentList.arguments.first;
      }

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

  /// Finds the `build` method within a class declaration.
  static MethodDeclaration? findBuildMethod(ClassDeclaration node) {
    for (final member in (node.body as BlockClassBody).members) {
      if (member is MethodDeclaration && member.name.lexeme == 'build') {
        return member;
      }
    }
    return null;
  }

  /// Checks if a class inherits from a Riverpod/Hooks consumer.
  bool _isConsumerWidget(ClassDeclaration node) {
    if (node.extendsClause == null) return false;
    final superName = node.extendsClause!.superclass.name.lexeme;
    return superName == 'ConsumerWidget' || superName == 'HookConsumerWidget';
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
