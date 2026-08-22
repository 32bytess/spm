import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spm/src/core/constants/app_constants.dart';

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

/// Whether [decl] is a Riverpod/Hooks consumer widget.
///
/// Name-based on purpose: consumer widgets come from packages that may not be
/// resolvable in standalone fixtures, and the two class names are unambiguous
/// enough that a direct-superclass check is sufficient.
bool isConsumerWidgetSubclass(ClassDeclaration decl) {
  final extendsClause = decl.extendsClause;
  if (extendsClause == null) return false;

  final superName = extendsClause.superclass.name.lexeme;
  return superName == 'ConsumerWidget' || superName == 'HookConsumerWidget';
}

/// The inline builder callback of a builder-pattern widget creation, if it has
/// one.
///
/// Most widgets pass it as the named `builder:` argument; the widgets in
/// [AppConstants.positionalBuilderScopeWidgets] also accept it as the first
/// positional argument (`Obx(() => ...)`).
///
/// Only a [FunctionExpression] counts. A tear-off or a variable reference
/// (`builder: _buildRow`) is measured wherever the function is declared, not
/// here, and this is the single place that decides it for both commands.
/// `analyze` used to apply that test at its own call site and `isolate` did not,
/// so a tear-off became an isolate-only match whose scope node is an identifier:
/// the transplant fell through to its expression fallback and emitted
/// `return _buildRow;`, a function returned where a `Widget` is required. That
/// is a file which can never analyse clean, a row in the mapping, and a count
/// in the summary, for a scope `analyze` never reports at all.
FunctionExpression? findBuilderArgument(
  InstanceCreationExpression node,
  String typeName,
) {
  for (final arg in node.argumentList.arguments) {
    if (arg is NamedArgument && arg.name.lexeme == 'builder') {
      // Returns rather than continues: an explicit `builder:` settles the
      // question, so a widget that also takes a positional callback does not
      // fall through and match that one instead.
      final expression = arg.argumentExpression;
      return expression is FunctionExpression ? expression : null;
    }
  }

  if (AppConstants.positionalBuilderScopeWidgets.contains(typeName) &&
      node.argumentList.arguments.isNotEmpty) {
    final first = node.argumentList.arguments.first;
    if (first is FunctionExpression) return first;
  }
  return null;
}

/// The constructor type name of [node] with any import prefix stripped
/// (`bloc.BlocBuilder` -> `BlocBuilder`).
String unprefixedTypeName(InstanceCreationExpression node) {
  final typeName = node.constructorName.type.name.lexeme;
  return typeName.contains('.') ? typeName.split('.').last : typeName;
}

/// Finds the `build` method declared directly on [decl], if any.
MethodDeclaration? findBuildMethod(ClassDeclaration decl) {
  final body = decl.body;
  if (body is! BlockClassBody) return null;

  for (final member in body.members) {
    if (member is MethodDeclaration && member.name.lexeme == 'build') {
      return member;
    }
  }
  return null;
}
