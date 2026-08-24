import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/sdk_uris.dart';

class Skeletonizer {
  /// The widget an image construction that cannot be kept is replaced by.
  static const String placeholder = "Image.asset('$placeholderAsset')";

  /// The provider an image source is replaced by.
  ///
  /// Still an `ImageProvider`, which is the whole point. Rewriting a provider
  /// to `Image.asset(...)` turned a value object into a widget: in place
  /// `BuildMetricsVisitor` counts `NetworkImage` in `valueObjectAllocCount`,
  /// and as an `Image` it lands in `treeNonConstWidgetCount` and adds a level
  /// of depth, so two features diverged in opposite directions wherever an
  /// image provider appeared. It also put a widget in a provider-typed slot,
  /// which `BoxDecoration(image: ...)` and `CircleAvatar(backgroundImage: ...)`
  /// reject, and `argument_type_not_assignable` is the commonest error in the
  /// output.
  static const String providerPlaceholder =
      "const AssetImage('$placeholderAsset')";

  /// The asset every rewritten image points at.
  static const String placeholderAsset = 'assets/placeholder.png';

  /// Left where an argument was removed, so the loss is visible in the file
  /// and countable from it.
  static const String droppedLoadingBuilder =
      '/* spm: loadingBuilder dropped, Image.asset has no such argument */';

  /// Image providers replaced whole, because their arguments are a URL, a path
  /// or bytes and never a widget subtree.
  ///
  /// SDK classes only. Image widgets from packages used to be in this family,
  /// and they were the entries that made it say something other than what it
  /// means: they are third-party widgets, and the transplant now carries a
  /// third-party widget's real tree rather than replacing it.
  static final Set<String> _providerClasses = {
    'AssetImage',
    'NetworkImage',
    'FileImage',
    'MemoryImage',
  };

  /// Image constructions kept in place, with only their source substituted.
  ///
  /// Replacing the whole node erased widget subtrees: `errorBuilder` and
  /// `loadingBuilder` are widget-returning closures, and in place
  /// `BuildMetricsVisitor` walks the argument list and counts what they build.
  /// A revision that adds an `errorBuilder` therefore produced a nonzero
  /// in-place delta and a zero transplant delta, which is a delta erased.
  static final Set<String> _imageWidgetClasses = {
    'Image',
    'DecorationImage',
    'FadeInImage',
    'RawImage',
  };

  /// `Image` constructors whose first positional argument names the source.
  static const Set<String> _imageSourceConstructors = {
    'asset',
    'network',
    'file',
    'memory',
  };

  /// [rewriters] contribute extra edits alongside the image replacements. The
  /// transplant uses them to re-insert casts that type promotion used to supply
  /// and to rename a declaration that would shadow a Flutter name. Edits from
  /// every source are applied in a single right-to-left pass so their offsets
  /// stay valid.
  static String skeletonize(
    AstNode node,
    ResolvedUnitResult result, {
    List<SourceRewriter> rewriters = const [],
  }) {
    final collector = _ReplacementCollector(result);
    node.accept(collector);

    String source = result.content.substring(node.offset, node.end);
    final replacements = <Replacement>[...collector.replacements];
    for (final rewriter in rewriters) {
      // Cleared first, because one rewriter serves the whole transplant and its
      // nodes come from several files. A leftover edit from another file could
      // land inside this node's range by coincidence, and nothing downstream
      // would notice.
      rewriter.reset();
      node.accept(rewriter);
      replacements.addAll(rewriter.replacements);
    }
    // Edits now arrive from several independent sources, so one can land
    // inside another: an `Image(...)` inside a handler body the eraser
    // replaces whole, for instance. A nested edit cannot survive the
    // right-to-left pass, because the outer replacement still carries the
    // original length while the inner one has already changed it. Outermost
    // wins, which is the same rule `_ReplacementCollector` applies to the
    // edits it makes on its own.
    replacements.sort((a, b) {
      final byOffset = a.offset.compareTo(b.offset);
      return byOffset != 0 ? byOffset : b.length.compareTo(a.length);
    });
    final applicable = <Replacement>[];
    var coveredTo = -1;
    for (final r in replacements) {
      if (r.offset < coveredTo) continue;
      applicable.add(r);
      coveredTo = r.offset + r.length;
    }

    applicable.sort((a, b) => b.offset.compareTo(a.offset));

    for (final r in applicable) {
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

  /// Drops the edits from the previous traversal.
  ///
  /// Called before each one, so a rewriter shared across several nodes never
  /// applies an offset that belonged to a different file.
  void reset() {}
}

class _ReplacementCollector extends RecursiveAstVisitor<void> {
  final List<Replacement> replacements = [];
  final ResolvedUnitResult result;

  /// Arguments already replaced whole, so the walk does not descend into them.
  ///
  /// A replacement inside another replacement's span cannot survive the
  /// right-to-left pass: the outer edit still holds the original length, and
  /// the inner edit has already changed it.
  final Set<AstNode> _replacedWhole = {};

  _ReplacementCollector(this.result);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final owner = _imageOwner(node);
    if (owner != null && Skeletonizer._providerClasses.contains(owner)) {
      replacements.add(
        Replacement(node.offset, node.length, Skeletonizer.providerPlaceholder),
      );
      return;
    }
    if (owner != null && Skeletonizer._imageWidgetClasses.contains(owner)) {
      if (_rewriteImageWidget(
        owner,
        node.constructorName.name?.name,
        node.constructorName.name,
        node.argumentList,
        node,
      )) {
        return;
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final owner = _imageOwner(node);
    if (owner != null && Skeletonizer._providerClasses.contains(owner)) {
      replacements.add(
        Replacement(node.offset, node.length, Skeletonizer.providerPlaceholder),
      );
      return;
    }
    if (owner != null && Skeletonizer._imageWidgetClasses.contains(owner)) {
      if (_rewriteImageWidget(
        owner,
        node.methodName.name == owner ? null : node.methodName.name,
        node.methodName,
        node.argumentList,
        node,
      )) {
        return;
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (_replacedWhole.contains(node)) return;
    super.visitNamedArgument(node);
  }

  /// Substitutes the source of an image widget, keeping the node and the rest
  /// of its arguments.
  ///
  /// Returns true when the whole node was replaced instead, which happens only
  /// for the `FadeInImage` named constructors: their two sources are a string
  /// and a byte buffer in the same call, and there is no substitution that
  /// keeps both types.
  bool _rewriteImageWidget(
    String owner,
    String? constructorName,
    AstNode? constructorNameNode,
    ArgumentList arguments,
    AstNode node,
  ) {
    if (owner == 'FadeInImage') {
      if (constructorName == null) return false;
      replacements.add(
        Replacement(node.offset, node.length, Skeletonizer.placeholder),
      );
      return true;
    }

    if (owner == 'RawImage') {
      // `ui.Image? image`, and there is no asset that produces one. Null is in
      // range and leaves every other argument, including the subtree ones,
      // untouched.
      final image = _namedArgument(arguments, 'image');
      if (image != null) {
        final value = image.argumentExpression;
        replacements.add(Replacement(value.offset, value.length, 'null'));
        _replacedWhole.add(image);
      }
      return false;
    }

    // `DecorationImage` needs nothing of its own: its `image:` is a provider,
    // so the provider rule reaches it on the way down.
    if (owner == 'DecorationImage') return false;

    if (constructorName == null ||
        !Skeletonizer._imageSourceConstructors.contains(constructorName)) {
      // `Image(image: ...)` takes a provider, handled on the way down.
      return false;
    }

    if (constructorName != 'asset' && constructorNameNode != null) {
      replacements.add(
        Replacement(
          constructorNameNode.offset,
          constructorNameNode.length,
          'asset',
        ),
      );
    }

    final source = arguments.arguments
        .where((a) => a is! NamedArgument)
        .firstOrNull;
    if (source != null) {
      replacements.add(
        Replacement(
          source.offset,
          source.length,
          "'${Skeletonizer.placeholderAsset}'",
        ),
      );
      _replacedWhole.add(source);
    }

    // `Image.asset` has no `loadingBuilder`, so the one argument that cannot
    // come across is removed with its comma and a marker is left in its place.
    final loading = _namedArgument(arguments, 'loadingBuilder');
    if (loading != null) {
      _removeArgument(arguments, loading);
      _replacedWhole.add(loading);
    }
    return false;
  }

  NamedArgument? _namedArgument(ArgumentList arguments, String name) {
    for (final argument in arguments.arguments) {
      if (argument is NamedArgument && argument.name.lexeme == name) {
        return argument;
      }
    }
    return null;
  }

  /// Replaces [argument] and its separating comma with a marker comment.
  ///
  /// The comma has to go with it: an argument list cannot hold an empty slot,
  /// and a comment on its own is not an argument.
  void _removeArgument(ArgumentList arguments, NamedArgument argument) {
    var start = argument.offset;
    var end = argument.end;
    final following = argument.endToken.next;
    if (following != null && following.lexeme == ',') {
      end = following.end;
    } else {
      final index = arguments.arguments.indexOf(argument);
      if (index > 0) {
        final comma = arguments.arguments[index - 1].endToken.next;
        if (comma != null && comma.lexeme == ',') start = comma.offset;
      }
    }
    replacements.add(
      Replacement(start, end - start, Skeletonizer.droppedLoadingBuilder),
    );
  }

  /// Rewrites the pre-Dart-3 default-value separator, `{int x: 5}` -> `{int x = 5}`.
  ///
  /// The transplant copies source text verbatim, so a repository old enough to
  /// still use the colon form carries it into a file that is then analyzed by a
  /// modern SDK, where it is `OBSOLETE_COLON_FOR_DEFAULT_VALUE` for a named
  /// parameter and `WRONG_SEPARATOR_FOR_POSITIONAL_PARAMETER` for a positional
  /// one. The parser recovers from both and still reports the separator token,
  /// so the span is exact. `=` is valid in either position, which is why the
  /// replacement needs no knowledge of which kind of parameter it sits on.
  @override
  void visitFormalParameterDefaultClause(FormalParameterDefaultClause node) {
    final separator = node.separator;
    if (separator.lexeme == ':') {
      replacements.add(Replacement(separator.offset, separator.length, '='));
    }
    super.visitFormalParameterDefaultClause(node);
  }

  /// The image class [node] constructs, or null when it constructs none.
  String? _imageOwner(AstNode node) {
    Element? element;
    if (node is InstanceCreationExpression) {
      element =
          _getElement(node.constructorName)?.enclosingElement ??
          _getElement(node)?.enclosingElement;
    } else if (node is MethodInvocation) {
      element = _getElement(node.methodName) ?? _getElement(node);
    }
    if (element == null) return null;
    final name = element.name;
    if (name == null) return null;
    if (!Skeletonizer._providerClasses.contains(name) &&
        !Skeletonizer._imageWidgetClasses.contains(name)) {
      return null;
    }
    // The names in these sets are Flutter's, and a package is free to reuse
    // one. Rewriting somebody else's `NetworkImage` to an asset would replace a
    // widget tree the transplant is now able to carry.
    return _isSdkOwned(element) ? name : null;
  }

  /// Whether [element] is declared by the Dart or Flutter SDK.
  ///
  /// An element whose library cannot be read is treated as SDK-owned, which is
  /// how this behaved before the test existed. A project with unresolved
  /// dependencies reaches here constantly, and the placeholder is the more
  /// useful answer there than a construction referencing assets that are not
  /// in the output directory.
  bool _isSdkOwned(Element element) {
    try {
      final uri = element.library?.identifier;
      if (uri == null) return true;
      return isSdkLibrary(uri);
    } catch (_) {
      return true;
    }
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
