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

  static String skeletonize(AstNode node, ResolvedUnitResult result) {
    final collector = _ReplacementCollector(result);
    node.accept(collector);

    String source = result.content.substring(node.offset, node.end);
    final replacements = collector.replacements.toList()
      ..sort((a, b) => b.offset.compareTo(a.offset));

    for (final r in replacements) {
      final relativeOffset = r.offset - node.offset;
      if (relativeOffset < 0 || relativeOffset >= source.length) continue;
      source = source.replaceRange(
        relativeOffset,
        relativeOffset + r.length,
        placeholder,
      );
    }

    return source;
  }
}

class _Replacement {
  final int offset;
  final int length;
  _Replacement(this.offset, this.length);
}

class _ReplacementCollector extends RecursiveAstVisitor<void> {
  final List<_Replacement> replacements = [];
  final ResolvedUnitResult result;

  _ReplacementCollector(this.result);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_isImage(node)) {
      replacements.add(_Replacement(node.offset, node.length));
      return;
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isImage(node)) {
      replacements.add(_Replacement(node.offset, node.length));
      return;
    }
    super.visitMethodInvocation(node);
  }

  bool _isImage(AstNode node) {
    Element? element;
    if (node is InstanceCreationExpression) {
      element = _getElement(node.constructorName)?.enclosingElement ??
          _getElement(node)?.enclosingElement;
    } else if (node is MethodInvocation) {
      element = _getElement(node.methodName) ?? _getElement(node);
    }
    return element != null &&
        Skeletonizer._imageClasses.contains(element.name);
  }

  Element? _getElement(dynamic node) {
    if (node == null) return null;
    try { return node.staticElement; } catch (_) {}
    try { return node.element; } catch (_) {}
    try { return node.element2; } catch (_) {}
    return null;
  }
}
