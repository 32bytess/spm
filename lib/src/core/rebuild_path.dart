import 'package:analyzer/dart/ast/ast.dart';
import 'package:spm/src/core/constants/app_constants.dart' show AppConstants;

/// Whether [node] is a closure that cannot run during a rebuild.
///
/// Every feature `analyze` emits prices one rebuild of a scope, and an
/// `onPressed` body runs only when the user presses. Counting it charges the
/// rebuild for cost it never pays, and the child-widget traversal amplifies
/// that: a page pushed from a handler would merge its whole build tree into
/// the scope's metrics.
///
/// Only a [FunctionExpression] qualifies. Any other expression in a handler
/// slot (`onTap: enabled ? _a : _b`) is evaluated while the tree is built, so
/// it keeps counting. The default is to descend: an unrecognised closure keeps
/// its old treatment, which is what keeps builder callbacks such as
/// `itemBuilder`, `LayoutBuilder(builder:)` and the positional `Obx(() => ...)`
/// inside the measurement.
bool isNonRebuildCallback(AstNode node) =>
    node is FunctionExpression && _inNonRebuildSlot(node);

/// Whether [node] is a bare reference sitting in a non-rebuild callback slot
/// (`onPressed: submit`).
///
/// The reference itself is evaluated while the tree is built; only the body is
/// deferred. So this answers one narrow question: may the referenced body be
/// pulled into the metrics? It must not be, for the same reason the closure
/// form must not.
bool isNonRebuildCallbackReference(SimpleIdentifier node) =>
    _inNonRebuildSlot(node);

/// Whether [node] occupies an argument slot whose value runs off the build
/// path, either by the label it is passed under or by the call it is passed to.
bool _inNonRebuildSlot(Expression node) {
  var current = node.parent;
  if (current is NamedArgument) {
    final label = current.name.lexeme;
    if (AppConstants.eventHandlerLabel.hasMatch(label) ||
        AppConstants.nonRebuildCallbackLabels.contains(label)) {
      return true;
    }
    // A named argument to one of the deferred hosts below, such as
    // `Future.delayed(d, computation: ...)`, is still deferred.
    current = current.parent;
  }
  // A positional argument is the expression itself, so its parent is the
  // argument list directly.
  if (current is! ArgumentList) return false;
  return _isDeferredHost(current.parent);
}

/// Whether [host] is a call whose callback argument is invoked later.
bool _isDeferredHost(AstNode? host) {
  final hosts = AppConstants.nonRebuildCallbackHosts;
  if (host is MethodInvocation) return hosts.contains(host.methodName.name);
  if (host is! InstanceCreationExpression) return false;
  final typeName = host.constructorName.type.name.lexeme;
  final constructor = host.constructorName.name?.name;
  return hosts.contains(typeName) ||
      (constructor != null && hosts.contains('$typeName.$constructor'));
}
