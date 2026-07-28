import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/constants/app_constants.dart';

import '../extensions/state_class_detector.dart';
import '../sets/rebuild_scope_instance_set.dart';

/// Collects every rebuild scope in a compilation unit: `State` subclasses,
/// consumer widgets, and the builder callbacks of state-management widgets.
///
/// Scopes nest — a `BlocBuilder` callback inside a `State.build()` yields two
/// instances, and the enclosing scope's metrics include the callback. That is
/// intentional: a parent rebuild does re-run the callback, while the callback
/// scope measures the path the package can rebuild on its own.
class RebuildScopeAnalysisVisitor extends RecursiveAstVisitor<void> {
  final ResolvedUnitResult result;

  /// Analysis root the hashed path is relativized against. Hashing the
  /// relative path keeps `instanceId` stable across machines and checkout
  /// directories; when null (e.g. validation's in-memory comparisons) the
  /// absolute path is used.
  final String? rootPath;
  final List<RebuildScopeInstance> instances = [];

  /// Per-file occurrence counter, keyed `type:name`, so repeated builder
  /// scopes of the same kind get distinct ids.
  final _ordinals = <String, int>{};

  RebuildScopeAnalysisVisitor(this.result, {this.rootPath});

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final scopeType = isFlutterStateSubclass(node)
        ? AppConstants.stateScopeType
        : isConsumerWidgetSubclass(node)
        ? AppConstants.consumerWidgetScopeType
        : null;

    if (scopeType != null) {
      final className = node.namePart.typeName.lexeme;
      instances.add((
        instanceId: _instanceId(scopeType, className),
        filePath: result.path,
        scopeName: className,
        scopeType: scopeType,
        declaringClass: node,
        body: findBuildMethod(node)?.body,
      ));
    }

    super.visitClassDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Handles prefixed types like 'bloc.BlocBuilder'.
    final typeName = unprefixedTypeName(node);

    if (AppConstants.builderScopeWidgets.contains(typeName)) {
      final builderArg = findBuilderArgument(node, typeName);

      // Only an inline closure has a body to walk; a tear-off or a variable
      // reference is measured wherever the function is declared.
      if (builderArg is FunctionExpression) {
        final scopeName = '${typeName}_builder';
        instances.add((
          instanceId: _instanceId(typeName, scopeName),
          filePath: result.path,
          scopeName: scopeName,
          scopeType: typeName,
          declaringClass: node.thisOrAncestorOfType<ClassDeclaration>(),
          body: builderArg.body,
        ));
      }
    }

    super.visitInstanceCreationExpression(node);
  }

  /// `State` ids stay `path:ClassName` — they are referenced by injected
  /// `instanceId` getters and by validation reports, so their hash must not
  /// change. Other scopes are disambiguated by type and occurrence.
  String _instanceId(String scopeType, String scopeName) {
    if (scopeType == AppConstants.stateScopeType) {
      return _hash('${_stablePath()}:$scopeName');
    }
    final key = '$scopeType:$scopeName';
    final ordinal = _ordinals[key] = (_ordinals[key] ?? -1) + 1;
    return _hash('${_stablePath()}:$key#$ordinal');
  }

  /// Machine-independent identity path: relative to the analysis root, with
  /// forward slashes on every platform.
  String _stablePath() {
    final root = rootPath;
    if (root == null) return result.path;
    return p.relative(result.path, from: root).replaceAll(r'\', '/');
  }

  String _hash(String s) => s.codeUnits
      .fold<int>(0, (a, b) => (a * 131 + b) & 0x7fffffff)
      .toRadixString(16);
}
