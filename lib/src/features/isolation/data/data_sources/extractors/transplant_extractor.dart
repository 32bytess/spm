import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/core/rebuild_path.dart';
import 'package:spm/src/features/analysis/data/data_sources/extensions/state_class_detector.dart';
import 'package:spm/src/features/isolation/data/data_sources/emitters/import_collector.dart';
import 'package:spm/src/features/isolation/data/data_sources/emitters/shim_emitter.dart';
import 'package:spm/src/features/isolation/data/data_sources/emitters/stub_emitter.dart';
import 'package:spm/src/features/isolation/data/data_sources/emitters/synthetic_shim_emitter.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/declaration_names.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/default_values.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/flutter_namespace.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/inline_budget.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/sdk_uris.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/skeletonizer.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/ui_surface.dart';
import 'package:spm/src/features/isolation/data/data_sources/sets/isolation_match_set.dart';
import 'package:spm/src/features/isolation/data/data_sources/visitors/captured_variable_visitor.dart';
import 'package:spm/src/features/isolation/data/data_sources/visitors/dependency_extractor_visitor.dart';
import 'package:spm/src/features/isolation/data/data_sources/visitors/namespace_renamer.dart';
import 'package:spm/src/features/isolation/data/data_sources/visitors/non_rebuild_body_eraser.dart';
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
    this.unseededBindings = const [],
    this.hasFixtureConstructor = false,
    this.droppedLoadingBuilders = 0,
    this.carriedUiDeclarations = const [],
    this.renamedThirdPartyDeclarations = const [],
    this.erasedNonRebuildBodies = 0,
    this.droppedUnreachableMembers = const [],
  });

  /// The generated Dart file.
  final String source;

  /// How many third-party declarations were carried into it.
  final int inlinedThirdPartyDeclarations;

  /// Whether the inline budget ran out, so some third-party UI was stood in for
  /// that would otherwise have been carried.
  final bool truncated;

  /// Bindings left unassigned because no value of their type could be built.
  ///
  /// Reading one throws before the first frame, so a file with any of these
  /// does not mount. Named rather than counted, since the name is what a human
  /// filling in the fixture block needs.
  final List<String> unseededBindings;

  /// Whether the file declares `GeneratedWidget.fixture()`.
  ///
  /// False when the scope's widget required a field nothing here could build.
  /// Mounting such a file means constructing that value first, which is a
  /// second fix point outside the fixture block and different for every scope.
  final bool hasFixtureConstructor;

  /// How many `loadingBuilder` arguments the image rewrite had to drop.
  ///
  /// `Image.asset` has no such argument, so this is the one part of an image
  /// construction that still cannot come across. Counted rather than lost, and
  /// the file itself carries a marker comment where each one stood.
  final int droppedLoadingBuilders;

  /// The UI-producing declarations carried into the file, as `libraryUri#Name`.
  ///
  /// One half of the symmetry check the third-party goal reduces to: for every
  /// declaration `spm analyze` walks in place, `spm isolate` has to carry the
  /// source. The other half is the analyze row's own list of walked classes.
  final List<String> carriedUiDeclarations;

  /// How many closure bodies were emptied because a rebuild cannot run them.
  ///
  /// `spm analyze` never walked them, so no feature moves. What changes is the
  /// file: the names they used are gone, and so are the declarations the crawl
  /// carried on their behalf.
  final int erasedNonRebuildBodies;

  /// Members of the scope's own class dropped as unreachable from the rebuild.
  ///
  /// Named rather than counted, because a member missing from the output that
  /// should not be is the failure mode of the prune, and a count cannot say
  /// which one.
  final List<String> droppedUnreachableMembers;

  /// Third-party names carried under a mangled name because
  /// `package:flutter/material.dart` exports the same one.
  ///
  /// The declaration and its tree come across; what changes is the name, so the
  /// output no longer matches `git show` byte for byte at those points. Said out
  /// loud because the fidelity audit measures exactly that.
  final List<String> renamedThirdPartyDeclarations;
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
    : _newBudget = newBudget;

  final InlineBudget Function()? _newBudget;

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
  /// [inlineMaxDeclarations] and [inlineMaxCharacters] bound that carrying.
  /// [pruneNonRebuild]: whether code a rebuild cannot run is left out of the
  /// output, which is what `spm analyze` already does before it counts
  /// anything. False reproduces the output as it was before the prune existed.
  Future<TransplantResult> extract(
    IsolationMatch match,
    ResolvedUnitResult result,
    AnalysisSession session, {
    bool inlineThirdParty = true,
    int inlineMaxDeclarations = InlineBudget.defaultMaxDeclarations,
    int inlineMaxCharacters = InlineBudget.defaultMaxCharacters,
    bool pruneNonRebuild = true,
  }) async {
    try {
      return await _extract(
        match,
        result,
        session,
        inlineThirdParty: inlineThirdParty,
        inlineMaxDeclarations: inlineMaxDeclarations,
        inlineMaxCharacters: inlineMaxCharacters,
        pruneNonRebuild: pruneNonRebuild,
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
    required int inlineMaxDeclarations,
    required int inlineMaxCharacters,
    required bool pruneNonRebuild,
  }) async {
    // Every UI-producing declaration this scope carried, as `libraryUri#Name`.
    final carriedUiDeclarations = <String>{};
    // Members of the scope's own class left out as unreachable from a rebuild.
    final droppedMembers = <String>[];
    // Every binding the scope's build depends on, seeded from the fixture
    // block: the fields the dropped members used to assign, and the scope's own
    // fields hoisted out of the class.
    // Keyed by field name, because a field can arrive here twice: once because
    // a dropped member assigned it, and again when the field itself is hoisted.
    // The hoisted entry wins, since it reads the type off the declaration.
    final fixtureSeededFields = <String, CapturedVariable>{};
    // Seed name -> the expression it starts from, where the field carried one.
    // Absent means `DefaultValues` supplies it.
    final fixtureValues = <String, String>{};
    // Fields the dropped constructor used to initialise and nothing here can.
    final unseededFields = <String>[];
    final budget =
        _newBudget?.call() ??
        InlineBudget(
          maxDeclarations: inlineMaxDeclarations,
          maxCharacters: inlineMaxCharacters,
        );
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
      // Lifting has to see the source as it will be written. A name captured
      // only by a body the eraser empties would otherwise become a `late` field
      // seeded in the generated `initState` for code no longer in the file.
      skipNonRebuildCallbacks: pruneNonRebuild,
    );
    scopeNode.accept(capture);
    liftedFields.addAll(capture.captured);
    final liftedGlobals = capture.capturedGlobals;

    // Lifting a promoted parameter onto a field costs it its promotion, so the
    // casts the original code did not need have to be written back in.
    final rewriter = PromotionCastRewriter({
      for (final f in liftedFields) f.name: f.type,
    });
    final projectRoot = result.session.analysisContext.contextRoot.root.path;
    final renamer = NamespaceRenamer(
      flutterNames,
      isLocal: (path) =>
          p.isWithin(projectRoot, path) || p.equals(projectRoot, path),
    );
    final eraser = NonRebuildBodyEraser();
    final rewriters = <SourceRewriter>[
      rewriter,
      renamer,
      if (pruneNonRebuild) eraser,
    ];
    // Source carried in from another declaration gets the eraser and nothing
    // else. It has to get the eraser, because the crawl is gated inside it too,
    // and a gate without an erasure leaves the names it skipped with nothing to
    // resolve against. It must not get the other two: `PromotionCastRewriter`
    // is keyed to this scope's lifted bindings, and a carried declaration that
    // happens to use one of those names is not the same binding.
    final carriedRewriters = <SourceRewriter>[if (pruneNonRebuild) eraser];

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
    // One per file, so `_Stub` is declared once no matter which emitter first
    // needed a value.
    // Shares the name set, so a generated value never writes a type argument
    // the file does not declare.
    final defaults = DefaultValues(nameable: emittedNames);
    // Renames any third-party declaration whose name material also exports, and
    // every reference that resolves to it. Shared with the dependency visitor,
    // so a declaration carried there is renamed the same way the body that uses
    // it is.
    final shims = ShimEmitter(emittedNames, defaults);
    final synthetics = SyntheticShimEmitter(emittedNames, defaults);

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
      defaults: defaults,
      rewriters: rewriters,
      pruneNonRebuild: pruneNonRebuild,
    );

    // Types the transplant writes down but the copied source may never mention.
    // A lifted binding is emitted as `late List<EncryptLevel> encryptLevels;`,
    // and before the prune the crawl reached `EncryptLevel` by accident,
    // through some other mention in the copied source. A handler body was often
    // the only such mention, so the type now has to be asked for outright.
    for (final element in capture.typeElements) {
      extractor.handleTypeElement(element);
    }

    String widgetFields = '';
    String widgetConstructor = '  const GeneratedWidget({super.key});';
    // The widget's own fields, kept alongside the rendered source so the
    // fixture constructor below can default each one.
    final widgetFieldSpecs =
        <({String name, String type, DartType? resolved})>[];

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
                // A `late` field cannot appear in an initialiser list, and one
                // that already has a value needs nothing.
                if (field.fields.isLate || v.initializer != null) continue;
                if (field.isStatic) continue;
                widgetFieldSpecs.add((
                  name: v.name.lexeme,
                  type: field.fields.type?.toSource() ?? 'dynamic',
                  resolved: _fieldType(v),
                ));
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
                    '    ${Skeletonizer.skeletonize(s, result, rewriters: rewriters)}',
              )
              .join('\n');
        } else if (body is ExpressionFunctionBody) {
          buildBody =
              '    return ${Skeletonizer.skeletonize(body.expression, result, rewriters: rewriters)};';
        } else {
          buildBody =
              '    ${Skeletonizer.skeletonize(body, result, rewriters: rewriters)}';
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
      // those fields unassigned, so they are given a value below, or marked
      // `late` when no value of their type can be built.
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

      // Which members the timed rebuild can actually reach. Null keeps every
      // one of them, which is what the command did before the prune existed.
      final reachable = pruneNonRebuild
          ? _reachableMemberNames(scopeNode)
          : null;

      // Whatever those dropped members were seeding has to come from somewhere,
      // and the fixture block is already where a transplanted scope gets the
      // values the application used to hand it.
      if (reachable != null) {
        for (final seed in _fieldsSeededByDroppedMembers(
          scopeNode,
          reachable.whole,
        )) {
          fixtureSeededFields[seed.name] = seed;
        }
      }

      // Extract all members of the original class (methods, fields, getters)
      for (final member in (scopeNode.body as BlockClassBody).members) {
        if (member is MethodDeclaration && member.name.lexeme == 'build') {
          continue;
        }
        if (member is MethodDeclaration &&
            reachable != null &&
            !reachable.whole.contains(member.name.lexeme)) {
          // Not written out whole, and the body is not traversed either. The
          // traversal is where the cost was: a handler that pushes a route made
          // the crawl carry the whole target screen, and a service it called
          // became a stand-in whose signature then failed to type-check against
          // the call site.
          droppedMembers.add(member.name.lexeme);
          if (reachable.signatureOnly.contains(member.name.lexeme)) {
            extractor.memberCode +=
                '\n${_signatureOnly(member, result, rewriters)}\n';
            // The signature still names types, and those have to resolve.
            member.returnType?.accept(extractor);
            member.typeParameters?.accept(extractor);
            member.parameters?.accept(extractor);
          }
          continue;
        }
        if (member is ConstructorDeclaration) {
          // Still traversed: default values and initialiser expressions can
          // reference declarations the isolated file needs.
          member.accept(extractor);
          continue;
        }
        if (member is FieldDeclaration && pruneNonRebuild) {
          final hoisted = _hoistFieldToFixture(member, result, rewriters);
          if (hoisted != null) {
            extractor.memberCode += '\n${hoisted.source}\n';
            for (final seed in hoisted.seeds) {
              fixtureSeededFields[seed.name] = seed;
            }
            fixtureValues.addAll(hoisted.values);
            // Still traversed: the declared type, and whatever the initialiser
            // that moved to the top level names, both have to resolve.
            member.accept(extractor);
            continue;
          }
        }
        var source = Skeletonizer.skeletonize(
          member,
          result,
          rewriters: rewriters,
        );
        if (member is FieldDeclaration &&
            !member.isStatic &&
            member.fields.lateKeyword == null &&
            member.fields.variables.any(
              (v) =>
                  v.initializer == null &&
                  ctorInitialisedFields.contains(v.name.lexeme) &&
                  // A field the fixture block seeds is assigned in the generated
                  // `initState`, so an inline default here would be a second
                  // answer to the same question and the one nobody can edit.
                  !fixtureSeededFields.containsKey(v.name.lexeme),
            )) {
          // A value beats `late`, because `late` here is a
          // `LateInitializationError` on the first read and the read is in
          // `build`. Only when nothing of the field's type can be built does
          // the throw stay, and then the name is reported.
          final defaulted = _defaultedFieldSource(source, member, defaults);
          if (defaulted != null) {
            source = defaulted;
          } else {
            source = 'late $source';
            unseededFields.addAll(
              member.fields.variables
                  .where(
                    (v) =>
                        v.initializer == null &&
                        ctorInitialisedFields.contains(v.name.lexeme),
                  )
                  .map((v) => v.name.lexeme),
            );
          }
        }
        extractor.memberCode += '\n$source\n';
        member.accept(extractor);
      }
    } else if (scopeNode is Block) {
      // Handle a raw block of code (uncommon but supported)
      buildBody = scopeNode.statements
          .map(
            (s) =>
                '    ${Skeletonizer.skeletonize(s, result, rewriters: rewriters)}',
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
                  '    ${Skeletonizer.skeletonize(s, result, rewriters: rewriters)}',
            )
            .join('\n');
      } else if (body is ExpressionFunctionBody) {
        buildBody =
            '    return ${Skeletonizer.skeletonize(body.expression, result, rewriters: rewriters)};';
      } else {
        buildBody =
            '    ${Skeletonizer.skeletonize(body, result, rewriters: rewriters)}';
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
            final source = Skeletonizer.skeletonize(
              decl,
              unitResult,
              rewriters: carriedRewriters,
            );
            // Recorded so the symmetry between the two commands can be checked
            // rather than asserted: for every declaration `spm analyze` walks
            // in place, `spm isolate` has to carry the source. The driver diffs
            // this set against the classes the analyze row reports walking, and
            // a non-empty diff names the subtree that went missing.
            for (final declared in declaredNames(decl)) {
              carriedUiDeclarations.add(
                '${unitResult.libraryElement.identifier}#$declared',
              );
            }
            registerInlinedDeclaration(decl, defaults);

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
                    rewriters: carriedRewriters,
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
              defaults: defaults,
              rewriters: rewriters,
              pruneNonRebuild: pruneNonRebuild,
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
                defaults: defaults,
                rewriters: rewriters,
                pruneNonRebuild: pruneNonRebuild,
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
        final uriValue = directive.uri.stringValue;
        if (uriValue != null && isSdkLibrary(uriValue)) {
          imports.addDirective(directive);
          continue;
        }
        // A third-party prefix cannot be restored as an import. The output is
        // analysed and compiled against a package config that supplies
        // `package:flutter` and nothing else, so restoring
        // `import 'package:some_package/some_package.dart' as helper;` would be
        // `uri_does_not_exist`: still error-severity, still skipped by
        // `spm analyze`, and it would spend the one clear result that no file
        // in the output reports an unresolved import.
        //
        // A `dynamic` receiver makes `helper.join(...)` compile with no import
        // at all, which is what every other unresolved third-party name in the
        // output already does. `render(reserved:)` guards the name against
        // something the file declares.
        synthetics.requestGlobal(prefix);
      }
    }

    final initState = _buildInitState(
      liftedFields,
      liftedGlobals,
      extractor.memberCode,
      seededFields: fixtureSeededFields.values.toList(),
    );

    // The cross-file loop has finished, so the set of names this file inlines
    // has stopped growing and the shim emitter can say which of its own
    // declarations supply a value. Seeds are built next and read those answers.
    shims.publishDefaults();

    // Seeds are declared before the shims are rendered, so a captured global
    // that the emitter also saw is declared once, by the seed builder.
    final seeds = _buildSeedDeclarations(
      lifted: [...liftedFields, ...fixtureSeededFields.values],
      globals: liftedGlobals,
      declared: emittedNames,
      defaults: defaults,
      values: fixtureValues,
    );
    final seedDeclarations = seeds.source;
    final fixtureConstructor = _buildFixtureConstructor(
      widgetFieldSpecs,
      defaults,
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
$fixtureConstructor
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
$seedDeclarations$shimDeclarations$syntheticDeclarations${defaults.usesStub ? renderStubClass() : ''}''';

    return TransplantResult(
      source: source,
      inlinedThirdPartyDeclarations: budget.inlinedDeclarations,
      truncated: budget.exhausted,
      unseededBindings: [...seeds.unseeded, ...unseededFields]..sort(),
      hasFixtureConstructor: fixtureConstructor.isNotEmpty,
      carriedUiDeclarations: carriedUiDeclarations.toList()..sort(),
      erasedNonRebuildBodies: eraser.erasedBodies,
      droppedUnreachableMembers: droppedMembers..sort(),
      renamedThirdPartyDeclarations: renamer.renamed.toList()..sort(),
      droppedLoadingBuilders: Skeletonizer.droppedLoadingBuilder
          .allMatches(source)
          .length,
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
  /// Each seed carries a value of its own type wherever one can be built.
  ///
  /// These used to be declared `late` and left unassigned, on the argument that
  /// a fabricated default could be mistaken for the real value. The argument
  /// holds for types and not for values: [_buildInitState] reads every one of
  /// these from `initState`, so an unassigned `late` is a
  /// `LateInitializationError` before the first frame, for every scope that
  /// lifted a captured binding. A value is never measured, because the features
  /// come from the shape of the build tree and that shape is fixed before any
  /// of this executes.
  ///
  /// A binding whose type nothing here can build keeps the old `late` form and
  /// its name is returned in `unseeded`, so a file that still cannot mount says
  /// which binding stopped it rather than failing anonymously.
  ///
  /// The captured global itself is declared too when [declared] does not
  /// already carry it, since `initState` assigns to it.
  ///
  /// [declared] is both read and written: every name emitted here is added to
  /// it, so the shim emitter that renders next does not declare it a second
  /// time.
  ({String source, List<String> unseeded}) _buildSeedDeclarations({
    required List<CapturedVariable> lifted,
    required List<CapturedVariable> globals,
    required Set<String> declared,
    required DefaultValues defaults,
    Map<String, String> values = const {},
  }) {
    // Insertion-ordered so the output stays byte-identical between runs.
    final declarations = <String, String>{};
    final unseeded = <String>[];

    void declare(String name, String type) {
      if (declared.contains(name)) return;
      // A field that carried its own value keeps it: the value moves to the
      // top level rather than being replaced by a default. That is the whole
      // difference between relocating the scope's initial state and discarding
      // it, and a `ListView` seeded with twenty rows still builds twenty.
      final carried = values[name];
      if (carried != null) {
        declarations.putIfAbsent(name, () => '$type $name = $carried;');
        return;
      }
      // The declared type is not widened here. These seeds are assigned into
      // fields declared with the original type, so a nullable seed would not
      // assign and a stub in a typed slot would throw where the old `late`
      // threw. Where no value fits, the old form is kept and reported.
      final value = defaults.forType(type);
      if (value == null || value.nullableType) {
        declarations.putIfAbsent(name, () => 'late $type $name;');
        unseeded.add(name);
        return;
      }
      declarations.putIfAbsent(
        name,
        () => '$type $name = ${value.expression};',
      );
    }

    for (final g in globals) {
      declare(g.name, g.type);
      declare('${g.name}Value', g.type);
    }
    for (final f in lifted) {
      declare(_fixtureNameFor(f.name), f.type);
    }

    if (declarations.isEmpty) return (source: '', unseeded: const []);
    declared.addAll(declarations.keys);
    final source =
        '''

// Fixture block. These are the bindings the transplanted scope used to receive
// from the application, and this is the one region to edit when a real value is
// needed: nothing outside it has to change. Collections are generated empty, so
// a scope whose rows come from a lifted list builds none until one is filled in.
${declarations.values.join('\n')}
''';
    return (source: source, unseeded: unseeded);
  }

  /// [source] with a default appended to every variable that needs one.
  ///
  /// Returns null when any of them has a type nothing here can build, since a
  /// partly initialised declaration is still a `LateInitializationError` and a
  /// wrongly typed one is a `TypeError`.
  String? _defaultedFieldSource(
    String source,
    FieldDeclaration member,
    DefaultValues defaults,
  ) {
    final type = member.fields.type?.toSource();
    if (type == null) return null;
    final needing = member.fields.variables
        .where((v) => v.initializer == null)
        .toList();
    if (needing.isEmpty) return null;

    final value = defaults.forType(type);
    if (value == null || value.nullableType) return null;

    var out = source;
    for (final variable in needing) {
      final name = variable.name.lexeme;
      // The declarations are `name`, `name,` or `name;` in the copied source.
      final pattern = RegExp('\\b$name\\s*(?=[,;])');
      final match = pattern.firstMatch(out);
      if (match == null) return null;
      out = out.replaceRange(
        match.start,
        match.end,
        '$name = ${value.expression}',
      );
    }
    return out;
  }

  /// A constructor a caller can use without knowing the scope's fields.
  ///
  /// The copied constructor is the commit's own, so a scope whose widget
  /// declared `required this.arguments` emits
  /// `const GeneratedWidget({Key? key, required this.arguments})` and nothing
  /// can write `GeneratedWidget()`. Mounting it would mean knowing this scope's
  /// field names and types and building a value for each, which is a second fix
  /// point outside the fixture block and different for every scope.
  ///
  /// Returns an empty string when any field's type could not be built, rather
  /// than emitting a constructor that does not compile. The copied constructor
  /// always stays: it is part of the commit's source and the fidelity audit
  /// measures against it.
  String _buildFixtureConstructor(
    List<({String name, String type, DartType? resolved})> fields,
    DefaultValues defaults,
  ) {
    final initialisers = <String>[];
    for (final field in fields) {
      final value =
          defaults.forType(field.type) ??
          _constructionFor(field.resolved, defaults);
      if (value == null) return '';
      initialisers.add('${field.name} = ${value.expression}');
    }
    final list = initialisers.isEmpty ? '' : ' : ${initialisers.join(', ')}';
    return '\n  GeneratedWidget.fixture({super.key})$list;\n';
  }

  /// Builds [type] by calling its unnamed constructor, one level deep.
  ///
  /// The fields that stop [_buildFixtureConstructor] are almost always a small
  /// arguments or model class the transplant carried in whole, so its
  /// constructor is right there in the output. [depth] stops the walk before a
  /// self-referential model turns into an infinite expression.
  DefaultValue? _constructionFor(
    DartType? type,
    DefaultValues defaults, {
    int depth = 0,
  }) {
    if (type is! InterfaceType || depth > 1) return null;
    final name = type.element.name;
    if (name == null || name.isEmpty) return null;

    for (final ctor in type.element.constructors) {
      final ctorName = ctor.name;
      if (ctorName != null && ctorName.isNotEmpty && ctorName != 'new') {
        continue;
      }
      final arguments = <String>[];
      for (final parameter in ctor.formalParameters) {
        if (!parameter.isRequired) continue;
        final parameterName = parameter.name;
        if (parameterName == null) return null;
        final value =
            defaults.forType(parameter.type.getDisplayString()) ??
            _constructionFor(parameter.type, defaults, depth: depth + 1);
        if (value == null || value.nullableType) return null;
        arguments.add(
          parameter.isNamed
              ? '$parameterName: ${value.expression}'
              : value.expression,
        );
      }
      return DefaultValue('$name(${arguments.join(', ')})');
    }
    return null;
  }

  /// The entry point a timed rebuild reaches on its own.
  ///
  /// `build`, and nothing else. `initState` and `didChangeDependencies` were
  /// kept for a while because they seed the fields `build` reads, and dropping
  /// them turns a file that analyses clean into a `LateInitializationError`
  /// before the first frame. That was the right worry and the wrong fix: what
  /// those methods contribute is a *value*, and the transplant already knows
  /// how to supply one. The fields they seeded now come from the fixture block
  /// instead, so the seeding survives and the network calls, listener
  /// registrations and notification setup that sat beside it do not.
  static const Set<String> _rebuildEntryPoints = {'build'};

  /// Names of the class members a rebuild can reach, transitively.
  ///
  /// This is the same closure `TreeExtractor` walks when it counts: the scope
  /// body, then the helpers it calls, then the helpers those call. What falls
  /// outside it cannot move a feature, so carrying it buys nothing and costs
  /// the dependencies it drags in.
  ///
  /// Fields and constructors are always kept: they carry no bodies worth
  /// pruning, their initialisers may be exactly what `build` reads, and a
  /// dropped field would change the class rather than trim it. Whatever they
  /// name is therefore reachable too, and seeds the walk alongside the entry
  /// points.
  ///
  /// Matching is by name rather than by element. A helper reference that never
  /// resolved has no element to match on, and the scopes this runs over are the
  /// ones whose project did not resolve as often as not. Over-keeping a member
  /// because an unrelated local shares its name costs nothing; dropping one
  /// that `build` calls costs the file.
  static ({Set<String> whole, Set<String> signatureOnly}) _reachableMemberNames(
    ClassDeclaration cls,
  ) {
    final members = (cls.body as BlockClassBody).members;
    final methodsByName = <String, MethodDeclaration>{};
    for (final member in members) {
      if (member is MethodDeclaration) {
        methodsByName[member.name.lexeme] = member;
      }
    }

    final kept = <String>{};
    final tearOffs = <String>{};
    final pending = <AstNode>[];

    void seed(String name) {
      final method = methodsByName[name];
      if (method != null && kept.add(name)) pending.add(method);
    }

    for (final member in members) {
      if (member is FieldDeclaration || member is ConstructorDeclaration) {
        pending.add(member);
      }
    }
    for (final entryPoint in _rebuildEntryPoints) {
      seed(entryPoint);
    }

    while (pending.isNotEmpty) {
      final collector = _MemberReferenceCollector();
      pending.removeLast().accept(collector);
      tearOffs.addAll(collector.handlerNames);
      for (final name in collector.names) {
        seed(name);
      }
    }

    // A member the walk reached both ways keeps its body: a name is written out
    // once, and the reachable answer is the one that has to win.
    return (
      whole: kept,
      signatureOnly: tearOffs
          .where(
            (name) => methodsByName.containsKey(name) && !kept.contains(name),
          )
          .toSet(),
    );
  }

  /// Rewrites one field declaration as `late` bindings seeded from the fixture
  /// block.
  ///
  /// ```dart
  /// // was: int _limit = 20;
  /// late int _limit;                     // in the State
  /// _limit = fixtureLimit;               // in the generated initState
  /// int fixtureLimit = 20;               // at the top level of the file
  /// ```
  ///
  /// The point is a dependency surface that is uniform and in one place: every
  /// value the scope's build depends on is named, declared together, and can be
  /// lifted into a shared `dependencies.dart` without touching anything else.
  ///
  /// Returns null when the field must stay where it is, and the reasons are all
  /// about not changing what the metrics see:
  ///
  ///  * **`static` or `const`.** `treeConstWidgetCount` and
  ///    `rootBuildReturnsConstWidget` are features. A `static const _spec` used
  ///    inside a `const` constructor in `build` stops the call being const the
  ///    moment it becomes a variable, and two features move with it.
  ///  * **An initialiser that needs the instance**, `context.read<T>()`,
  ///    `widget.arguments`, anything reading another member. It cannot be
  ///    evaluated at the top level, and a `late` field with a lazy initialiser
  ///    is already the right shape for it.
  ///  * **No nameable type.** The fixture declaration has to write the type
  ///    down, and `var` alone does not give one.
  ///
  /// `final` is dropped rather than carried onto the `late` binding: a kept
  /// member may still assign the field, `_toggleA() => setState(() => _enabled
  /// = true)` being the recurring shape, and `late final` would make that a
  /// second assignment to a final.
  ({String source, List<CapturedVariable> seeds, Map<String, String> values})?
  _hoistFieldToFixture(
    FieldDeclaration member,
    ResolvedUnitResult result,
    List<SourceRewriter> rewriters,
  ) {
    if (member.isStatic || member.fields.isConst) return null;

    final declaredType = member.fields.type?.toSource();
    final lines = <String>[];
    final seeds = <CapturedVariable>[];
    final values = <String, String>{};

    for (final variable in member.fields.variables) {
      final type = declaredType ?? _fieldType(variable)?.getDisplayString();
      if (type == null || type.isEmpty || type == 'dynamic') return null;

      final initializer = variable.initializer;
      if (initializer != null) {
        if (_needsInstance(initializer)) return null;
        values[_fixtureNameFor(variable.name.lexeme)] =
            Skeletonizer.skeletonize(initializer, result, rewriters: rewriters);
      }

      lines.add('  late $type ${variable.name.lexeme};');
      seeds.add(CapturedVariable(variable.name.lexeme, type, seeds.length));
    }

    if (lines.isEmpty) return null;
    return (source: lines.join('\n'), seeds: seeds, values: values);
  }

  /// Whether [expression] can only be evaluated with an instance in hand.
  static bool _needsInstance(Expression expression) {
    final detector = _InstanceContextDetector();
    expression.accept(detector);
    return detector.found;
  }

  /// Fields that lose their value when the prune drops a member.
  ///
  /// A `late final String currentUserId;` assigned in `initState` is fine while
  /// `initState` is in the file and a `LateInitializationError` the moment it
  /// is not. These are exactly the bindings the fixture block exists for, so
  /// they join it: declared at the top of the file as `fixtureCurrentUserId`,
  /// assigned in a generated `initState` that does nothing else, and left empty
  /// for whoever fills the block in.
  ///
  /// Only fields with no initialiser of their own qualify. A field that carries
  /// its own value, `final _controller = TextEditingController()`, is not
  /// waiting on anything.
  static List<CapturedVariable> _fieldsSeededByDroppedMembers(
    ClassDeclaration cls,
    Set<String> keptWhole,
  ) {
    final members = (cls.body as BlockClassBody).members;

    // name -> declared type, for fields that have no value of their own.
    final unset = <String, String>{};
    for (final member in members) {
      if (member is! FieldDeclaration || member.isStatic) continue;
      final type = member.fields.type?.toSource() ?? 'dynamic';
      for (final variable in member.fields.variables) {
        if (variable.initializer == null) {
          unset[variable.name.lexeme] = type;
        }
      }
    }
    if (unset.isEmpty) return const [];

    final seeded = <String, CapturedVariable>{};
    for (final member in members) {
      if (member is! MethodDeclaration) continue;
      if (keptWhole.contains(member.name.lexeme)) continue;
      final assigned = _FieldAssignmentCollector(unset.keys.toSet());
      member.accept(assigned);
      for (final name in assigned.names) {
        seeded.putIfAbsent(
          name,
          () => CapturedVariable(name, unset[name]!, seeded.length),
        );
      }
    }
    return seeded.values.toList();
  }

  /// A method declaration with its body replaced.
  ///
  /// For a member only a handler names. The signature has to stay, because the
  /// tear-off referencing it is evaluated while the tree is built and the file
  /// will not compile without something to resolve to. The body does not,
  /// because nothing in it runs during the rebuild, and it is the body that
  /// drags in the route it pushes and the service it calls.
  ///
  /// Reassembled from the parts rather than cut out of the source, so the
  /// rewriters still reach the return type and the parameter list. Annotations
  /// are dropped: `@override` on a member the generated class does not override
  /// is a warning nothing gains from, and the body they described is gone.
  static String _signatureOnly(
    MethodDeclaration member,
    ResolvedUnitResult result,
    List<SourceRewriter> rewriters,
  ) {
    String render(AstNode? node) => node == null
        ? ''
        : Skeletonizer.skeletonize(node, result, rewriters: rewriters);

    final buffer = StringBuffer('  ');
    if (member.modifierKeyword != null) {
      buffer.write('${member.modifierKeyword!.lexeme} ');
    }
    if (member.returnType != null) {
      buffer.write('${render(member.returnType)} ');
    }
    if (member.isGetter) buffer.write('get ');
    if (member.isSetter) buffer.write('set ');
    if (member.isOperator) buffer.write('operator ');
    buffer.write(member.name.lexeme);
    buffer.write(render(member.typeParameters));
    buffer.write(render(member.parameters));

    final body = member.body;
    final modifier = [
      if (body.keyword != null) body.keyword!.lexeme,
      if (body.star != null) body.star!.lexeme,
    ].join();
    final returnType = _returnTypeOf(member);
    final filler = NonRebuildBodyEraser.completesWithNoValue(returnType)
        ? ''
        : ' throw UnimplementedError();';
    buffer.write(' $modifier{ ${NonRebuildBodyEraser.marker}$filler }');
    return buffer.toString();
  }

  /// The resolved return type of [member], across the spellings the analyzer
  /// has used for it.
  static DartType? _returnTypeOf(MethodDeclaration member) {
    try {
      final element = (member as dynamic).declaredFragment?.element;
      final type = element?.returnType;
      if (type is DartType) return type;
    } catch (_) {}
    return null;
  }

  /// The resolved type of a field variable, across the spellings the analyzer
  /// has used for it.
  static DartType? _fieldType(VariableDeclaration variable) {
    try {
      final element = (variable as dynamic).declaredFragment?.element;
      final type = element?.type;
      if (type is DartType) return type;
    } catch (_) {}
    try {
      final type = (variable as dynamic).declaredElement?.type;
      if (type is DartType) return type;
    } catch (_) {}
    return null;
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
    String memberCode, {
    List<CapturedVariable> seededFields = const [],
  }) {
    if (lifted.isEmpty && globals.isEmpty && seededFields.isEmpty) return '';
    if (RegExp(r'\bvoid\s+initState\s*\(').hasMatch(memberCode)) return '';

    final assignments = [
      // Globals first: a field initialiser may read one.
      ...globals.map((g) => '    ${g.name} = ${g.name}Value;'),
      ...lifted.map((f) => '    ${f.name} = ${_fixtureNameFor(f.name)};'),
      // Fields the scope declared itself, whose seeding went with the member
      // the prune dropped.
      ...seededFields.map((f) => '    ${f.name} = ${_fixtureNameFor(f.name)};'),
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
  List<SourceRewriter> rewriters = const [],
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
        final source = Skeletonizer.skeletonize(
          other,
          unitResult,
          rewriters: rewriters,
        );
        budget?.take(source.length);
        extractor.classCode += '\n$source\n';
        extractor.emittedNames.add(other.namePart.typeName.lexeme);
        companions.add(other);
      }
    }
  }
  return companions;
}

/// Collects the bare names one member mentions, ignoring the ones only a
/// non-rebuild callback mentions.
///
/// The eraser empties those bodies, so a helper named only inside one is not
/// reachable from the rebuild and must not keep itself alive through the
/// reference. Mirrors the bookkeeping `BuildMetricsVisitor` does for local
/// functions a handler is the only caller of.
class _MemberReferenceCollector extends RecursiveAstVisitor<void> {
  /// Names reached on a path a rebuild can run.
  final Set<String> names = {};

  /// Names reached only as `onPressed: _handleSubmit`.
  ///
  /// The reference is evaluated while the tree is built, so the name has to
  /// resolve; the body it names runs only on the press, so nothing in it counts
  /// and nothing in it needs to survive. That is a declaration without a body,
  /// which is a third answer neither set alone can carry.
  final Set<String> handlerNames = {};

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (isNonRebuildCallback(node)) return;
    super.visitFunctionExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (isNonRebuildCallbackReference(node)) {
      handlerNames.add(node.name);
      return;
    }
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}

/// Collects the names from [fields] that a member assigns to.
///
/// `x = v`, `x ??= v` and `this.x = v` all count. A read does not, and neither
/// does a member of something else that happens to share the name.
class _FieldAssignmentCollector extends RecursiveAstVisitor<void> {
  _FieldAssignmentCollector(this.fields);

  final Set<String> fields;
  final Set<String> names = {};

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final target = node.leftHandSide;
    if (target is SimpleIdentifier && fields.contains(target.name)) {
      names.add(target.name);
    } else if (target is PropertyAccess &&
        target.target is ThisExpression &&
        fields.contains(target.propertyName.name)) {
      names.add(target.propertyName.name);
    }
    super.visitAssignmentExpression(node);
  }
}

/// Detects whether an expression reads the instance it sits in.
///
/// `this`, `widget` and `context` by name, and any identifier that resolved to
/// a non-static member of a class. Such an expression cannot be evaluated at
/// the top level of the file, so the field it initialises cannot be hoisted
/// into the fixture block.
class _InstanceContextDetector extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitThisExpression(ThisExpression node) {
    found = true;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (found) return;
    if (node.name == 'widget' || node.name == 'context') {
      found = true;
      return;
    }
    // A qualified tail says nothing about the receiver: `Colors.red` is not an
    // instance read, and `red` is not a name in scope here.
    final parent = node.parent;
    if (parent is PropertyAccess && identical(parent.propertyName, node)) {
      return;
    }
    if (parent is PrefixedIdentifier && identical(parent.identifier, node)) {
      return;
    }
    if (parent is MethodInvocation && identical(parent.methodName, node)) {
      if (parent.realTarget != null) return;
    }

    // Reading the element through `dynamic` for the same reason the rest of
    // this file does: the analyzer has changed the spelling more than once.
    try {
      final dynamic target = node;
      final Object? element = target.element ?? target.staticElement;
      if (element == null) return;
      final dynamic member = element;
      if (member.enclosingElement is! InterfaceElement) return;
      // A static member of some other class is nameable from anywhere.
      if (member.isStatic != true) found = true;
    } catch (_) {
      // Unresolved, so there is nothing here to say it needs an instance.
    }
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    node.rightHandSide.accept(this);
  }
}
