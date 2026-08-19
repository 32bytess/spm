import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;
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

  /// A set of unique import statements for external packages and SDK libraries.
  final Set<String> packageImports;

  /// Collected source code for members (methods/fields) of the [enclosingClass].
  String memberCode = '';

  /// Collected source code for top-level declarations or classes from other files.
  String classCode = '';

  /// A list of references found in other files that need to be resolved and extracted.
  final List<({String filePath, String name})> crossFileRefs = [];

  /// The analysis session, used to convert `package:` URIs to file paths.
  final AnalysisSession? _session;

  DependencyExtractorVisitor(
    this.originResult,
    this.enclosingClass,
    this._processedKeys,
    this.packageImports, [
    this._session,
  ]);

  /// Returns true if the [filePath] belongs to the local project (not a package or SDK).
  bool isProjectLocal(String filePath) {
    final root = originResult.session.analysisContext.contextRoot.root.path;
    return p.isWithin(root, filePath) || p.equals(root, filePath);
  }

  /// Returns true if [element]'s library is provided by [importedLib] —
  /// either directly or via one level of re-exports.
  static bool _isFromLibrary(Element element, dynamic importedLib) {
    try {
      // Use identifier (canonical URI) to compare libraries; avoid .source
      // which was removed from LibraryElement in analyzer ≥ 10.
      final dynamic elementLib = element.library;
      final elementUri = elementLib?.identifier as String?;
      if (elementUri == null) return false;
      if ((importedLib?.identifier as String?) == elementUri) return true;
      for (final exported
          in (importedLib?.exportedLibraries as Iterable? ?? const [])) {
        if (((exported as dynamic)?.identifier as String?) == elementUri) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Processes an [Element] to determine if it needs to be extracted.
  void _handleElement(Element element) {
    String? name;
    Element? target;

    // Resolve the actual target element and its name based on the element type
    if (element is ConstructorElement) {
      final enclosing = element.enclosingElement;
      if (enclosing is ClassElement) {
        target = enclosing;
        name = enclosing.name;
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
        if (enclosing is ClassElement) {
          if (enclosing.name == enclosingClass?.namePart.typeName.lexeme) {
            target = element;
            name = element.name;
          } else {
            target = enclosing;
            name = enclosing.name;
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
    // Try legacy source.fullName (analyzer < 10)
    try {
      filePath = (target as dynamic)?.library?.source?.fullName;
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
    if (!_processedKeys.add(key)) return;

    if (!isProjectLocal(filePath)) {
      final uri =
          target?.library?.identifier ?? element.library?.identifier ?? '';

      // Only collect imports for the Flutter SDK and Dart SDK.
      // Third-party packages (flutter_bloc, provider, get, etc.) are excluded
      // because we focus on the widget tree structure, not external state managers.
      final bool isFlutterOrDart =
          uri.startsWith('package:flutter') || uri.startsWith('dart:');
      if (!isFlutterOrDart) return;

      // Find the matching import directive in the source file so that we
      // preserve the exact URI and any `as` / `show` / `hide` clauses.
      bool found = false;
      try {
        for (final directive in originResult.unit.directives) {
          if (directive is! ImportDirective) continue;
          try {
            final dynamic d = directive;
            final importedLib =
                d.element?.importedLibrary ?? d.element2?.importedLibrary;
            if (importedLib != null && _isFromLibrary(element, importedLib)) {
              final src = directive.toSource();
              packageImports.add(src.endsWith(';') ? src : '$src;');
              found = true;
              break;
            }
          } catch (_) {}
        }
      } catch (_) {}

      if (!found) {
        // Fallback: construct an import from the library's canonical URI.
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
            packageImports.add("import '$importUri';");
          }
        } catch (_) {}
      }
      return;
    }

    if (filePath == originResult.path) {
      _extractSameFile(name);
    } else {
      crossFileRefs.add((filePath: filePath, name: name));
    }
  }

  /// Extracts the source code for a dependency located in the same file.
  void _extractSameFile(String name) {
    if (name == 'build') return;
    // `State` already supplies `context`. Some classes declare a field of the
    // same name (nMobile's `BottomDialog` does); copying it across shadows the
    // real one and the isolated file stops compiling.
    if (name == 'context') return;

    if (enclosingClass != null) {
      for (final member in (enclosingClass!.body as BlockClassBody).members) {
        if (member is MethodDeclaration && member.name.lexeme == name) {
          memberCode += '\n${Skeletonizer.skeletonize(member, originResult)}\n';
          member.accept(this);
          return;
        } else if (member is FieldDeclaration) {
          for (final variable in member.fields.variables) {
            if (variable.name.lexeme == name) {
              memberCode +=
                  '\n${Skeletonizer.skeletonize(member, originResult)}\n';
              member.accept(this);
              return;
            }
          }
        }
      }
    }

    for (final decl in originResult.unit.declarations) {
      if (_nameOf(decl) == name) {
        classCode += '\n${Skeletonizer.skeletonize(decl, originResult)}\n';
        decl.accept(this);
        return;
      } else if (decl is TopLevelVariableDeclaration) {
        for (final variable in decl.variables.variables) {
          if (variable.name.lexeme == name) {
            classCode += '\n${Skeletonizer.skeletonize(decl, originResult)}\n';
            decl.accept(this);
            return;
          }
        }
      }
    }
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
    if (element != null) _handleElement(element);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
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
      _handleElement(element);
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
    _safeHandle(node.methodName);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _safeHandle(node.constructorName);
    super.visitInstanceCreationExpression(node);
  }
}

String? _nameOf(CompilationUnitMember decl) {
  if (decl is ClassDeclaration) return decl.namePart.typeName.lexeme;
  if (decl is EnumDeclaration) return decl.namePart.typeName.lexeme;
  if (decl is FunctionDeclaration) return decl.name.lexeme;
  if (decl is MixinDeclaration) return decl.name.lexeme;
  if (decl is GenericTypeAlias) return decl.name.lexeme;
  if (decl is ClassTypeAlias) return decl.name.lexeme;
  return null;
}
