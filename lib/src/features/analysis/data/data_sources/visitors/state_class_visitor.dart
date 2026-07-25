import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../extensions/state_class_detector.dart';
import '../sets/state_class_instance_set.dart';

class StateClassVisitor extends RecursiveAstVisitor<void> {
  final ResolvedUnitResult result;

  /// Analysis root the hashed path is relativized against. Hashing the
  /// relative path keeps `instanceId` stable across machines and checkout
  /// directories; when null (e.g. validation's in-memory comparisons) the
  /// absolute path is used.
  final String? rootPath;
  final List<StateClassInstance> instances = [];

  StateClassVisitor(this.result, {this.rootPath});

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (isFlutterStateSubclass(node)) {
      MethodDeclaration? buildMethod;
      final body = node.body;
      if (body is BlockClassBody) {
        for (final member in body.members) {
          if (member is MethodDeclaration && member.name.lexeme == 'build') {
            buildMethod = member;
            break;
          }
        }
      }

      final className = node.namePart.typeName.lexeme;
      instances.add((
        instanceId: _hash('${_stablePath()}:$className'),
        filePath: result.path,
        stateClassName: className,
        classDeclaration: node,
        buildMethod: buildMethod,
      ));
    }

    super.visitClassDeclaration(node);
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
