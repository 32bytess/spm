import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Finds constructs that make a `buildSpan` measurement non-deterministic
/// or timing-dependent (check 6): async machinery, randomness, wall-clock
/// reads, I/O, network, and animations.
class ForbiddenConstructVisitor extends RecursiveAstVisitor<void> {
  final List<String> findings = [];

  static const _forbiddenTypes = {
    'Future',
    'Stream',
    'FutureBuilder',
    'StreamBuilder',
    'Timer',
    'Random',
    'AnimationController',
    'Animation',
    'Ticker',
    'TickerProviderStateMixin',
    'SingleTickerProviderStateMixin',
    'AnimatedBuilder',
    'AnimatedContainer',
    'HttpClient',
  };

  static const _forbiddenImportPrefixes = {
    'dart:io',
    'dart:async',
    'dart:isolate',
    'package:http/',
    'package:dio/',
  };

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue ?? '';
    if (_forbiddenImportPrefixes.any(uri.startsWith)) {
      findings.add("forbidden import '$uri'");
    }
    super.visitImportDirective(node);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    findings.add("'await' expression: ${node.toSource()}");
    super.visitAwaitExpression(node);
  }

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    _checkAsyncKeyword(node);
    super.visitBlockFunctionBody(node);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    _checkAsyncKeyword(node);
    super.visitExpressionFunctionBody(node);
  }

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if (_forbiddenTypes.contains(name)) {
      findings.add("forbidden type '$name'");
    }
    super.visitNamedType(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // NamedType check above already catches Random(), Timer(), Future.delayed
    // etc.; DateTime is only forbidden through its wall-clock constructor.
    if (node.constructorName.type.name.lexeme == 'DateTime' &&
        node.constructorName.name?.name == 'now') {
      findings.add('wall-clock read: DateTime.now()');
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Fallback for unresolved units where DateTime.now() stays a
    // MethodInvocation instead of being rewritten to a constructor call.
    final target = node.target;
    if (target is SimpleIdentifier &&
        target.name == 'DateTime' &&
        node.methodName.name == 'now') {
      findings.add('wall-clock read: DateTime.now()');
    }
    super.visitMethodInvocation(node);
  }

  void _checkAsyncKeyword(FunctionBody node) {
    if (node.keyword?.lexeme == 'async') {
      findings.add("'async' function body");
    }
  }
}
