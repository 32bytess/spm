import 'package:analyzer/dart/ast/ast.dart';

/// Represents a matched rebuild scope found during static analysis.
///
/// Fields:
/// * [originalPath]: Path to the source file where the match was found.
/// * [name]: A descriptive name for the scope (e.g., class name or widget type).
/// * [scopeNode]: The actual AST node representing the rebuild scope.
/// * [type]: The category of the scope (e.g., 'State', 'BlocBuilder', 'Consumer').
typedef IsolationMatch = ({
  String originalPath,
  String name,
  AstNode scopeNode,
  String type,
});
