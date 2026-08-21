import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/skeletonizer.dart';

/// Restores casts that type promotion used to make unnecessary.
///
/// Inside its original method a builder parameter is promotable, so
/// `if (state is WalletLoaded) { state.wallets }` resolves. The transplant lifts
/// that parameter to a `late WalletState state;` field, and Dart does not
/// promote fields, so every promoted use stops compiling.
///
/// This rewriter finds references to lifted names whose promoted static type is
/// a proper subtype of the field's declared type and wraps them:
/// `state.wallets` becomes `(state as WalletLoaded).wallets`.
///
/// Only lifted names are considered. Locals keep their promotion and must be
/// left alone, or the output fills with redundant casts.
class PromotionCastRewriter extends SourceRewriter {
  /// Declared type of each lifted field, keyed by name.
  PromotionCastRewriter(this.declaredTypes);

  final Map<String, String> declaredTypes;

  @override
  final List<Replacement> replacements = [];

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);

    if (node.inDeclarationContext()) return;
    final declared = declaredTypes[node.name];
    if (declared == null) return;

    // Only a reference to the lifted binding itself matters. `foo.state` is
    // somebody else's member.
    final parent = node.parent;
    if (parent is PropertyAccess && identical(parent.propertyName, node)) {
      return;
    }
    if (parent is PrefixedIdentifier && identical(parent.identifier, node)) {
      return;
    }
    if (parent is Label || parent is NamedType) return;

    final element = _elementOf(node);
    if (element is! LocalVariableElement &&
        element is! FormalParameterElement) {
      return;
    }

    final promoted = _staticTypeOf(node);
    if (promoted == null || promoted == declared) return;

    // A promoted reference standing alone (`return state;`) still assigns fine;
    // it is member access that breaks.
    final needsCast =
        (parent is PropertyAccess && identical(parent.target, node)) ||
        (parent is PrefixedIdentifier && identical(parent.prefix, node)) ||
        (parent is MethodInvocation && identical(parent.target, node)) ||
        (parent is IndexExpression && identical(parent.target, node));
    if (!needsCast) return;

    replacements.add(
      Replacement(node.offset, node.length, '(${node.name} as $promoted)'),
    );
  }

  String? _staticTypeOf(SimpleIdentifier node) {
    try {
      final type = node.staticType;
      if (type == null) return null;
      final display = type.getDisplayString();
      if (display.isEmpty || display == 'dynamic') return null;
      return display;
    } catch (_) {
      return null;
    }
  }

  Element? _elementOf(SimpleIdentifier node) {
    final dynamic n = node;
    try {
      final e = n.element;
      if (e != null) return e as Element;
    } catch (_) {}
    try {
      final e = n.staticElement;
      if (e != null) return e as Element;
    } catch (_) {}
    return null;
  }
}
