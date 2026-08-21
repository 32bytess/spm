import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Collects the rendered-leaf vocabulary of a widget file: displayed
/// `Text`/`SelectableText`/`Tooltip` strings, `Icons.*` references, and
/// asset paths. Base and mutation must agree on all of them (check 3).
class RenderedLeafVisitor extends RecursiveAstVisitor<void> {
  /// A multiset, because a duplicated or removed label must be detected when
  /// the distinct string set is unchanged.
  final List<String> texts = [];
  final Set<String> icons = {};
  final Set<String> assets = {};

  static const _textWidgets = {'Text', 'SelectableText', 'Tooltip'};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name.lexeme;
    final ctorName = node.constructorName.name?.name;
    final args = node.argumentList.arguments;

    if (_textWidgets.contains(typeName)) {
      final lit =
          args.whereType<StringLiteral>().firstOrNull ??
          args
              .whereType<NamedArgument>()
              .where((n) => n.name.lexeme == 'message')
              .map((n) => n.argumentExpression)
              .whereType<StringLiteral>()
              .firstOrNull;
      if (lit != null) texts.add(lit.stringValue ?? lit.toSource());
    }

    if (typeName == 'AssetImage' ||
        (typeName == 'Image' && ctorName == 'asset')) {
      final lit = args.whereType<StringLiteral>().firstOrNull;
      if (lit != null) assets.add(lit.stringValue ?? lit.toSource());
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'Icons') icons.add(node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }
}
