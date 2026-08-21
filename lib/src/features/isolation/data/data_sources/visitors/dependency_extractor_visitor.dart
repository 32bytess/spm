import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/emitters/import_collector.dart';
import 'package:spm/src/features/isolation/data/data_sources/emitters/shim_emitter.dart';
import 'package:spm/src/features/isolation/data/data_sources/emitters/synthetic_shim_emitter.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/declaration_names.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/sdk_uris.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/skeletonizer.dart';

/// An AST visitor that extracts transitive dependencies of a rebuild scope.
///
/// It follows references to methods, fields, and classes within the same file
/// or in other project files, collecting the source code needed to make the
/// isolated code self-contained and compilable.
class DependencyExtractorVisitor extends RecursiveAstVisitor<void> {
  /// The analysis result for the file where extraction started.
  final ResolvedUnitResult originResult;

  /// The class declaration enclosing the scope being isolated, if any.
  final ClassDeclaration? enclosingClass;

  /// A set of unique keys (file path + element name) to track processed dependencies
  /// and prevent infinite recursion or duplicate extraction.
  final Set<String> _processedKeys;

  /// The imports the isolated file needs, shared with every sub-visitor.
  final ImportCollector imports;

  /// Collected source code for members (methods/fields) of the [enclosingClass].
  String memberCode = '';

  /// Collected source code for top-level declarations or classes from other files.
  String classCode = '';

  /// Top-level names [classCode] actually declares.
  ///
  /// The transplant appends its own declarations once the extractor is done,
  /// the seeds for lifted bindings and the shims, and has to know which names
  /// are already spoken for. [_processedKeys] cannot answer that: a name is
  /// marked processed when it is *considered*, including the ones the widget
  /// filter then drops, so it over-reports.
  ///
  /// Shared with every sub-visitor of the same transplant, so a name inlined
  /// anywhere in the recursion is known everywhere.
  final Set<String> emittedNames;

  /// References found in other files that need to be resolved and extracted.
  ///
  /// The element travels with the reference so that a lookup which finds
  /// nothing has something to stand in for. Dropping the name there is what
  /// leaves an undefined widget behind, and an undefined widget is worse than a
  /// missing one: `_aggregateChildMetrics` skips the whole subtree, so the row
  /// is wrong rather than absent.
  final List<({String filePath, String name, Element element})> crossFileRefs =
      [];

  /// The analysis session, used to convert `package:` URIs to file paths.
  final AnalysisSession? _session;

  /// Collects stand-ins for third-party symbols this visitor cannot import.
  ///
  /// Optional so the visitor can still be driven without one, in which case
  /// third-party references are dropped exactly as they were before.
  final ShimEmitter? shims;

  /// Collects stand-ins for references that resolved to nothing at all.
  ///
  /// Optional on the same terms as [shims].
  final SyntheticShimEmitter? synthetics;

  DependencyExtractorVisitor(
    this.originResult,
    this.enclosingClass,
    this._processedKeys,
    this.imports, {
    AnalysisSession? session,
    this.shims,
    this.synthetics,
    Set<String>? emittedNames,
  }) : _session = session,
       emittedNames = emittedNames ?? <String>{};

  /// Returns true if the [filePath] belongs to the local project (not a package or SDK).
  bool isProjectLocal(String filePath) {
    final root = originResult.session.analysisContext.contextRoot.root.path;
    return p.isWithin(root, filePath) || p.equals(root, filePath);
  }

  /// Returns true if [element]'s library is provided by [importedLib], either
  /// directly or through any depth of re-exports.
  ///
  /// The walk used to stop after one hop, which is shallower than real
  /// libraries are: `package:flutter/material.dart` re-exports `widgets.dart`,
  /// which re-exports `foundation.dart`. A symbol two hops down failed to match
  /// its own directive and fell to the URI-only fallback, which is the path
  /// that used to lose the prefix.
  static bool _isFromLibrary(Element element, dynamic importedLib) {
    try {
      // Use identifier (canonical URI) to compare libraries; avoid .source
      // which was removed from LibraryElement in analyzer ≥ 10.
      final dynamic elementLib = element.library;
      final elementUri = elementLib?.identifier as String?;
      if (elementUri == null || importedLib == null) return false;

      final seen = <String>{};
      final pending = <dynamic>[importedLib];
      while (pending.isNotEmpty) {
        final dynamic library = pending.removeLast();
        final uri = library?.identifier as String?;
        if (uri == null || !seen.add(uri)) continue;
        if (uri == elementUri) return true;
        for (final exported
            in (library?.exportedLibraries as Iterable? ?? const [])) {
          pending.add(exported);
        }
      }
    } catch (_) {}
    return false;
  }

  /// The import prefix the reference at [node] was written with, if any.
  ///
  /// The visitor otherwise never learns that a reference was prefixed: a
  /// `PrefixedIdentifier` is descended into, so `math.pi` arrives as two
  /// separate simple identifiers, the prefix half resolves to a `PrefixElement`
  /// that matches no branch of [_handleElement], and the tail half carries no
  /// memory of it.
  static String? _prefixAtUseSite(AstNode? node) {
    if (node == null) return null;

    if (node is NamedType) return node.importPrefix?.name.lexeme;
    if (node is ConstructorName) return node.type.importPrefix?.name.lexeme;

    if (node is SimpleIdentifier) {
      final parent = node.parent;
      if (parent is PrefixedIdentifier &&
          identical(parent.identifier, node) &&
          _isPrefixElement(parent.prefix)) {
        return parent.prefix.name;
      }
      if (parent is MethodInvocation && identical(parent.methodName, node)) {
        final target = parent.target;
        if (target is SimpleIdentifier && _isPrefixElement(target)) {
          return target.name;
        }
      }
    }
    return null;
  }

  static bool _isPrefixElement(SimpleIdentifier identifier) {
    try {
      return (identifier as dynamic).element is PrefixElement;
    } catch (_) {}
    return false;
  }

  /// Processes an [Element] to determine if it needs to be extracted.
  ///
  /// [node] is the reference that reached [element], when the caller has it.
  /// It is read only for the import prefix the reference was written with.
  void _handleElement(Element element, {AstNode? node}) {
    String? name;
    Element? target;
    // The member the reference actually reached, when [target] is the type
    // that declares or inherits it. A shim for a third-party type carries only
    // the members that were reached, so this is what keeps it small.
    Element? member;

    // Resolve the actual target element and its name based on the element type
    if (element is ConstructorElement) {
      final enclosing = element.enclosingElement;
      if (enclosing is ClassElement) {
        target = enclosing;
        name = enclosing.name;
        member = element;
      } else {
        return;
      }
    } else if (element is ClassElement ||
        element is EnumElement ||
        element is MixinElement ||
        element is ExtensionElement ||
        element is TopLevelVariableElement ||
        element is TypeAliasElement) {
      target = element;
      name = element.name;
    } else if (element is PropertyAccessorElement) {
      final variable = (element as dynamic).variable;
      if (variable is TopLevelVariableElement) {
        target = variable;
        name = variable.name;
      } else {
        final enclosing = element.enclosingElement;
        // `InstanceElement` rather than `ClassElement`: a getter reached
        // through an extension (`10.sp`, `context.h`) has an
        // `ExtensionElement` enclosing it, and narrowing to classes dropped
        // that whole family silently. Sizing extensions on `num` and
        // `BuildContext` are common enough in real apps that this was the
        // largest single source of undefined names in isolated output.
        if (enclosing is InstanceElement) {
          if (enclosing.name == enclosingClass?.namePart.typeName.lexeme) {
            target = element;
            name = element.name;
          } else {
            target = enclosing;
            name = enclosing.name;
            member = element;
          }
        } else {
          return;
        }
      }
    } else if (element is ExecutableElement) {
      final enclosing = element.enclosingElement;
      if (enclosing is ClassElement ||
          enclosing is MixinElement ||
          enclosing is ExtensionElement) {
        final enclName = (enclosing as dynamic).name as String?;
        if (enclName != null &&
            enclName != enclosingClass?.namePart.typeName.lexeme) {
          target = enclosing;
          name = enclName;
          member = element;
        } else {
          target = element;
          name = element.name;
        }
      } else {
        target = element;
        name = element.name;
      }
    } else if (element is FieldElement) {
      final enclosing = element.enclosingElement;
      if (enclosing is ClassElement ||
          enclosing is MixinElement ||
          enclosing is ExtensionElement) {
        final enclName = (enclosing as dynamic).name as String?;
        if (enclName != null &&
            enclName != enclosingClass?.namePart.typeName.lexeme) {
          target = enclosing;
          name = enclName;
          member = element;
        } else {
          target = element;
          name = element.name;
        }
      } else {
        return;
      }
    } else if (element is TypeParameterElement) {
      return;
    } else {
      return;
    }

    if (name == null || name.isEmpty) return;

    String? filePath;
    // The fragment that declares the element, which is the file it is written
    // in. `library.source` names the file that *defines the library* instead,
    // so every declaration in a `part` file reported its library's path: the
    // same-file lookup then searched a unit that does not declare it, found
    // nothing, and marked the name processed on the way out.
    try {
      final dynamic fragment = (target as dynamic)?.firstFragment;
      final path = fragment?.libraryFragment?.source?.fullName;
      if (path is String) filePath = path;
    } catch (_) {}
    // Try legacy source.fullName (analyzer < 10)
    try {
      filePath ??= (target as dynamic)?.library?.source?.fullName;
    } catch (_) {}
    try {
      filePath ??= (element as dynamic)?.source?.fullName;
    } catch (_) {}
    // analyzer 10.x removed LibraryElement.source; use library.identifier URI instead
    if (filePath == null) {
      try {
        final dynamic tLib = (target as dynamic)?.library;
        final dynamic eLib = (element as dynamic)?.library;
        final uriStr = (tLib?.identifier ?? eLib?.identifier) as String?;
        if (uriStr != null) {
          if (uriStr.startsWith('file:')) {
            filePath = Uri.parse(uriStr).toFilePath();
          } else if (uriStr.startsWith('package:') && _session != null) {
            try {
              final dynamic converter = (_session as dynamic).uriConverter;
              filePath = converter?.uriToPath(Uri.parse(uriStr)) as String?;
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    if (filePath == null) return;

    final key = '$filePath::$name';
    // Not an early return any more: the first reference to a third-party type
    // marks it processed, and every later one names a *different* member the
    // shim still has to carry.
    final bool alreadySeen = !_processedKeys.add(key);

    if (!isProjectLocal(filePath)) {
      final uri =
          target?.library?.identifier ?? element.library?.identifier ?? '';

      // Only collect imports for the Flutter SDK and Dart SDK.
      // Third-party packages (flutter_bloc, provider, get, etc.) are excluded
      // because we focus on the widget tree structure, not external state managers.
      if (!isSdkLibrary(uri)) {
        // Importing the package back is not an option, since preventing that
        // is what this gate is for, but dropping the name silently leaves the
        // isolated file unanalyzable. A declaration-only stand-in resolves it
        // while mirroring whether it was a widget, which is the one property
        // the feature extractor reads off the supertype chain.
        shims?.request(target ?? element, member: member);
        return;
      }
      if (alreadySeen) return;

      // Find the matching import directives in the source file so that the
      // exact URI and any `as` / `show` / `hide` clauses are preserved. Every
      // match is taken rather than the first: a file that imports one library
      // both plainly and under a prefix needs both directives, since the
      // transplanted body may write either form.
      bool found = false;
      try {
        for (final directive in originResult.unit.directives) {
          if (directive is! ImportDirective) continue;
          try {
            // `libraryImport` is where analyzer ≥ 13 keeps this. The older
            // `element` / `element2` spellings are kept as a fallback, but they
            // throw on the current analyzer, which silently made this whole
            // branch dead: every import fell through to the URI-only fallback,
            // and with it every `show`, `hide` and `as` clause.
            final dynamic d = directive;
            Object? importedLib;
            try {
              importedLib = directive.libraryImport?.importedLibrary;
            } catch (_) {}
            if (importedLib == null) {
              try {
                importedLib = d.element?.importedLibrary;
              } catch (_) {}
            }
            if (importedLib == null) {
              try {
                importedLib = d.element2?.importedLibrary;
              } catch (_) {}
            }
            if (importedLib != null && _isFromLibrary(element, importedLib)) {
              imports.addDirective(directive);
              found = true;
            }
          } catch (_) {}
        }
      } catch (_) {}

      if (!found) {
        // Fallback: construct an import from the library's canonical URI, under
        // whatever prefix the reference itself was written with.
        try {
          if (uri.isNotEmpty &&
              uri != 'dart:core' &&
              !uri.startsWith('file:')) {
            var importUri = uri;
            if (uri.startsWith('package:flutter/src/')) {
              final parts = uri.split('/');
              if (parts.length > 2) {
                importUri = 'package:flutter/${parts[2]}.dart';
              }
            }
            imports.add(importUri, prefix: _prefixAtUseSite(node));
          }
        } catch (_) {}
      }
      return;
    }

    if (alreadySeen) return;

    if (filePath == originResult.path) {
      // A lookup that finds nothing used to end here, with the name marked
      // processed so no later reference would retry it. A stand-in keeps the
      // file analysable, and keeps a widget reading as a widget.
      if (!_extractSameFile(name)) {
        shims?.request(target ?? element, member: member, allMembers: true);
      }
    } else {
      crossFileRefs.add((
        filePath: filePath,
        name: name,
        element: target ?? element,
      ));
    }
  }

  /// Extracts the source code for a dependency located in the same file.
  ///
  /// Returns false when nothing declaring [name] was found, so the caller can
  /// fall back to a stand-in rather than leave the reference dangling.
  bool _extractSameFile(String name) {
    if (name == 'build') return true;
    // `State` already supplies `context`. Some classes declare a field of the
    // same name (nMobile's `BottomDialog` does); copying it across shadows the
    // real one and the isolated file stops compiling.
    if (name == 'context') return true;

    if (enclosingClass != null) {
      for (final member in (enclosingClass!.body as BlockClassBody).members) {
        if (member is MethodDeclaration && member.name.lexeme == name) {
          memberCode += '\n${Skeletonizer.skeletonize(member, originResult)}\n';
          member.accept(this);
          return true;
        } else if (member is FieldDeclaration) {
          for (final variable in member.fields.variables) {
            if (variable.name.lexeme == name) {
              memberCode +=
                  '\n${Skeletonizer.skeletonize(member, originResult)}\n';
              member.accept(this);
              return true;
            }
          }
        }
      }
    }

    for (final decl in originResult.unit.declarations) {
      if (declaredNames(decl).contains(name)) {
        classCode += '\n${Skeletonizer.skeletonize(decl, originResult)}\n';
        emittedNames.addAll(declaredNames(decl));
        decl.accept(this);
        return true;
      }
    }
    return false;
  }

  /// Safely extracts the [Element] from an AST node and passes it to [_handleElement].
  void _safeHandle(dynamic node) {
    if (node == null) return;
    Element? element;
    try {
      element = node.staticElement;
    } catch (_) {}
    if (element == null) {
      try {
        element = node.element;
      } catch (_) {}
    }
    if (element == null) {
      try {
        element = node.element2;
      } catch (_) {}
    }
    if (element != null) {
      _handleElement(element, node: node is AstNode ? node : null);
    }
  }

  /// Records [member] on the shim for the type the code actually names.
  ///
  /// [_handleElement] keys a member to the class that *declares* it, which is
  /// the wrong owner whenever the declaration is inherited from elsewhere.
  /// `VideoPlayerController.addListener` is declared on `ChangeNotifier`, a
  /// Flutter type, so the reference took the import branch and the member was
  /// never recorded on the controller's stand-in. The result is a stub that
  /// carries `removeListener` but not `addListener`, which type-checks in some
  /// places and not others, so the file fails in a way that looks unrelated to
  /// the member set.
  ///
  /// Only third-party receivers are recorded. A project-local one is inlined
  /// whole or shimmed with its full surface, and an SDK one is imported.
  void _recordOnReceiver(Expression? target, Element? member) {
    if (target == null || member == null || shims == null) return;

    final type = target.staticType;
    if (type is! InterfaceType) return;
    final owner = type.element;

    final uri = _libraryUri(owner);
    if (uri == null || isSdkLibrary(uri)) return;

    final path = _pathOfLibrary(owner);
    if (path != null && isProjectLocal(path)) return;

    shims!.request(owner, member: member);
  }

  static String? _libraryUri(Element element) {
    try {
      return element.library?.identifier;
    } catch (_) {}
    return null;
  }

  /// The file path backing [element]'s library, when it can be found.
  String? _pathOfLibrary(Element element) {
    try {
      final dynamic full = (element as dynamic).library?.source?.fullName;
      if (full is String) return full;
    } catch (_) {}
    final uri = _libraryUri(element);
    if (uri == null) return null;
    if (uri.startsWith('file:')) return Uri.parse(uri).toFilePath();
    if (uri.startsWith('package:') && _session != null) {
      try {
        final dynamic converter = (_session as dynamic).uriConverter;
        return converter?.uriToPath(Uri.parse(uri)) as String?;
      } catch (_) {}
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // References that resolved to nothing
  // ---------------------------------------------------------------------------

  /// The type name an extension may be written on, or null when the receiver's
  /// type cannot be named in the isolated file.
  ///
  /// A third-party receiver is requested as a shim on the way past, so the
  /// extension always has something to extend.
  String? _extendableTypeName(Expression? target) {
    if (target == null) return null;
    final type = target.staticType;
    if (type is! InterfaceType) return null;
    final owner = type.element;
    final name = owner.name;
    if (name == null || name.isEmpty) return null;

    // `10.sp` and `1.5.sp` reach the same extension in the package that
    // declares it, which writes `on num`. Widening here keeps one stand-in
    // instead of one per numeric type.
    if (name == 'int' || name == 'double') return 'num';

    final uri = _libraryUri(owner);
    if (uri == null) return null;
    if (isSdkLibrary(uri)) return name;

    final path = _pathOfLibrary(owner);
    if (path != null && isProjectLocal(path)) return name;

    shims?.request(owner);
    return name;
  }

  /// Records an unresolved `receiver.name(...)` as an extension method.
  ///
  /// `context.read<T>()` is the case this exists for. The extension that
  /// defines `read` lives in provider or flutter_bloc, which the import gate
  /// refuses, so the reference has nowhere to resolve. Restoring it as an
  /// extension on `BuildContext` names neither package and covers `watch` and
  /// `select` by the same rule, along with `10.sp` on `num` and any other
  /// extension a package hangs off an SDK type.
  void _handleUnresolvedInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final onType = _extendableTypeName(node.realTarget);
    if (onType != null) {
      synthetics?.requestExtensionMember(
        onType,
        name,
        isGetter: false,
        typeArgumentCount: node.typeArguments?.arguments.length ?? 0,
        positional: _positionalArguments(node.argumentList),
        named: _namedArguments(node.argumentList),
      );
      return;
    }
    if (node.realTarget != null) return;

    // No receiver: either a constructor call written without `const` or `new`,
    // which is how most widget construction is written, or a plain function
    // call. Casing is the only signal left, and it is the convention Dart
    // itself relies on.
    if (_looksLikeTypeName(name)) {
      synthetics?.requestClass(
        name,
        isWidget: _looksLikeWidgetPosition(node),
        typeArgumentCount: node.typeArguments?.arguments.length ?? 0,
        positionalCount: _positionalArguments(node.argumentList).length,
        named: _namedArguments(node.argumentList),
      );
      return;
    }
    synthetics?.requestGlobal(name);
  }

  static List<String> _positionalArguments(ArgumentList arguments) => [
    for (final argument in arguments.arguments)
      if (argument is! NamedArgument) argument.toSource(),
  ];

  static List<String> _namedArguments(ArgumentList arguments) => [
    for (final argument in arguments.arguments)
      if (argument is NamedArgument) argument.name.lexeme,
  ];

  /// Whether [name] reads as a type rather than as a function.
  static bool _looksLikeTypeName(String name) {
    final bare = name.replaceFirst(RegExp(r'^_+'), '');
    if (bare.isEmpty) return false;
    return bare[0].toUpperCase() == bare[0] && bare[0].toLowerCase() != bare[0];
  }

  /// Argument names that hold widgets, used to decide whether an unresolved
  /// constructor call stands in for a widget.
  ///
  /// Widget-ness is the one property a stand-in has to get right, since
  /// `BuildMetricsVisitor` sorts an allocation into `widgetCount` or
  /// `valueObjectAllocCount` by walking the supertype chain.
  static const Set<String> _widgetArgumentNames = {
    'child',
    'children',
    'body',
    'title',
    'subtitle',
    'leading',
    'trailing',
    'icon',
    'label',
    'content',
    'header',
    'footer',
    'appBar',
    'bottomNavigationBar',
    'floatingActionButton',
    'flexibleSpace',
    'drawer',
    'endDrawer',
    'home',
    'builder',
    'separatorBuilder',
    'itemBuilder',
  };

  bool _looksLikeWidgetPosition(AstNode node) {
    AstNode? current = node;
    while (current != null) {
      final parent = current.parent;
      if (parent == null) return false;
      if (parent is NamedArgument) {
        return _widgetArgumentNames.contains(parent.name.lexeme);
      }
      if (parent is ReturnStatement || parent is ExpressionFunctionBody) {
        return _returnsWidget(parent);
      }
      if (parent is ListLiteral ||
          parent is ConditionalExpression ||
          parent is ParenthesizedExpression) {
        current = parent;
        continue;
      }
      if (parent is ArgumentList || parent is InstanceCreationExpression) {
        current = parent;
        continue;
      }
      return false;
    }
    return false;
  }

  /// Whether the function [node] returns from is declared to build UI.
  static bool _returnsWidget(AstNode node) {
    final method = node.thisOrAncestorOfType<MethodDeclaration>();
    final returnType = method?.returnType?.toSource() ?? '';
    if (returnType.contains('Widget')) return true;
    final function = node.thisOrAncestorOfType<FunctionDeclaration>();
    return (function?.returnType?.toSource() ?? '').contains('Widget');
  }

  /// Whether [node] is the trailing half of a qualified name, a label, or any
  /// other position where a bare identifier is not a free reference.
  static bool _isQualifiedTail(SimpleIdentifier node) {
    final parent = node.parent;
    if (parent is PropertyAccess && identical(parent.propertyName, node)) {
      return true;
    }
    if (parent is PrefixedIdentifier && identical(parent.identifier, node)) {
      return true;
    }
    if (parent is MethodInvocation && identical(parent.methodName, node)) {
      return true;
    }
    if (parent is Label) return true;
    if (parent is ConstructorName || parent is NamedType) return true;
    if (parent is Declaration || parent is VariableDeclaration) return true;
    if (parent is FormalParameter) return true;
    return false;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_elementOf(node) == null && !_isQualifiedTail(node)) {
      // Locals and parameters resolve even in a project whose dependencies are
      // missing, so an unresolved bare identifier is a genuinely free name.
      synthetics?.requestGlobal(node.name);
    }
    _safeHandle(node);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    // Try node directly first, then fall back to the resolved DartType's element
    Element? element;
    try {
      element = (node as dynamic).element as Element?;
    } catch (_) {}
    if (element == null) {
      try {
        element = (node as dynamic).type?.element as Element?;
      } catch (_) {}
    }
    if (element == null) {
      try {
        element = (node.type as dynamic)?.element as Element?;
      } catch (_) {}
    }
    if (element != null) {
      _handleElement(element, node: node);
    } else if (node.importPrefix == null &&
        node.question == null &&
        _looksLikeTypeName(node.name.lexeme)) {
      // An unresolved type annotation. A stand-in for it is not a widget: only
      // a construction site can tell, and this is not one.
      //
      // The casing test is not style policing: `void` has no element either,
      // and standing it in produced `class void {}`, which does not parse.
      synthetics?.requestClass(
        node.name.lexeme,
        isWidget: false,
        typeArgumentCount: node.typeArguments?.arguments.length ?? 0,
      );
      _safeHandle(node);
    } else {
      _safeHandle(node);
    }
    super.visitNamedType(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    _safeHandle(node);
    super.visitAnnotation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final member = _elementOf(node.methodName);
    if (member == null) {
      _handleUnresolvedInvocation(node);
    } else {
      _safeHandle(node.methodName);
      _recordOnReceiver(node.realTarget, member);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final member = _elementOf(node.propertyName);
    if (member == null) {
      final onType = _extendableTypeName(node.realTarget);
      if (onType != null) {
        synthetics?.requestExtensionMember(
          onType,
          node.propertyName.name,
          isGetter: true,
        );
      }
    } else {
      _recordOnReceiver(node.realTarget, member);
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    // An import prefix is not a receiver; `math.pi` names a library member.
    if (!_isPrefixElement(node.prefix)) {
      final member = _elementOf(node.identifier);
      if (member == null) {
        final onType = _extendableTypeName(node.prefix);
        if (onType != null) {
          synthetics?.requestExtensionMember(
            onType,
            node.identifier.name,
            isGetter: true,
          );
        }
      } else {
        _recordOnReceiver(node.prefix, member);
      }
    }
    super.visitPrefixedIdentifier(node);
  }

  /// The resolved element behind [node], across the spellings the analyzer has
  /// used for it.
  static Element? _elementOf(dynamic node) {
    if (node == null) return null;
    for (final read in [
      () => node.element,
      () => node.staticElement,
      () => node.element2,
    ]) {
      try {
        final value = read();
        if (value is Element) return value;
      } catch (_) {}
    }
    return null;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_elementOf(node.constructorName) == null) {
      final type = node.constructorName.type;
      if (type.importPrefix == null) {
        synthetics?.requestClass(
          type.name.lexeme,
          isWidget: _looksLikeWidgetPosition(node),
          typeArgumentCount: type.typeArguments?.arguments.length ?? 0,
          positionalCount: _positionalArguments(node.argumentList).length,
          named: _namedArguments(node.argumentList),
        );
      }
    }
    _safeHandle(node.constructorName);
    super.visitInstanceCreationExpression(node);
  }
}
