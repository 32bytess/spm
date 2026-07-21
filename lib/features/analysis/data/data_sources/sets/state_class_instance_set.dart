import 'package:analyzer/dart/ast/ast.dart';

typedef StateClassInstance = ({
  String instanceId,
  String filePath,
  String stateClassName,
  ClassDeclaration classDeclaration,
  MethodDeclaration? buildMethod,
});
