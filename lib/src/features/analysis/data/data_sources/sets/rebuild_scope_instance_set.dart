import 'package:analyzer/dart/ast/ast.dart';

/// One independently rebuildable scope discovered in a source file.
///
/// A scope is either a class Flutter rebuilds as a unit (`State` subclass,
/// `ConsumerWidget`) or the builder callback of a state-management widget
/// such as `BlocBuilder` or `Obx`, which its package re-invokes on its own.
typedef RebuildScopeInstance = ({
  String instanceId,
  String filePath,

  /// Class name, or `'<Widget>_builder'` for a builder callback.
  String scopeName,

  /// One of [AppConstants.rebuildScopeTypes].
  String scopeType,

  /// Class the scope belongs to; the metric extractor resolves helper
  /// references against its members. Null for a builder callback written
  /// outside any class.
  ClassDeclaration? declaringClass,

  /// Body walked to collect metrics: a `build()` body, or the builder
  /// callback's body. Null when a scope class declares no `build`.
  FunctionBody? body,
});
