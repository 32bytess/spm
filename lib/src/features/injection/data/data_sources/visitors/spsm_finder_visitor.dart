import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:spm/src/core/constants/app_constants.dart';

class SpmFinderVisitor extends RecursiveAstVisitor<void> {
  final List<MethodInvocation> matches = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target is SimpleIdentifier &&
        (node.target as SimpleIdentifier).name ==
            AppConstants.profilerClassName) {
      matches.add(node);
    }
    super.visitMethodInvocation(node);
  }
}
