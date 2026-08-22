import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/features/analysis/data/data_sources/extensions/state_class_detector.dart';
import 'package:spm/src/features/isolation/data/data_sources/emitters/import_collector.dart';
import 'package:spm/src/features/isolation/data/data_sources/emitters/shim_emitter.dart';
import 'package:spm/src/features/isolation/data/data_sources/emitters/synthetic_shim_emitter.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/declaration_names.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/flutter_namespace.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/inline_budget.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/sdk_uris.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/skeletonizer.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/ui_surface.dart';
import 'package:spm/src/features/isolation/data/data_sources/sets/isolation_match_set.dart';
import 'package:spm/src/features/isolation/data/data_sources/visitors/captured_variable_visitor.dart';
import 'package:spm/src/features/isolation/data/data_sources/visitors/dependency_extractor_visitor.dart';
import 'package:spm/src/features/isolation/data/data_sources/visitors/promotion_cast_rewriter.dart';
import 'package:spm/src/features/isolation/data/data_sources/visitors/rebuild_scope_visitor.dart';

/// One transplanted scope, plus what the transplant had to give up to produce it.
///
/// The counts are not decoration. A row whose third-party closure was truncated
/// measures a smaller tree than one that carried it whole, and nothing reading
/// the JSONL downstream could otherwise tell the two apart.
class TransplantResult {
  const TransplantResult({
    required this.source,
    required this.inlinedThirdPartyDeclarations,
    required this.truncated,
  });

  /// The generated Dart file.
  final String source;

  /// How many third-party declarations were carried into it.
  final int inlinedThirdPartyDeclarations;

  /// Whether the inline budget ran out, so some third-party UI was stood in for
  /// that would otherwise have been carried.
  final bool truncated;
}

/// Extracts and transforms a discovered rebuild scope into a standalone [StatefulWidget].
///
/// This class handles the "transplantation" process, where a scope (like a `State`
/// class or a `BlocBuilder` builder function) is extracted from its original
/// context and wrapped into a new, generated widget that includes all its
/// transitive dependencies.
class TransplantExtractor {
  /// [newBudget] builds the inline budget each scope is given. One per scope,
  /// not one per run: a budget shared across scopes would let whichever scope
  /// ran first spend the allowance for all of them, and the output would depend
  /// on file ordering.
  TransplantExtractor({InlineBudget Function()? newBudget})
    : _newBudget = newBudget ?? InlineBudget.new;

  final InlineBudget Function() _newBudget;

  /// The names `package:flutter/material.dart` exports, resolved once and kept.
  ///
  /// Held on the extractor rather than looked up per scope: it is the same
  /// answer for every scope in a run, and resolving material is not free.
  Future<FlutterNamespace>? _flutterNames;

  /// Extracts the source code for [match] and returns it as a full Dart file.
  ///
  /// [result]: The analysis result of the file containing the match.
  /// [session]: The current analysis session for cross-file resolution.
  /// [inlineThirdParty]: whether a third-party declaration that can produce UI
  /// is carried into the output rather than stood in for.
  Future<TransplantResult> extract(
    IsolationMatch match,
    ResolvedUnitResult result,
    AnalysisSession session, {
    bool inlineThirdParty = true,
  }) async {
    try {
      return await _extract(
        match,
        result,
        session,
        inlineThirdParty: inlineThirdParty,
      );
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
  Future<TransplantResult> _extract(
    IsolationMatch match,
    ResolvedUnitResult result,
    AnalysisSession session, {
    required bool inlineThirdParty,
  }) async {
    final budget = _newBudget();
    final flutterNames = inlineThirdParty
        ? await (_flutterNames ??= FlutterNamespace.load(session))
        : FlutterNamespace.empty;
    final scopeNode = match.scopeNode;
    String buildBody;
    String paramFields = '';

    // Names lifted onto the generated State, in emission order. Drives the
    // field list, the generated initState and the promotion casts, so it has
    // to be complete before any source is rendered.
    final liftedFields = <CapturedVariable>[
      ..._liftedParameters(scopeNode, match),
    ];
    final capture = CapturedVariableVisitor(
      result,
      scopeNode.offset,
      scopeNode.end,
      ignore: liftedFields.map((f) => f.name).toSet(),
    );
    scopeNode.accept(capture);
    liftedFields.addAll(capture.captured);
    final liftedGlobals = capture.capturedGlobals;

    // Lifting a promoted parameter onto a field costs it its promotion, so the
    // casts the original code did not need have to be written back in.
    final rewriter = PromotionCastRewriter({
      for (final f in liftedFields) f.name: f.type,
    });

    // Identify the enclosing class if the scope is part of one (e.g., a State class)
    final enclosingClass = scopeNode is ClassDeclaration
        ? scopeNode
        : scopeNode.thisOrAncestorOfType<ClassDeclaration>();

    final processedKeys = <String>{};
    processedKeys.add('${result.path}::${match.name}');

    final imports = ImportCollector()..add('package:flutter/material.dart');

    // Every unit the transplant copied source text out of. The prefix rescan
    // below reads their directives, since inlined code carries the prefixes of
    // the file it came from and nothing else records them.
    final visitedUnits = <CompilationUnit>{result.unit};

    // Names the isolated file declares by inlining, shared across the whole
    // recursion. The shim emitter reads it at render time, so a name inlined
    // late still wins over a shim requested early.
    final emittedNames = <String>{};
    final shims = ShimEmitter(emittedNames);
    final synthetics = SyntheticShimEmitter(emittedNames);

    final extractor = DependencyExtractorVisitor(
      result,
      enclosingClass,
      processedKeys,
      imports,
      session: session,
      shims: shims,
      synthetics: synthetics,
      emittedNames: emittedNames,
      inlineThirdParty: inlineThirdParty,
      budget: budget,
      flutterNames: flutterNames,
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
            if (decl is ClassDeclaration &&
                decl.namePart.typeName.lexeme == statefulName) {
              statefulDecl = decl;
              break;
            }
          }

          if (statefulDecl != null) {
            processedKeys.add(
              '${result.path}::${statefulDecl.namePart.typeName.lexeme}',
            );
            // Extract fields from the StatefulWidget to include in the generated widget
            final fields = (statefulDecl.body as BlockClassBody).members
                .whereType<FieldDeclaration>();
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
      final buildMethod = findBuildMethod(scopeNode);
      if (buildMethod != null) {
        processedKeys.add('${result.path}::build');
        if (buildMethod.parameters != null) {
          for (final param in buildMethod.parameters!.parameters) {
            final name = _getParamName(param);
            if (name != null && name != 'context') {
              processedKeys.add('${result.path}::$name');
              param.accept(extractor);
            }
          }
        }

        final body = buildMethod.body;
        if (body is BlockFunctionBody) {
          buildBody = body.block.statements
              .map(
                (s) =>
                    '    ${Skeletonizer.skeletonize(s, result, rewriter: rewriter)}',
              )
              .join('\n');
        } else if (body is ExpressionFunctionBody) {
          buildBody =
              '    return ${Skeletonizer.skeletonize(body.expression, result, rewriter: rewriter)};';
        } else {
          buildBody =
              '    ${Skeletonizer.skeletonize(body, result, rewriter: rewriter)}';
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

      // A constructor copied into `_GeneratedWidgetState` keeps the name of the
      // class it came from, which no longer matches the class it lands in, so
      // Dart reads it as a bodiless method. The scope's own constructor is
      // never what is measured -- the generated class supplies its own
      // construction -- so it is dropped rather than renamed. What it did
      // supply is field initialisation, and dropping that silently would leave
      // those fields unassigned, so they are marked `late` below.
      final ctorInitialisedFields = <String>{};
      for (final member in (scopeNode.body as BlockClassBody).members) {
        if (member is! ConstructorDeclaration) continue;
        for (final param in member.parameters.parameters) {
          // A default value is a clause on the parameter in analyzer >= 13,
          // not a wrapper node, so `this.x = v` needs no unwrapping.
          if (param is FieldFormalParameter) {
            ctorInitialisedFields.add(param.name.lexeme);
          }
        }
        for (final initializer in member.initializers) {
          if (initializer is ConstructorFieldInitializer) {
            ctorInitialisedFields.add(initializer.fieldName.name);
          }
        }
      }

      // Extract all members of the original class (methods, fields, getters)
      for (final member in (scopeNode.body as BlockClassBody).members) {
        if (member is MethodDeclaration && member.name.lexeme == 'build') {
          continue;
        }
        if (member is ConstructorDeclaration) {
          // Still traversed: default values and initialiser expressions can
          // reference declarations the isolated file needs.
          member.accept(extractor);
          continue;
        }
        var source = Skeletonizer.skeletonize(
          member,
          result,
          rewriter: rewriter,
        );
        if (member is FieldDeclaration &&
            !member.isStatic &&
            member.fields.lateKeyword == null &&
            member.fields.variables.any(
              (v) =>
                  v.initializer == null &&
                  ctorInitialisedFields.contains(v.name.lexeme),
            )) {
          source = 'late $source';
        }
        extractor.memberCode += '\n$source\n';
        member.accept(extractor);
      }
    } else if (scopeNode is Block) {
      // Handle a raw block of code (uncommon but supported)
      buildBody = scopeNode.statements
          .map(
            (s) =>
                '    ${Skeletonizer.skeletonize(s, result, rewriter: rewriter)}',
          )
          .join('\n');
      scopeNode.accept(extractor);
    } else if (scopeNode is FunctionExpression) {
      // Handle builder functions such as `BlocBuilder(builder: (context, state) => …)`.
      final body = scopeNode.body;
      if (body is BlockFunctionBody) {
        buildBody = body.block.statements
            .map(
              (s) =>
                  '    ${Skeletonizer.skeletonize(s, result, rewriter: rewriter)}',
            )
            .join('\n');
      } else if (body is ExpressionFunctionBody) {
        buildBody =
            '    return ${Skeletonizer.skeletonize(body.expression, result, rewriter: rewriter)};';
      } else {
        buildBody =
            '    ${Skeletonizer.skeletonize(body, result, rewriter: rewriter)}';
      }

      if (scopeNode.parameters != null) {
        for (final param in scopeNode.parameters!.parameters) {
          final name = _getParamName(param);
          if (name != null && name != 'context') {
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

    paramFields = liftedFields
        .map((f) => '    late ${f.type} ${f.name};')
        .join('\n');

    // Recursively resolve cross-file references found by the visitor
    final pending = List<CrossFileRef>.from(extractor.crossFileRefs);

    // Stands a reference in rather than carrying it, for whichever reason the
    // caller found. Repo-local references ask for the whole declared surface,
    // having never seen which members the scope reads; third-party ones ask for
    // the member they reached, since rendering everything is what
    // `ShimEmitter._fullSurfaceLimit` exists to prevent.
    void standIn(CrossFileRef ref) => shims.request(
      ref.element,
      member: ref.member,
      allMembers: ref.fullSurface,
    );

    while (pending.isNotEmpty) {
      final ref = pending.removeAt(0);

      // Guarded, because a third-party reference sends this at a file in the
      // pub cache rather than in the project. That resolves, but it is the
      // analyzer answering about a file outside the context root, and a throw
      // here would otherwise escape into the handler in [extract] and lose the
      // whole scope over one unreadable dependency.
      Object? unitResult;
      try {
        unitResult = await session.getResolvedUnit(ref.filePath);
      } catch (_) {}
      if (unitResult is! ResolvedUnitResult) {
        // The file did not resolve, so nothing can be read out of it. Standing
        // the name in keeps the reference from dangling, which is the whole
        // difference between a smaller row and a wrong one.
        standIn(ref);
        continue;
      }
      visitedUnits.add(unitResult.unit);

      bool matched = false;
      for (final decl in unitResult.unit.declarations) {
        if (declaredNames(decl).contains(ref.name)) {
          // A declaration is inlined whole when it can contribute to the
          // build tree, and shimmed when it cannot:
          //  - EnumDeclaration                    → inline + recurse
          //  - widget ClassDeclaration            → inline + recurse
          //  - class declaring a UI-returning
          //    member such as `Widget buildRow()`  -> inline + recurse
          //  - UI-returning FunctionDeclaration   → inline + recurse
          //  - everything else (models, services,
          //    constants)                         → declaration-only shim
          //
          // The middle case is the one the widget filter alone gets wrong.
          // `tree_extractor` walks the body of every widget-returning helper it
          // sees, so a class that is not itself a widget but hands one out,
          // `AppStyles.buildDivider()` being the recurring shape, contributes
          // widgets to the metrics. Shimming it away reports zero where
          // analyzing the original project counted a subtree, which is a wrong
          // number rather than a missing file.
          final bool isWidget =
              decl is ClassDeclaration && isUiClassDeclaration(decl);
          final bool declaresUi =
              decl is ClassDeclaration && !isWidget && declaresUiMember(decl);
          final bool isWidgetFn =
              decl is FunctionDeclaration && returnsUi(decl);

          if (decl is EnumDeclaration || isWidget || declaresUi || isWidgetFn) {
            final source = Skeletonizer.skeletonize(decl, unitResult);

            // Repo-local inlining is free of the budget: its closure is bounded
            // by the repository, and capping it would change behaviour this
            // work never set out to change. Third-party inlining has no such
            // bound, so it pays, and once the budget is spent the declaration
            // takes the stand-in branch it would have taken before.
            if (!ref.fullSurface && !budget.take(source.length)) {
              standIn(ref);
              matched = true;
              break;
            }

            extractor.classCode += '\n$source\n';
            emittedNames.addAll(declaredNames(decl));

            // For StatefulWidgets, pull in the companion State class.
            final ClassDeclaration? widgetDecl =
                decl is ClassDeclaration && isWidget ? decl : null;
            final companions =
                widgetDecl != null && isStatefulWidgetDeclaration(widgetDecl)
                ? _includeCompanionState(
                    widgetDecl,
                    unitResult,
                    extractor,
                    processedKeys,
                    budget: ref.fullSurface ? null : budget,
                  )
                : const <ClassDeclaration>[];

            // Recurse: visit this declaration and feed its cross-file refs
            // back into pending. The same widget/enum gate applies at the
            // next iteration, so non-widget deps are still skipped.
            final sub = DependencyExtractorVisitor(
              unitResult,
              widgetDecl,
              processedKeys,
              imports,
              session: session,
              shims: shims,
              synthetics: synthetics,
              emittedNames: emittedNames,
              inlineThirdParty: inlineThirdParty,
              budget: budget,
              flutterNames: flutterNames,
            );
            decl.accept(sub);
            pending.addAll(sub.crossFileRefs);

            // The companion `State` is visited under its OWN class, not under
            // the widget's: a reference to one of its own methods has to read
            // as a member of the class that declares it, or `_extractSameFile`
            // searches the wrong class, finds nothing, and stands in for a type
            // the file already inlines. `memberCode` is discarded for the same
            // reason it is on the widget above -- those members are already in
            // the skeletonised class, and hoisting them redeclares them.
            for (final companion in companions) {
              final companionSub = DependencyExtractorVisitor(
                unitResult,
                companion,
                processedKeys,
                imports,
                session: session,
                shims: shims,
                synthetics: synthetics,
                emittedNames: emittedNames,
                inlineThirdParty: inlineThirdParty,
                budget: budget,
                flutterNames: flutterNames,
              );
              companion.accept(companionSub);
              pending.addAll(companionSub.crossFileRefs);
              extractor.classCode += companionSub.classCode;
            }

            // Whatever the sub-visitor resolved *within its own file* has to
            // come across too. Taking only `crossFileRefs` discarded it, and
            // the base class of an inlined widget is the case that hurts:
            // `isUiClassDeclaration` admits `class ExternalCard extends _BaseCard`
            // because the resolved chain reaches `StatelessWidget`, but
            // `_BaseCard` lives beside it and was dropped, so the emitted file
            // says `extends_non_class` and the chain is gone. A widget whose
            // supertype no longer resolves is not merely an error: it stops
            // being a widget, so `BuildMetricsVisitor` counts it as a value
            // object and never walks its build tree.
            //
            // `memberCode` is deliberately not merged: it holds members of
            // `widgetDecl`, which the skeletonised `decl` above already
            // carries, and hoisting them would redeclare them at top level.
            //
            // `_extractSameFile` applies no widget filter, so this inlines
            // same-file dependencies whole. That is the intended rule, not an
            // oversight: within a file take everything, across files take only
            // what can build UI and shim the rest. The closure crosses a file
            // boundary only through the gate below, so the ungated part stays
            // bounded to one file at a time.
            extractor.classCode += sub.classCode;
          } else if (ref.fullSurface) {
            // Not reachable as UI, so a stand-in cannot move a widget count:
            // the inline gate above has already established that neither the
            // declaration nor any member of it produces a widget.
            _requestShims(decl, shims);
          } else {
            // A third-party reference the element model called UI-producing and
            // the AST gate then refused. Rare, and the member-scoped stand-in is
            // the right size for it either way.
            standIn(ref);
          }
          matched = true;
          break;
        }
      }

      // No declaration in the resolved unit carries the name. A `part` file is
      // the usual reason: the reference resolves to the library, and the
      // declaration lives in a unit the loop never opened.
      if (!matched) standIn(ref);
    }

    final fullClassCode = extractor.classCode;

    // Scan all collected code for `prefix.` patterns so that imports with an
    // `as X` alias are included even when the package wasn't resolved by the
    // analyzer (unresolved imports give a null element, bypassing normal
    // detection).
    //
    // Every unit the transplant copied code from is scanned, not only the
    // origin. A declaration inlined from another file keeps that file's
    // prefixes, and its directives live nowhere else.
    final allCode =
        buildBody +
        extractor.memberCode +
        fullClassCode +
        paramFields +
        widgetFields;
    for (final unit in visitedUnits) {
      for (final directive in unit.directives) {
        if (directive is! ImportDirective) continue;
        final prefix = directive.prefix?.name;
        if (prefix == null || !allCode.contains('$prefix.')) continue;
        // Apply the same SDK-only filter used in the visitor: prefix-aliased
        // imports from third-party packages are excluded.
        final uriValue = directive.uri.stringValue;
        if (uriValue == null || !isSdkLibrary(uriValue)) continue;
        imports.addDirective(directive);
      }
    }

    final initState = _buildInitState(
      liftedFields,
      liftedGlobals,
      extractor.memberCode,
    );

    // Seeds are declared before the shims are rendered, so a captured global
    // that the emitter also saw is declared once, by the seed builder.
    final seedDeclarations = _buildSeedDeclarations(
      lifted: liftedFields,
      globals: liftedGlobals,
      declared: emittedNames,
    );
    final shimDeclarations = shims.render();

    // Synthesised last, so anything the file already declares by inlining, by
    // seeding or by shimming wins over a stand-in rebuilt from syntax.
    final syntheticDeclarations = synthetics.render(
      reserved: shims.shimmedNames,
    );

    // Generate the final self-contained file
    final source =
        '''
${imports.render()}

class GeneratedWidget extends StatefulWidget {
$widgetFields
$widgetConstructor

  @override
  State<GeneratedWidget> createState() => _GeneratedWidgetState();
}

class _GeneratedWidgetState extends State<GeneratedWidget> {
$paramFields
$initState
${extractor.memberCode}

  @override
  Widget build(BuildContext context) {
$buildBody
  }
}

$fullClassCode
$seedDeclarations$shimDeclarations$syntheticDeclarations''';

    return TransplantResult(
      source: source,
      inlinedThirdPartyDeclarations: budget.inlinedDeclarations,
      truncated: budget.exhausted,
    );
  }

  /// Declares the symbols the transplant's own seeding convention invents.
  ///
  /// [_buildInitState] assigns each lifted binding from a `fixture<Name>`
  /// symbol and each captured global from a `<name>Value` one, but nothing
  /// declared them: the convention assumed someone would write the
  /// declarations alongside the output by hand. An undeclared seed is an
  /// error-severity diagnostic, and `spm analyze` skips any file that carries
  /// one, so the convention as it stood made the isolated file unreadable by
  /// the very tool it exists to feed.
  ///
  /// Each seed is declared `late` and left unassigned, for the same reason the
  /// lifted fields are: a fabricated default would be measured as though it
  /// were the real value, where an unset `late` throws on read. Nothing here
  /// can move a feature count: a top-level variable is not a widget, and the
  /// generated `build` never reads one except through the field it seeds.
  ///
  /// The captured global itself is declared too when [declared] does not
  /// already carry it, since `initState` assigns to it.
  ///
  /// [declared] is both read and written: every name emitted here is added to
  /// it, so the shim emitter that renders next does not declare it a second
  /// time.
  String _buildSeedDeclarations({
    required List<CapturedVariable> lifted,
    required List<CapturedVariable> globals,
    required Set<String> declared,
  }) {
    // Insertion-ordered so the output stays byte-identical between runs.
    final declarations = <String, String>{};

    void declare(String name, String type) {
      if (declared.contains(name)) return;
      declarations.putIfAbsent(name, () => 'late $type $name;');
    }

    for (final g in globals) {
      declare(g.name, g.type);
      declare('${g.name}Value', g.type);
    }
    for (final f in lifted) {
      declare(_fixtureNameFor(f.name), f.type);
    }

    if (declarations.isEmpty) return '';
    declared.addAll(declarations.keys);
    return '''

// Seeds for the bindings the transplanted scope used to receive from the app.
// Left unassigned on purpose: reading one throws rather than quietly standing
// in for the value that was really there.
${declarations.values.join('\n')}
''';
  }

  /// Emits an `initState` that seeds every lifted field from a named fixture.
  ///
  /// The transplanted scope no longer receives its inputs from the surrounding
  /// app, so each lifted field needs a value. Rather than invent one, this
  /// emits a reference to a conventionally named symbol, so field `wallets`
  /// becomes `wallets = fixtureWallets;`, which the caller then defines
  /// alongside the isolated file. The convention makes the required symbol
  /// names predictable instead of leaving them to be rediscovered per scope.
  ///
  /// Returns an empty string when nothing was lifted, or when the transplanted
  /// class already brought its own `initState` in [memberCode], since
  /// overwriting a real one would discard setup the scope depends on.
  String _buildInitState(
    List<CapturedVariable> lifted,
    List<CapturedVariable> globals,
    String memberCode,
  ) {
    if (lifted.isEmpty && globals.isEmpty) return '';
    if (RegExp(r'\bvoid\s+initState\s*\(').hasMatch(memberCode)) return '';

    final assignments = [
      // Globals first: a field initialiser may read one.
      ...globals.map((g) => '    ${g.name} = ${g.name}Value;'),
      ...lifted.map((f) => '    ${f.name} = ${_fixtureNameFor(f.name)};'),
    ].join('\n');

    return '''

  @override
  void initState() {
    super.initState();
$assignments
  }
''';
  }

  /// `wallets` -> `fixtureWallets`, `_controller` -> `fixtureController`.
  String _fixtureNameFor(String field) {
    final bare = field.replaceFirst(RegExp(r'^_+'), '');
    if (bare.isEmpty) return 'fixture';
    return 'fixture${bare[0].toUpperCase()}${bare.substring(1)}';
  }

  /// Drops a type's outer nullability so it can back a `late` field.
  ///
  /// Only the trailing `?` is removed. Stripping every `?` in the string would
  /// rewrite the type's interior: `(Wallet?, Wallet?)` became
  /// `(Wallet, Wallet)` and `Map<String, int?>` became `Map<String, int>`,
  /// neither of which is the declared type.
  String _nonNullable(String type) =>
      type.endsWith('?') ? type.substring(0, type.length - 1) : type;

  /// The parameters of [scopeNode] that become fields on the generated State.
  ///
  /// A transplanted scope no longer gets called with arguments, so whatever it
  /// declared as a parameter has to live on the State instead. `context` is the
  /// exception, since `State` already provides one.
  List<CapturedVariable> _liftedParameters(
    AstNode scopeNode,
    IsolationMatch match,
  ) {
    final lifted = <CapturedVariable>[];

    void add(FormalParameter param, String type) {
      final name = _getParamName(param);
      if (name == null || name == 'context') return;
      lifted.add(CapturedVariable(name, type, lifted.length));
    }

    if (scopeNode is ClassDeclaration) {
      final buildMethod = findBuildMethod(scopeNode);
      for (final param in buildMethod?.parameters?.parameters ?? const []) {
        add(param, _getParamType(param));
      }
    } else if (scopeNode is FunctionExpression) {
      for (final param in scopeNode.parameters?.parameters ?? const []) {
        add(param, _getParamType(param, scopeNode, match.type));
      }
    }

    return lifted;
  }

  /// Extracts the name of a formal parameter.
  String? _getParamName(FormalParameter param) {
    if (param is RegularFormalParameter) return param.name?.lexeme;
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
            return _nonNullable(typeStr);
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
              return _nonNullable(typeStr);
            }
          }
        }
      } catch (_) {}

      // Step 3: walk up to a generic widget such as `BlocBuilder` or
      // `Consumer` and extract the state/model type from its type arguments.
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
              return _nonNullable(args[1].trim());
            } else if (typeName.contains('Consumer') && args.isNotEmpty) {
              return _nonNullable(args[0].trim());
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

/// Asks [shims] for a stand-in covering every name [decl] declares.
///
/// The whole declared surface is requested, unlike the third-party path: this
/// call site knows only that a declaration was reached, never which of its
/// members the scope reads. Repo-local declarations are small enough for that
/// to be the cheaper answer than threading member references back here.
///
/// A `TopLevelVariableDeclaration` is the one node that can declare several
/// names, and each carries its own element, so it is walked rather than
/// reduced to one.
void _requestShims(CompilationUnitMember decl, ShimEmitter shims) {
  if (decl is TopLevelVariableDeclaration) {
    for (final variable in decl.variables.variables) {
      final element = variable.declaredFragment?.element;
      if (element != null) shims.request(element, allMembers: true);
    }
    return;
  }
  try {
    final element = (decl as dynamic).declaredFragment?.element as Element?;
    if (element != null) shims.request(element, allMembers: true);
  } catch (_) {
    // A declaration kind without a fragment cannot be shimmed; it degrades to
    // the dangling reference it already was.
  }
}

/// Finds and appends the companion `State` subclass for [widgetDecl] by
/// scanning all declarations in [unitResult] for a class whose extends clause
/// matches `State<WidgetName>`.
///
/// Returns what it inlined, because a `State` body is where a StatefulWidget
/// keeps everything the dependency crawl needs to see. Appending it without
/// visiting it left every reference inside it invisible: no shim, no import, no
/// cross-file reference. A charting widget is the shape that shows it: the data
/// types it plots are named only inside the `State`, so the transplant carried
/// the code that names them and no declaration for any of them. The caller
/// visits what comes back.
/// [budget] is charged for a third-party companion and null for a repo-local
/// one. The charge is recorded but not enforced: the widget it belongs to has
/// already been admitted, and a `StatefulWidget` whose `State` was dropped
/// half-way names a type nothing declares, which is a broken file rather than a
/// smaller one.
List<ClassDeclaration> _includeCompanionState(
  ClassDeclaration widgetDecl,
  ResolvedUnitResult unitResult,
  DependencyExtractorVisitor extractor,
  Set<String> processedKeys, {
  InlineBudget? budget,
}) {
  final widgetName = widgetDecl.namePart.typeName.lexeme;
  final companions = <ClassDeclaration>[];
  for (final other in unitResult.unit.declarations) {
    if (other is! ClassDeclaration) continue;
    final superSrc = other.extendsClause?.superclass.toSource() ?? '';
    if (superSrc == 'State<$widgetName>' ||
        superSrc.contains('State<$widgetName>')) {
      final key = '${unitResult.path}::${other.namePart.typeName.lexeme}';
      if (processedKeys.add(key)) {
        final source = Skeletonizer.skeletonize(other, unitResult);
        budget?.take(source.length);
        extractor.classCode += '\n$source\n';
        extractor.emittedNames.add(other.namePart.typeName.lexeme);
        companions.add(other);
      }
    }
  }
  return companions;
}
