import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:spm/core/errors/exceptions.dart';
import 'package:spm/features/isolation/data/data_sources/helpers/skeletonizer.dart';
import 'package:spm/features/isolation/data/data_sources/sets/isolation_match_set.dart';
import 'package:spm/features/isolation/data/data_sources/visitors/dependency_extractor_visitor.dart';
import 'package:spm/features/isolation/data/data_sources/visitors/rebuild_scope_visitor.dart';

/// Extracts and transforms a discovered rebuild scope into a standalone [StatefulWidget].
///
/// This class handles the "transplantation" process, where a scope (like a `State`
/// class or a `BlocBuilder` builder function) is extracted from its original
/// context and wrapped into a new, generated widget that includes all its
/// transitive dependencies.
class TransplantExtractor {
  /// Extracts the source code for [match] and returns it as a full Dart file.
  ///
  /// [result]: The analysis result of the file containing the match.
  /// [session]: The current analysis session for cross-file resolution.
  Future<String> extract(
    IsolationMatch match,
    ResolvedUnitResult result,
    AnalysisSession session,
  ) async {
    try {
      return await _extract(match, result, session);
    } on IsolationException {
      rethrow;
    } catch (e, st) {
      throw IsolationException(
        'Failed to transplant ${match.name}: $e',
        st.toString(),
      );
    }
  }

  /// Internal implementation of the extraction logic.
  Future<String> _extract(
    IsolationMatch match,
    ResolvedUnitResult result,
    AnalysisSession session,
  ) async {
    final scopeNode = match.scopeNode;
    String buildBody;
    String paramFields = '';

    // Identify the enclosing class if the scope is part of one (e.g., a State class)
    final enclosingClass = scopeNode is ClassDeclaration
        ? scopeNode
        : scopeNode.thisOrAncestorOfType<ClassDeclaration>();

    final processedKeys = <String>{};
    processedKeys.add('${result.path}::${match.name}');

    final externalImports = <String>{"import 'package:flutter/material.dart';"};

    final extractor = DependencyExtractorVisitor(
      result,
      enclosingClass,
      processedKeys,
      externalImports,
      session,
    );

    String widgetFields = '';
    String widgetConstructor = '  const GeneratedWidget({super.key});';

    // If we're isolating a full State class, we also need to look at its companion StatefulWidget
    if (scopeNode is ClassDeclaration) {
      if (match.type == 'State') {
        final statefulName = scopeNode
            .extendsClause
            ?.superclass
            .typeArguments
            ?.arguments
            .first
            .toSource();
        if (statefulName != null) {
          ClassDeclaration? statefulDecl;
          for (final decl in result.unit.declarations) {
            if (decl is ClassDeclaration && decl.namePart.typeName.lexeme == statefulName) {
              statefulDecl = decl;
              break;
            }
          }

          if (statefulDecl != null) {
            processedKeys.add('${result.path}::${statefulDecl.namePart.typeName.lexeme}');
            // Extract fields from the StatefulWidget to include in the generated widget
            final fields = (statefulDecl.body as BlockClassBody).members.whereType<FieldDeclaration>();
            for (final field in fields) {
              for (final v in field.fields.variables) {
                processedKeys.add('${result.path}::${v.name.lexeme}');
              }
              widgetFields += '  ${Skeletonizer.skeletonize(field, result)}\n';
              field.accept(extractor);
            }

            // Extract the constructor of the StatefulWidget
            final constructors = (statefulDecl.body as BlockClassBody).members
                .whereType<ConstructorDeclaration>();
            if (constructors.isNotEmpty) {
              final mainCtor = constructors.first;
              var ctorSource = Skeletonizer.skeletonize(mainCtor, result);
              ctorSource = ctorSource.replaceFirst(
                statefulDecl.namePart.typeName.lexeme,
                'GeneratedWidget',
              );
              widgetConstructor = '  $ctorSource';
              mainCtor.accept(extractor);
            }
          }
        }
      }

      // Pre-mark all class members before any visitor traversal to prevent
      // _extractSameFile from adding members before the explicit loop below.
      for (final member in (scopeNode.body as BlockClassBody).members) {
        if (member is MethodDeclaration) {
          processedKeys.add('${result.path}::${member.name.lexeme}');
        } else if (member is FieldDeclaration) {
          for (final v in member.fields.variables) {
            processedKeys.add('${result.path}::${v.name.lexeme}');
          }
        } else if (member is ConstructorDeclaration) {
          if (member.name != null) {
            processedKeys.add('${result.path}::${member.name!.lexeme}');
          }
        }
      }

      // Handle the build method and its parameters
      final buildMethod = RebuildScopeVisitor.findBuildMethod(scopeNode);
      if (buildMethod != null) {
        processedKeys.add('${result.path}::build');
        if (buildMethod.parameters != null) {
          for (final param in buildMethod.parameters!.parameters) {
            final name = _getParamName(param);
            final type = _getParamType(param);
            if (name != null && name != 'context') {
              processedKeys.add('${result.path}::$name');
              paramFields += '    late $type $name;\n';
              param.accept(extractor);
            }
          }
        }

        final body = buildMethod.body;
        if (body is BlockFunctionBody) {
          buildBody = body.block.statements
              .map((s) => '    ${Skeletonizer.skeletonize(s, result)}')
              .join('\n');
        } else if (body is ExpressionFunctionBody) {
          buildBody =
              '    return ${Skeletonizer.skeletonize(body.expression, result)};';
        } else {
          buildBody = '    ${Skeletonizer.skeletonize(body, result)}';
        }

        final payload = RebuildScopeVisitor.extractScopeFromBody(
          buildMethod.body,
        );
        payload.accept(extractor);
      } else {
        buildBody = '    return Container();';
      }

      // Collect class-level metadata (annotations, extends, etc.)
      scopeNode.metadata.accept(extractor);
      scopeNode.extendsClause?.accept(extractor);
      scopeNode.implementsClause?.accept(extractor);
      scopeNode.withClause?.accept(extractor);

      // Extract all members of the original class (methods, fields, getters)
      for (final member in (scopeNode.body as BlockClassBody).members) {
        if (member is MethodDeclaration && member.name.lexeme == 'build') {
          continue;
        }
        extractor.memberCode +=
            '\n${Skeletonizer.skeletonize(member, result)}\n';
        member.accept(extractor);
      }
    } else if (scopeNode is Block) {
      // Handle a raw block of code (uncommon but supported)
      buildBody = scopeNode.statements
          .map((s) => '    ${Skeletonizer.skeletonize(s, result)}')
          .join('\n');
      scopeNode.accept(extractor);
    } else if (scopeNode is FunctionExpression) {
      // Handle builder functions (e.g., BlocBuilder builder: (context, state) => ...)
      final body = scopeNode.body;
      if (body is BlockFunctionBody) {
        buildBody = body.block.statements
            .map((s) => '    ${Skeletonizer.skeletonize(s, result)}')
            .join('\n');
      } else if (body is ExpressionFunctionBody) {
        buildBody =
            '    return ${Skeletonizer.skeletonize(body.expression, result)};';
      } else {
        buildBody = '    ${Skeletonizer.skeletonize(body, result)}';
      }

      if (scopeNode.parameters != null) {
        for (final param in scopeNode.parameters!.parameters) {
          final name = _getParamName(param);
          final type = _getParamType(param, scopeNode, match.type);
          if (name != null && name != 'context') {
            paramFields += '    late $type $name;\n';
            param.accept(extractor);
          }
        }
      }
      scopeNode.accept(extractor);
    } else {
      // Fallback for any other expression node
      buildBody = '    return ${Skeletonizer.skeletonize(scopeNode, result)};';
      scopeNode.accept(extractor);
    }

    // Recursively resolve cross-file references found by the visitor
    final pending = List<({String filePath, String name})>.from(
      extractor.crossFileRefs,
    );

    while (pending.isNotEmpty) {
      final ref = pending.removeAt(0);

      final unitResult = await session.getResolvedUnit(ref.filePath);
      if (unitResult is! ResolvedUnitResult) continue;

      for (final decl in unitResult.unit.declarations) {
        bool matchFound = false;
        if (_nameOf(decl) == ref.name) {
          matchFound = true;
        } else if (decl is TopLevelVariableDeclaration) {
          for (final variable in decl.variables.variables) {
            if (variable.name.lexeme == ref.name) {
              matchFound = true;
              break;
            }
          }
        }

        if (matchFound) {
          // Only include declarations relevant to the widget build tree:
          //  - EnumDeclaration       → include + recurse
          //  - widget ClassDeclaration → include + recurse (find its widget/enum deps too)
          //  - Widget-returning FunctionDeclaration → include + recurse
          //  - Everything else (models, services, constants) → skip
          final bool isWidget =
              decl is ClassDeclaration && _isUiClass(decl);
          final bool isWidgetFn =
              decl is FunctionDeclaration && _returnsUi(decl);

          if (decl is EnumDeclaration || isWidget || isWidgetFn) {
            extractor.classCode +=
                '\n${Skeletonizer.skeletonize(decl, unitResult)}\n';

            // For StatefulWidgets, pull in the companion State class.
            if (isWidget && _isStatefulWidget(decl as ClassDeclaration)) {
              _includeCompanionState(
                  decl, unitResult, extractor, processedKeys);
            }

            // Recurse: visit this declaration and feed its cross-file refs
            // back into pending. The same widget/enum gate applies at the
            // next iteration, so non-widget deps are still skipped.
            final sub = DependencyExtractorVisitor(
              unitResult,
              isWidget ? decl as ClassDeclaration : null,
              processedKeys,
              externalImports,
              session,
            );
            decl.accept(sub);
            pending.addAll(sub.crossFileRefs);
          }
          break;
        }
      }
    }

    final fullClassCode = extractor.classCode;

    // Scan all collected code for `prefix.` patterns so that imports with an
    // `as X` alias are included even when the package wasn't resolved by the
    // analyzer (unresolved imports give a null element, bypassing normal detection).
    final allCode =
        buildBody +
        extractor.memberCode +
        fullClassCode +
        paramFields +
        widgetFields;
    for (final directive in result.unit.directives) {
      if (directive is! ImportDirective) continue;
      final prefix = (directive as dynamic).prefix?.name as String?;
      if (prefix == null || !allCode.contains('$prefix.')) continue;
      // Apply the same flutter/dart-only filter used in the visitor —
      // prefix-aliased imports from 3rd party packages are excluded.
      final uriValue = (directive as dynamic).uri?.stringValue as String? ??
          directive.toSource();
      final isFlutterOrDart =
          uriValue.startsWith('package:flutter') || uriValue.startsWith('dart:');
      if (!isFlutterOrDart) continue;
      final src = directive.toSource();
      externalImports.add(src.endsWith(';') ? src : '$src;');
    }

    // Generate the final self-contained file
    return '''
${externalImports.join('\n')}

class GeneratedWidget extends StatefulWidget {
$widgetFields
$widgetConstructor

  @override
  State<GeneratedWidget> createState() => _GeneratedWidgetState();
}

class _GeneratedWidgetState extends State<GeneratedWidget> {
$paramFields

${extractor.memberCode}

  @override
  Widget build(BuildContext context) {
$buildBody
  }
}

$fullClassCode
''';
  }

  /// Extracts the name of a formal parameter.
  String? _getParamName(FormalParameter param) {
    if (param is NormalFormalParameter) return param.name?.lexeme;
    if (param is FieldFormalParameter) return param.name.lexeme;
    return null;
  }

  /// Infers the type of a formal parameter, with fallbacks for builder
  /// functions where types can be extracted from the parent widget's type
  /// arguments (e.g., `BlocBuilder<B, S>`).
  String _getParamType(
    FormalParameter param, [
    FunctionExpression? parentFunc,
    String? widgetType,
  ]) {
    // Step 1: resolve from the element's declared type.
    // Uses declaredFragment.element (analyzer ≥ 10) with a fallback to
    // declaredElement for older versions.
    try {
      final dynamic p = param;
      dynamic element;
      try {
        element = p.declaredFragment?.element;
      } catch (_) {}
      if (element == null) {
        try {
          element = p.declaredElement;
        } catch (_) {}
      }
      if (element != null) {
        final dynamic type = element.type;
        if (type != null) {
          final typeStr = type.getDisplayString() as String;
          // Object? / Object are upper bounds that carry no useful info.
          if (typeStr != 'dynamic' &&
              typeStr != 'Object?' &&
              typeStr != 'Object') {
            return typeStr.replaceAll('?', '');
          }
        }
      }
    } catch (_) {}

    if (parentFunc != null) {
      // Step 2: try from the parent function's static type.
      try {
        final dynamic funcType = parentFunc.staticType;
        if (funcType != null && funcType.toString().contains('Function')) {
          final dynamic parameters = funcType.parameters;
          final index = parentFunc.parameters?.parameters.indexOf(param);
          if (index != null &&
              index != -1 &&
              index < (parameters?.length ?? 0)) {
            final typeStr = parameters[index].type.getDisplayString() as String;
            if (typeStr != 'dynamic' &&
                typeStr != 'Object?' &&
                typeStr != 'Object') {
              return typeStr.replaceAll('?', '');
            }
          }
        }
      } catch (_) {}

      // Step 3: walk up to a generic widget (BlocBuilder, Consumer, …) and
      // extract the state/model type from its type arguments.
      try {
        AstNode? current = parentFunc.parent;
        while (current != null) {
          if (current is InstanceCreationExpression) {
            final name = current.constructorName.type.name.lexeme;
            if (widgetType != null && name.contains(widgetType)) break;
            if ([
              'BlocBuilder',
              'Consumer',
              'Selector',
              'BlocSelector',
              'BlocConsumer',
            ].any((t) => name.contains(t))) {
              break;
            }
          }
          if (current is CompilationUnit) {
            current = null;
            break;
          }
          current = current.parent;
        }

        if (current is InstanceCreationExpression) {
          final String ctorSource = current.constructorName.toSource();
          if (ctorSource.contains('<')) {
            final typeArgsStr = ctorSource.substring(
              ctorSource.indexOf('<') + 1,
              ctorSource.lastIndexOf('>'),
            );
            final args = _splitTypeArgs(typeArgsStr);
            final typeName = current.constructorName.type.name.lexeme;

            if ((typeName.contains('BlocBuilder') ||
                    typeName.contains('Selector') ||
                    typeName.contains('BlocSelector') ||
                    typeName.contains('BlocConsumer')) &&
                args.length >= 2) {
              return args[1].trim().replaceAll('?', '');
            } else if (typeName.contains('Consumer') && args.isNotEmpty) {
              return args[0].trim().replaceAll('?', '');
            }
          }
        }
      } catch (_) {}
    }

    // Step 4: use the syntactic type annotation if present.
    try {
      if (param is FieldFormalParameter && param.type != null) {
        return param.type!.toSource();
      }
      final dynamic dynamicParam = param;
      if (dynamicParam.type != null) {
        return dynamicParam.type.toSource() as String;
      }
    } catch (_) {}

    return 'dynamic';
  }

  /// Splits a type-argument string on commas, respecting nested `<>`.
  List<String> _splitTypeArgs(String src) {
    final result = <String>[];
    int depth = 0;
    int start = 0;
    for (int i = 0; i < src.length; i++) {
      final c = src[i];
      if (c == '<') {
        depth++;
      } else if (c == '>') {
        depth--;
      } else if (c == ',' && depth == 0) {
        result.add(src.substring(start, i).trim());
        start = i + 1;
      }
    }
    if (start < src.length) result.add(src.substring(start).trim());
    return result;
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

/// Base class names that identify a UI-related class.
/// Used for both the fast direct-superclass check and the resolved supertype scan.
const _uiBaseClasses = {
  // Widget hierarchy
  'StatelessWidget', 'StatefulWidget', 'State',
  'InheritedWidget', 'InheritedNotifier', 'InheritedModel',
  'RenderObjectWidget', 'LeafRenderObjectWidget',
  'SingleChildRenderObjectWidget', 'MultiChildRenderObjectWidget',
  'ProxyWidget', 'ParentDataWidget',
  // Painting & clipping
  'CustomPainter', 'CustomClipper',
  // Decoration & shapes
  'Decoration', 'ShapeBorder', 'BoxBorder', 'OutlinedBorder',
  'GradientTransform',
  // Text / inline content
  'InlineSpan',
  // Animation
  'Animatable',
  // Navigation
  'Route',
  // Riverpod / hooks
  'HookWidget', 'HookConsumerWidget', 'ConsumerWidget',
};

/// Return-type substrings that indicate a UI-building function.
const _uiReturnTypes = {
  'Widget', 'CustomPainter', 'CustomClipper',
  'Decoration', 'BoxDecoration', 'ShapeDecoration',
  'ShapeBorder', 'OutlinedBorder', 'InputDecoration',
  'InlineSpan', 'TextSpan', 'WidgetSpan',
  'Animatable', 'Tween', 'Animation',
  'Route', 'PageRoute',
  'PreferredSizeWidget',
};

/// Returns true if [decl] is a UI-related class (widget, painter, decoration, etc.).
bool _isUiClass(ClassDeclaration decl) {
  // Fast path: direct superclass name is in the known set.
  final superName = decl.extendsClause?.superclass.name.lexeme;
  if (superName != null && _uiBaseClasses.contains(superName)) return true;

  // Slow path: walk the resolved supertype chain to catch transitive subclasses
  // (e.g. `class MyCard extends BaseCard` where BaseCard extends StatelessWidget,
  // or `class MyPainter extends _BasePainter` where _BasePainter extends CustomPainter).
  try {
    dynamic element;
    try {
      element = (decl as dynamic).declaredFragment?.element;
    } catch (_) {}
    element ??= (decl as dynamic).declaredElement;
    final supertypes = element?.allSupertypes as List?;
    if (supertypes != null) {
      return supertypes.any(
        (t) => _uiBaseClasses.contains((t as dynamic).element?.name),
      );
    }
  } catch (_) {}
  return false;
}

bool _isStatefulWidget(ClassDeclaration decl) {
  final superName = decl.extendsClause?.superclass.name.lexeme;
  if (superName == 'StatefulWidget') return true;
  try {
    dynamic element;
    try {
      element = (decl as dynamic).declaredFragment?.element;
    } catch (_) {}
    element ??= (decl as dynamic).declaredElement;
    final supertypes = element?.allSupertypes as List?;
    if (supertypes != null) {
      return supertypes.any(
        (t) => (t as dynamic).element?.name == 'StatefulWidget',
      );
    }
  } catch (_) {}
  return false;
}

/// Returns true if [decl] is a function that builds UI (widgets, decorations,
/// painters, spans, routes, etc.).
bool _returnsUi(FunctionDeclaration decl) {
  final returnType = decl.returnType?.toSource() ?? '';
  if (returnType.isEmpty || returnType == 'void') return false;
  return _uiReturnTypes.any((t) => returnType.contains(t));
}

/// Finds and appends the companion `State` subclass for [widgetDecl] by
/// scanning all declarations in [unitResult] for a class whose extends clause
/// matches `State<WidgetName>`.
void _includeCompanionState(
  ClassDeclaration widgetDecl,
  ResolvedUnitResult unitResult,
  DependencyExtractorVisitor extractor,
  Set<String> processedKeys,
) {
  final widgetName = widgetDecl.namePart.typeName.lexeme;
  for (final other in unitResult.unit.declarations) {
    if (other is! ClassDeclaration) continue;
    final superSrc = other.extendsClause?.superclass.toSource() ?? '';
    if (superSrc == 'State<$widgetName>' || superSrc.contains('State<$widgetName>')) {
      final key = '${unitResult.path}::${other.namePart.typeName.lexeme}';
      if (processedKeys.add(key)) {
        extractor.classCode += '\n${Skeletonizer.skeletonize(other, unitResult)}\n';
      }
    }
  }
}
