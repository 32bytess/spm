import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

class Skeletonizer {
  static const String placeholder = "Image.asset('assets/placeholder.png')";

  static final Set<String> _imageClasses = {
    'Image',
    'AssetImage',
    'NetworkImage',
    'FileImage',
    'MemoryImage',
    'DecorationImage',
    'FadeInImage',
    'RawImage',
    'CachedNetworkImage',
    'SvgPicture',
  };

  /// [rewriter] contributes extra edits alongside the image replacements —
  /// used by the transplant to re-insert casts that type promotion used to
  /// supply. Edits from both sources are applied in a single right-to-left
  /// pass so their offsets stay valid.
  static String skeletonize(
    AstNode node,
    ResolvedUnitResult result, {
    SourceRewriter? rewriter,
  }) {
    final collector = _ReplacementCollector(result);
    node.accept(collector);

    String source = result.content.substring(node.offset, node.end);
    final replacements = <Replacement>[...collector.replacements];
    if (rewriter != null) {
      node.accept(rewriter);
      replacements.addAll(rewriter.replacements);
    }
    replacements.sort((a, b) => b.offset.compareTo(a.offset));

    for (final r in replacements) {
      final relativeOffset = r.offset - node.offset;
      if (relativeOffset < 0 || relativeOffset >= source.length) continue;
      source = source.replaceRange(
        relativeOffset,
        relativeOffset + r.length,
        r.text,
      );
    }

    return source;
  }
}

/// A single span of source to overwrite.
class Replacement {
  final int offset;
  final int length;
  final String text;
  Replacement(this.offset, this.length, this.text);
}

/// A visitor that contributes [Replacement]s to [Skeletonizer.skeletonize].
abstract class SourceRewriter extends RecursiveAstVisitor<void> {
  /// Edits collected during traversal.
  List<Replacement> get replacements;
}

class _ReplacementCollector extends RecursiveAstVisitor<void> {
  final List<Replacement> replacements = [];
  final ResolvedUnitResult result;

  _ReplacementCollector(this.result);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_isImage(node)) {
      replacements.add(
        Replacement(node.offset, node.length, Skeletonizer.placeholder),
      );
      return;
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isImage(node)) {
      replacements.add(
        Replacement(node.offset, node.length, Skeletonizer.placeholder),
      );
      return;
    }
    super.visitMethodInvocation(node);
  }

  bool _isImage(AstNode node) {
    Element? element;
    if (node is InstanceCreationExpression) {
      element =
          _getElement(node.constructorName)?.enclosingElement ??
          _getElement(node)?.enclosingElement;
    } else if (node is MethodInvocation) {
      element = _getElement(node.methodName) ?? _getElement(node);
    }
    return element != null && Skeletonizer._imageClasses.contains(element.name);
  }

  Element? _getElement(dynamic node) {
    if (node == null) return null;
    try {
      return node.staticElement;
    } catch (_) {}
    try {
      return node.element;
    } catch (_) {}
    try {
      return node.element2;
    } catch (_) {}
    return null;
  }
}
