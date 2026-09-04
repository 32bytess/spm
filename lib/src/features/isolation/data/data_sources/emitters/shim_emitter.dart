import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spm/src/core/analysis/type_predicates.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/default_values.dart';

/// Emits declaration-only stand-ins for symbols the transplant cannot inline.
///
/// Declarations that produce no UI reach here, meaning models, services, and
/// theme or constant holders, whether they are repo-local or third-party: the
/// filter in the transplant's cross-file loop skips them, and the isolated file
/// then references a name nothing declares. That is an error-severity
/// diagnostic, and `spm analyze` skips any file that carries one. Output the
/// analyzer refuses to read is of no use to the tool that produced it.
///
/// Third-party declarations reach here for three further reasons: the run was
/// given `--no-inline-third-party`, the inline budget was spent, or the name is
/// one `package:flutter/material.dart` also exports. See `flutter_namespace.dart` for
/// why the last of those prefers a stand-in over the real declaration.
///
/// ## What a shim preserves, and what it deliberately does not
///
/// A shim carries exactly one thing faithfully: **whether the symbol is a
/// `Widget`**. `BuildMetricsVisitor` classifies an allocation by walking the
/// resolved supertype chain for `Widget`, so a stand-in whose chain does not
/// reach `Widget` silently moves that allocation from `widgetCount` to
/// `valueObjectAllocCount`. That is the failure mode a shim exists to avoid,
/// and it is why [_renderType] falls back to a type's nearest nameable
/// supertype rather than to `dynamic`: `dynamic` would resolve just as
/// cleanly and be just as wrong.
///
/// Everything else degrades. Member types the isolated file cannot name become
/// `dynamic`, bodies become `throw UnimplementedError()`, and constants become
/// `null`. None of that is measured, because the extracted features come from
/// the build tree's shape and never from a value. A fabricated concrete type
/// would be worse than an honest `dynamic`, since it can be wrong in a
/// direction the feature extractor believes.
///
/// ## The limitation to state plainly
///
/// A shimmed widget has an empty `build`, so an isolated scope that constructs
/// one describes a smaller tree than the code it came from actually builds.
///
/// For a repo-local widget that is a straight loss, and `tree_extractor` proves
/// it: analyzing the original project recurses into custom child widgets' build
/// bodies and into widget-returning helpers, so the in-place row counts a
/// subtree the shimmed row does not. Inlining anything that can produce UI is
/// what keeps that from being the normal case (see `ui_surface.dart`).
///
/// For a third-party widget the comparison runs the other way, which is worth
/// stating because the symmetry is tempting and wrong.
/// `TreeExtractor._indexLibrary` cannot read a library under the pub cache:
/// `AnalysisContextCollection.contextFor` throws for a path outside the
/// analyzed roots, so the child is dropped and the in-place row never counted
/// that subtree either. Carrying the widget therefore makes the isolated row
/// LARGER than the in-place one. The isolated file is the better reproduction
/// of the code; it is not the same measurement.
///
/// What is left reaching this emitter is the exceptions listed above, and every
/// one of them is either asked for or recorded on the row.
class ShimEmitter {
  /// [alreadyDeclared] is the live set of names the isolated file declares by
  /// inlining. It is read at [render] time, not at [request] time, because
  /// inlining and shim requests interleave: a name requested early may still
  /// be inlined later, and the inlined declaration always wins.
  ShimEmitter(this._alreadyDeclared, this._defaults);

  final Set<String> _alreadyDeclared;

  /// Supplies the value every rendered body and field hands back.
  ///
  /// Shared with the transplant, so a file declares `_Stub` once no matter
  /// which emitter first needed one.
  final DefaultValues _defaults;

  /// Requested symbols keyed by name. First request for a name wins; a second
  /// element under the same name would collide in the output anyway.
  ///
  /// Keying by simple name is what makes two collisions possible, both rare and
  /// neither guarded: two third-party types sharing a name merge into one shim,
  /// and a third-party type whose name Flutter also uses (a package declaring
  /// its own `Text`) shadows the SDK's for the whole file. Resolving either
  /// would mean carrying library URIs through the emitted source, which Dart
  /// has no syntax for without an import, and importing is what this whole
  /// path exists to avoid.
  final Map<String, Element> _requested = {};

  /// The members each requested symbol has to carry, keyed by owner name and
  /// then by member key (a setter's key carries a trailing `=`, as Dart's own
  /// naming does, so a getter and setter for one name both survive).
  ///
  /// Members are recorded from the *reference*, not from the declaration, so an
  /// inherited member lands on the shim that needs it rather than on a base
  /// class the file never emits.
  final Map<String, Map<String, Element>> _members = {};

  /// Owners whose full declared surface is emitted rather than only the
  /// members that were referenced. See [request].
  final Set<String> _allMembers = {};

  /// Records that [element] needs a stand-in.
  ///
  /// [member] is the specific member the reference reached, when there was
  /// one. Recording it keeps the shim to the size of what is actually used:
  /// rendering every member of a third-party value object produces hundreds of
  /// accessors for a type the scope touches twice.
  ///
  /// [allMembers] asks for the whole declared surface instead, which is what
  /// the repo-local path wants: it requests a declaration wholesale, having
  /// never seen which of its members the scope reaches.
  ///
  /// Silently ignores anything unnamed or of a kind [render] cannot express;
  /// a missing shim degrades to the pre-existing dangling reference rather
  /// than to broken output.
  void request(Element element, {Element? member, bool allMembers = false}) {
    final name = element.name;
    if (name == null || name.isEmpty || !_isIdentifier(name)) return;
    if (!_isShimmable(element)) return;
    _requested.putIfAbsent(name, () => element);
    if (allMembers) _allMembers.add(name);
    if (member == null) return;
    final key = _memberKey(member);
    if (key == null) return;
    (_members[name] ??= {}).putIfAbsent(key, () => member);
  }

  /// The key a member is stored under, or null when it cannot be rendered.
  ///
  /// Private members are dropped: a shim always stands in for a declaration in
  /// another library, where a private name was never reachable to begin with.
  static String? _memberKey(Element member) {
    final name = member is ConstructorElement
        ? (member.name ?? 'new')
        : member.name;
    if (name == null || name.isEmpty) return null;
    if (member is ConstructorElement) {
      return name == 'new' || _isIdentifier(name) ? 'new:$name' : null;
    }
    if (name.startsWith('_') || !_isIdentifier(name)) return null;
    return member is SetterElement ? '$name=' : name;
  }

  /// The names this emitter would declare, excluding any that got inlined.
  Set<String> get shimmedNames =>
      _requested.keys.where((n) => !_alreadyDeclared.contains(n)).toSet();

  /// Tells [_defaults] which of this emitter's declarations can supply a value.
  ///
  /// Called once the cross-file loop has finished and [_alreadyDeclared] has
  /// stopped growing, because a name that got inlined is not this emitter's to
  /// describe: the real declaration may need constructor arguments the stand-in
  /// would not have. Seed declarations are built after this and before
  /// [render], so both see the same answers.
  void publishDefaults() {
    for (final name in shimmedNames) {
      final element = _requested[name]!;
      if (element is EnumElement) {
        final first = element.constants
            .map((c) => c.name)
            .whereType<String>()
            .where(_isIdentifier)
            .firstOrNull;
        _defaults.registerEnum(name, first ?? '_shimEmpty');
        continue;
      }
      if (element is! InterfaceElement || element is MixinElement) continue;
      if (_hasUsableUnnamedConstructor(element)) {
        _defaults.registerConstructible(name);
      }
    }
  }

  /// Whether writing `Name()` builds this stand-in.
  ///
  /// A required positional parameter is the only thing that stops it.
  /// `required` is dropped from named parameters by [_renderParameters], and a
  /// type that declares no constructor at all still has the synthesised unnamed
  /// one in [InterfaceElement.constructors].
  static bool _hasUsableUnnamedConstructor(InterfaceElement element) {
    for (final ctor in element.constructors) {
      final name = ctor.name;
      if (name != null && name.isNotEmpty && name != 'new') continue;
      return !ctor.formalParameters.any((p) => p.isRequiredPositional);
    }
    return false;
  }

  /// Renders every requested shim, or an empty string when there are none.
  ///
  /// Output is sorted by name so two runs over the same input are byte-equal.
  String render() {
    final names = shimmedNames.toList()..sort();
    if (names.isEmpty) return '';

    // Available for type rendering: what the file inlines, plus what this
    // emitter is about to declare.
    final available = {..._alreadyDeclared, ...names};

    final bodies = <String>[];
    for (final name in names) {
      final source = _renderElement(_requested[name]!, name, available);
      if (source != null) bodies.add(source);
    }
    if (bodies.isEmpty) return '';

    return '''

// Declaration-only stand-ins for symbols this scope references but does not
// carry: repo-local declarations that build no UI, and third-party ones the
// transplant does not inline. Supertypes are mirrored so a widget still reads
// as a widget; everything else is `dynamic`, because none of it is measured.
${bodies.join('\n\n')}
''';
  }

  // ---------------------------------------------------------------------------
  // Declarations
  // ---------------------------------------------------------------------------

  bool _isShimmable(Element element) =>
      element is InterfaceElement ||
      element is ExtensionElement ||
      element is TypeAliasElement ||
      element is TopLevelVariableElement ||
      (element is ExecutableElement &&
          element.enclosingElement is LibraryElement);

  String? _renderElement(Element element, String name, Set<String> available) {
    if (element is EnumElement) return _renderEnum(element);
    if (element is InterfaceElement) {
      return _renderInterface(element, name, available);
    }
    if (element is ExtensionElement) {
      return _renderExtension(element, name, available);
    }
    if (element is TypeAliasElement) {
      // The type parameters have to come across even though the aliased type
      // does not: `Cb<int>` at the use site is an error against a `typedef Cb`
      // that takes none.
      final typeParams = _typeParameterNames(element.typeParameters);
      return 'typedef $name${_renderTypeParams(typeParams)} = dynamic;';
    }
    if (element is TopLevelVariableElement) {
      return _renderTopLevelVariable(element, available);
    }
    if (element is ExecutableElement) {
      return _renderExecutable(element, available, const {}, topLevel: true);
    }
    return null;
  }

  /// An enum's constants are its whole contract: a `switch` over it is checked
  /// for exhaustiveness, and each constant may be used as a constant. Nothing
  /// else about the enum is measured, so the members are dropped.
  String _renderEnum(EnumElement element) {
    final constants = element.constants
        .map((c) => c.name)
        .whereType<String>()
        .where(_isIdentifier)
        .toList();
    if (constants.isEmpty) return 'enum ${element.name} { _shimEmpty }';
    return 'enum ${element.name} { ${constants.join(', ')} }';
  }

  String _renderInterface(
    InterfaceElement element,
    String name,
    Set<String> available,
  ) {
    final typeParams = _typeParameterNames(element.typeParameters);
    final keyword = element is MixinElement ? 'mixin' : 'class';

    // Widget-ness is the one property that has to survive. Collapsing every
    // widget to `StatelessWidget` keeps `Widget` in the resolved chain while
    // leaving exactly one abstract member to satisfy. A `StatefulWidget` base
    // would demand a `createState` returning a `State` the shim cannot supply.
    final isWidget = hasSupertypeNamed(element, 'Widget');
    final passThrough = (isWidget && element is! MixinElement)
        ? _passThroughFor(element, name)
        : null;

    final members = <String>[];
    if (passThrough != null) {
      // `dynamic`, not `Widget?`. A `this.child` parameter takes the field's
      // type, so a `Widget?` field would refuse a builder, a nullable subtype
      // or another stand-in at the call site, which is the family of failures
      // the dynamic parameter types exist to remove. `dynamic` is assignable in
      // both directions and the `is Widget` test recovers the one thing that
      // matters.
      members.add('  final dynamic $passThrough;');
    }
    if (element is! MixinElement) {
      for (final ctor in _constructorsFor(element)) {
        final rendered = _renderConstructor(
          ctor,
          element,
          available,
          typeParams,
          isWidget: isWidget,
          passThrough: passThrough,
        );
        if (rendered != null) members.add(rendered);
      }
    }
    if (isWidget && element is! MixinElement) {
      members.add(_renderShimBuild(passThrough));
    }
    // The supertype is chosen before the members are rendered, because it
    // supplies some of them. `_pairedMembersOf` emits `addListener`,
    // `removeListener` and `dispose` for anything that inherits them, and
    // against a real `extends ChangeNotifier` those become overrides the
    // analyzer checks. Skipping them is right rather than merely safe: the
    // supertype's own implementations are the ones the call sites were written
    // against.
    final supertype = (isWidget || element is MixinElement)
        ? null
        : _shimSupertype(element, available);
    final inherited = supertype == null
        ? const <String>{}
        : _memberNamesOf(supertype.element);

    final rendered = _renderMembers(
      element,
      name,
      available,
      typeParams,
      // `createState` goes with `build`, and for the same reason the base was
      // collapsed: this shim extends `StatelessWidget`, and `State<T>` bounds
      // `T` on `StatefulWidget`, so carrying the real type's `createState`
      // would render `State<Foo> createState()` against a `Foo` that is no
      // longer stateful. Nothing calls it either -- the framework would, and a
      // stand-in widget never reaches the framework.
      skip: isWidget
          ? const {'build', 'createState', ..._frameworkOnly}
          : {..._frameworkOnly, ...inherited},
      // The pass-through name is spoken for. Without this the real class's own
      // `child` renders as a getter beside the field and the class declares one
      // name twice.
      reserved: passThrough == null ? const {} : {passThrough, '$passThrough='},
    );
    members.addAll(rendered.lines);

    final header = StringBuffer();
    header.write('$keyword ${element.name}${_renderTypeParams(typeParams)}');
    if (isWidget && element is! MixinElement) {
      header.write(' extends StatelessWidget');
    } else if (supertype != null) {
      header.write(' extends ${supertype.element.name}');
    }

    if (members.isEmpty) return '$header {}';
    return '$header {\n${members.join('\n')}\n}';
  }

  /// Constructor parameter names a widget stand-in carries into its `build`.
  ///
  /// A stand-in used to accept `child` and render `const SizedBox.shrink()`,
  /// so whatever tree the transplanted code passed in was constructed and then
  /// never mounted, laid out or painted. Where such a stand-in was the root of
  /// the generated build, the whole scope drew a blank box.
  ///
  /// Keyed on the name rather than on the type, because the type gets the
  /// commonest case wrong. A wrapper that takes a `List<Widget>` of state
  /// containers rather than of visual children is the shape that shows it:
  /// rendering those would build objects the application never draws, and a
  /// rule keyed on the type alone cannot tell them from a real child list. The
  /// list below is a floor rather than a closed set, and it should grow from
  /// what real output turns out to need.
  static const List<String> _passThroughParameters = [
    'child',
    'body',
    'children',
  ];

  /// The parameter [element] hands on to its build, or null when it has none.
  String? _passThroughFor(InterfaceElement element, String name) {
    final declared = <String>{};
    for (final ctor in _constructorsFor(element)) {
      for (final parameter in ctor.formalParameters) {
        final parameterName = parameter.name;
        if (parameterName != null) declared.add(parameterName);
      }
    }
    for (final candidate in _passThroughParameters) {
      if (declared.contains(candidate)) return candidate;
    }
    return null;
  }

  /// The `build` body of a widget stand-in.
  ///
  /// `children` wraps in `Stack`, and that is not a matter of taste.
  /// `BuildMetricsVisitor._classifyListStrategy` returns its most expensive
  /// class for any `Column`, `Row`, `Wrap` or `Flex` whose `children:` is not a
  /// fixed-arity literal, and `listRenderingStrategy` is taken as a scope-wide
  /// maximum, so a `Column` here would pin `treeListRenderingStrategy` at its
  /// ceiling for every scope reaching such a stand-in, in the transplant and
  /// nowhere else. `Stack` is in none of the visitor's list sets, and unlike
  /// `Column` it cannot overflow in an unbounded constraint.
  String _renderShimBuild(String? passThrough) {
    if (passThrough == null) {
      return '  @override\n'
          '  Widget build(BuildContext context) => const SizedBox.shrink();';
    }
    if (passThrough == 'children') {
      return '  @override\n'
          '  Widget build(BuildContext context) => Stack(\n'
          '    children: $passThrough is List<Widget>\n'
          '        ? $passThrough as List<Widget>\n'
          '        : const <Widget>[],\n'
          '  );';
    }
    return '  @override\n'
        '  Widget build(BuildContext context) => $passThrough is Widget\n'
        '      ? $passThrough as Widget\n'
        '      : const SizedBox.shrink();';
  }

  /// The supertype a non-widget stand-in declares, or null for none.
  ///
  /// A stand-in with no supertype at all used to be the whole answer for
  /// anything that is not a widget, and the cost is generic bounds. Carrying a
  /// package widget declared as `Wrapper<T extends ChangeNotifier?>` brings its
  /// real bound across, and the repository-local class that satisfies that
  /// bound in the application is a stand-in here. A bound is not a parameter,
  /// so degrading parameter types to `dynamic` does not reach it. The same
  /// applies to `is` and `as` sites and to the Widget-typed fields that keep
  /// their real types.
  ///
  /// The supertype is dropped whenever it could not be extended cleanly:
  ///
  ///  * an abstract supertype, which would leave members to implement,
  ///  * one this library may not extend at all (`final`, `sealed`, `interface`
  ///    or `base`),
  ///  * one with no unnamed constructor callable without arguments, or one
  ///    whose unnamed constructor is not `const` when a rendered constructor is.
  ///
  /// A member the supertype already declares is not a fourth case: it is
  /// skipped rather than rendered, so the `dynamic` signature that would be an
  /// invalid override never gets written.
  InterfaceType? _shimSupertype(
    InterfaceElement element,
    Set<String> available,
  ) {
    final candidate = _nearestNameableSupertypeType(
      element.thisType,
      available,
    );
    if (candidate == null) return null;
    final target = candidate.element;
    if (target is! ClassElement) return null;
    if (target.isAbstract ||
        target.isFinal ||
        target.isSealed ||
        target.isInterface ||
        target.isBase) {
      return null;
    }

    ConstructorElement? unnamed;
    for (final ctor in target.constructors) {
      final ctorName = ctor.name;
      if (ctorName != null && ctorName.isNotEmpty && ctorName != 'new') {
        continue;
      }
      unnamed = ctor;
      break;
    }
    if (unnamed == null) return null;
    if (unnamed.formalParameters.any((p) => p.isRequired)) return null;
    if (!unnamed.isConst && element.constructors.any((c) => c.isConst)) {
      return null;
    }

    return candidate;
  }

  /// Every member name [element] declares or inherits.
  static Set<String> _memberNamesOf(InterfaceElement element) {
    final names = <String>{};
    void scan(InterfaceElement owner) {
      for (final member in owner.methods) {
        if (member.name case final String name) names.add(name);
      }
      for (final member in owner.fields) {
        if (member.name case final String name) names.add(name);
      }
    }

    scan(element);
    for (final supertype in element.allSupertypes) {
      scan(supertype.element);
    }
    return names;
  }

  String _renderExtension(
    ExtensionElement element,
    String name,
    Set<String> available,
  ) {
    final typeParams = _typeParameterNames(element.typeParameters);
    final on = _renderType(element.extendedType, available, typeParams);
    final members = _renderMembers(element, name, available, typeParams).lines;
    final header = 'extension $name${_renderTypeParams(typeParams)} on $on';
    if (members.isEmpty) return '$header {}';
    return '$header {\n${members.join('\n')}\n}';
  }

  /// Members only the framework calls, which a stand-in therefore never needs.
  ///
  /// `debugFillProperties` is the one that costs something: its parameter type
  /// is `DiagnosticPropertiesBuilder`, and `package:flutter/widgets.dart`
  /// re-exports foundation as `show Brightness, UniqueKey`, so the name does NOT
  /// arrive through `material.dart`. A shim that carries the signature needs an
  /// unprefixed foundation import that the transplant may not have -- and when
  /// the source wrote `import 'package:flutter/foundation.dart' as foundation;`
  /// it definitely does not. Dropping the member is what the shim is for: a
  /// declaration-only stand-in owes the call sites, and nothing here calls it.
  static const Set<String> _frameworkOnly = {'debugFillProperties'};

  /// The most members a type may declare and still have its whole surface
  /// rendered.
  ///
  /// Referenced-only was too little and everything was too much. A stub built
  /// from references alone carries whichever members the traversal happened to
  /// reach, so `removeListener` lands and `addListener` does not, and the file
  /// fails at the one call site the shim forgot. Rendering everything is what
  /// the referenced-only rule was written to avoid: a maths or geometry value
  /// object can run to hundreds of lines. A small type costs little to render
  /// whole,
  /// so the cutoff buys completeness where completeness is cheap and keeps the
  /// reference set where it is not.
  static const int _fullSurfaceLimit = 40;

  /// Members that come as a set, so a shim carrying one has to carry them all.
  ///
  /// `initState` adds a listener and `dispose` removes it. Reaching only one of
  /// the two is the recurring shape, and both are inherited from
  /// `ChangeNotifier` often enough that neither is declared on the type being
  /// stood in for.
  static const Set<String> _pairedMembers = {
    'addListener',
    'removeListener',
    'dispose',
  };

  /// Whether [owner]'s whole declared surface is rendered.
  bool _rendersFullSurface(InstanceElement owner, String name) {
    if (_allMembers.contains(name)) return true;
    return owner.fields.length + owner.methods.length <= _fullSurfaceLimit;
  }

  /// The constructors to emit for [owner], which is all of them.
  ///
  /// This used to gate on the same flag as members, so a type declaring more
  /// than [_fullSurfaceLimit] fields and methods emitted no constructors at all
  /// unless a reference happened to reach one, and a call site's named
  /// arguments then landed on the implicit default constructor. That is a
  /// direct source of `undefined_named_parameter`, and the saving was never
  /// real: a constructor renders as one line, where the limit exists to stop a
  /// geometry value object contributing hundreds of accessors.
  List<ConstructorElement> _constructorsFor(InterfaceElement owner) =>
      owner.constructors;

  /// The members named in [_pairedMembers] that [owner] has, declared or
  /// inherited.
  ///
  /// Walked over the supertypes as well as the declaration, since a controller
  /// that extends `ChangeNotifier` declares none of them itself.
  List<ExecutableElement> _pairedMembersOf(InstanceElement owner) {
    final found = <String, ExecutableElement>{};
    void scan(Iterable<ExecutableElement> members) {
      for (final member in members) {
        final name = member.name;
        if (name == null || !_pairedMembers.contains(name)) continue;
        found.putIfAbsent(name, () => member);
      }
    }

    scan(owner.methods);
    if (owner is InterfaceElement) {
      for (final supertype in owner.allSupertypes) {
        scan(supertype.element.methods);
      }
    }
    return found.values.toList();
  }

  /// Renders the members of [owner], honouring the referenced-only rule.
  ///
  /// In [_allMembers] mode the declared surface is walked; otherwise the
  /// recorded member elements are rendered directly, which is what lets an
  /// inherited member land on the shim that needs it.
  ({List<String> lines, Set<String> names}) _renderMembers(
    InstanceElement owner,
    String name,
    Set<String> available,
    Set<String> typeParams, {
    Set<String> skip = const {},
    Set<String> reserved = const {},
  }) {
    final out = <String>[];
    // Two sources can name one member: the declared surface and the recorded
    // references, which may hold the inherited element of the same name. The
    // second spelling would be a duplicate declaration, so keys are tracked as
    // they are emitted. A field claims both its getter and its setter key,
    // since it renders as the pair.
    final emitted = <String>{...reserved};

    void renderOne(Element member) {
      final memberName = member.name;
      if (memberName == null ||
          memberName.isEmpty ||
          memberName.startsWith('_') ||
          skip.contains(memberName) ||
          !_isIdentifier(memberName)) {
        return;
      }
      if (member is ConstructorElement) return;
      if (member is FieldElement) {
        if (!emitted.add(memberName)) return;
        emitted.add('$memberName=');
        out.addAll(_renderField(member, available, typeParams));
        return;
      }
      if (!emitted.add(_memberKey(member) ?? memberName)) return;
      if (member is GetterElement) {
        final prefix = member.isStatic ? '  static ' : '  ';
        out.add(
          '$prefix${_renderAccessor(member.returnType, available, typeParams, memberName)}',
        );
        return;
      }
      if (member is SetterElement) {
        // A setter's parameter is a parameter, so it degrades with the rest.
        final prefix = member.isStatic ? '  static ' : '  ';
        out.add('${prefix}set $memberName(dynamic _) {}');
        return;
      }
      if (member is ExecutableElement) {
        final rendered = _renderExecutable(
          member,
          available,
          typeParams,
          topLevel: false,
        );
        if (rendered != null) out.add('  $rendered');
      }
    }

    if (_rendersFullSurface(owner, name)) {
      for (final field in owner.fields) {
        renderOne(field);
      }
      for (final method in owner.methods) {
        renderOne(method);
      }
    } else {
      for (final member in _pairedMembersOf(owner)) {
        renderOne(member);
      }
    }

    // Recorded references last: an inherited member lands on the shim that
    // needs it, and anything the surface already declared is skipped above.
    for (final member in (_members[name] ?? const <String, Element>{}).values) {
      renderOne(member);
    }
    return (lines: out, names: emitted.difference(reserved));
  }

  /// Renders a getter as `T get name => <value>;`, widening `T` when needed.
  ///
  /// The value comes from [_defaults], which cannot always build the declared
  /// type. When it cannot, the getter is declared nullable and hands back null,
  /// which is still a value rather than a throw.
  String _renderAccessor(
    DartType type,
    Set<String> available,
    Set<String> typeParams,
    String memberName,
  ) {
    final rendered = _renderMemberType(type, available, typeParams);
    if (rendered == 'void') return 'void get $memberName {}';
    final value = _valueFor(type, rendered);
    final declared = value.nullableType ? _optional(rendered) : rendered;
    return '$declared get $memberName => ${value.expression};';
  }

  /// The value a member of [type] hands back, when it renders as [rendered].
  ///
  /// The two are usually the same and the exception matters. Degrading a
  /// member's declared type to `dynamic` is what stops the call site
  /// disagreeing with the stand-in about that type, but it also throws away the
  /// one thing a value can be built from, and a stub in a slot the call site
  /// typed `String` is a `TypeError` at the first frame. So the declaration
  /// keeps `dynamic` and the value is built from the real type wherever one can
  /// be, and only falls back to a stub when nothing can.
  DefaultValue _valueFor(DartType type, String rendered) {
    final isWidget = _isWidgetType(type);
    // The real type first, and the order is the whole point. `dynamic` always
    // yields a stub, so asking about the rendered type first would answer every
    // question with one and the `String` the call site expects would never be
    // reached.
    final real = _defaults.forType(type.getDisplayString(), isWidget: isWidget);
    if (real != null && !real.nullableType) return real;
    final direct = _defaults.forType(rendered, isWidget: isWidget);
    if (direct != null) return direct;
    return real ?? _defaults.forTypeOrNull(rendered, isWidget: isWidget);
  }

  /// Renders one field as an accessor pair rather than as a field.
  ///
  /// A class with instance fields cannot have a `const` constructor unless
  /// every one of them is final and initialised, and the shim has to keep
  /// whatever `const` constructors the real class had, since dropping `const`
  /// turns every `const Foo()` at a use site into INVALID_CONSTANT. A `static const`
  /// field stays a field, since that is what a const use site needs to read.
  List<String> _renderField(
    FieldElement field,
    Set<String> available,
    Set<String> typeParams,
  ) {
    final name = field.name;
    if (name == null || field.isEnumConstant) return const [];
    if (field.isStatic && field.isConst) {
      return ['  static const dynamic $name = null;'];
    }
    final prefix = field.isStatic ? '  static ' : '  ';
    final out = [
      '$prefix${_renderAccessor(field.type, available, typeParams, name)}',
    ];
    if (field.setter != null && !field.isFinal && !field.isConst) {
      out.add('${prefix}set $name(dynamic _) {}');
    }
    return out;
  }

  String _renderTopLevelVariable(
    TopLevelVariableElement element,
    Set<String> available,
  ) {
    // A `const` holder is routinely read from a const context (`const
    // TextStyle(color: AppColors.primary)`), so the stand-in has to be const
    // too or the use site becomes INVALID_CONSTANT. `null` typed `dynamic` is
    // a valid constant and assignable wherever the real value was.
    if (element.isConst) return 'const dynamic ${element.name} = null;';
    final type = _renderMemberType(element.type, available, const {});
    final value = _valueFor(element.type, type);
    final declared = value.nullableType ? _optional(type) : type;
    return '$declared ${element.name} = ${value.expression};';
  }

  String? _renderConstructor(
    ConstructorElement ctor,
    InterfaceElement owner,
    Set<String> available,
    Set<String> typeParams, {
    required bool isWidget,
    String? passThrough,
  }) {
    final ctorName = ctor.name;
    // The unnamed constructor is `new` in the element model of analyzer >= 13.
    final suffix = (ctorName == null || ctorName.isEmpty || ctorName == 'new')
        ? ''
        : '.$ctorName';
    if (suffix.isNotEmpty && !_isIdentifier(ctorName!)) return null;

    final declaresPassThrough =
        passThrough != null &&
        ctor.formalParameters.any((p) => p.name == passThrough);
    final params = _renderParameters(
      ctor.formalParameters,
      available,
      typeParams,
      // `StatelessWidget` supplies `key`, so a shim widget forwards it rather
      // than shadowing it with a parameter of its own.
      superFormals: isWidget ? const {'key'} : const {},
      fieldFormals: declaresPassThrough ? {passThrough} : const {},
    );
    // A final field with no initialiser has to be initialised by every
    // generative constructor, so the ones that do not take the pass-through
    // name it here. Shim constructors carry no initialiser list otherwise, so
    // this is safe to add unconditionally; without it the output gains
    // `final_not_initialized_constructor`.
    final initialiser = (passThrough != null && !declaresPassThrough)
        ? ' : $passThrough = null'
        : '';
    // A const constructor may not have a body; the shim never needs one, since
    // all of its state is accessors.
    final constPrefix = ctor.isConst ? 'const ' : '';
    return '  $constPrefix${owner.name}$suffix($params)$initialiser;';
  }

  String? _renderExecutable(
    ExecutableElement element,
    Set<String> available,
    Set<String> typeParams, {
    required bool topLevel,
  }) {
    final name = element.name;
    if (name == null || !_isIdentifier(name)) return null;
    // Operators and `call` carry syntax this renderer does not express, and
    // nothing measured depends on them.
    if (name == 'call') return null;

    final ownTypeParams = _typeParameterNames(element.typeParameters);
    final allTypeParams = {...typeParams, ...ownTypeParams};
    final returnType = _renderMemberType(
      element.returnType,
      available,
      allTypeParams,
    );
    final params = _renderParameters(
      element.formalParameters,
      available,
      allTypeParams,
    );
    final staticPrefix = (!topLevel && element.isStatic) ? 'static ' : '';
    String signature(String type) =>
        '$staticPrefix$type $name'
        '${_renderTypeParams(ownTypeParams)}($params)';
    if (returnType == 'void') return '${signature('void')} {}';
    final value = _valueFor(element.returnType, returnType);
    final declared = value.nullableType ? _optional(returnType) : returnType;
    return '${signature(declared)} => ${value.expression};';
  }

  /// Renders a parameter list, mirroring the real element's parameter kinds.
  ///
  /// `required` is dropped from named parameters: a shim is never constructed
  /// by anything but the transplanted code, and a requirement it does not
  /// satisfy would be a fresh error rather than a fixed one. Default values are
  /// dropped for the same reason, since the real one may reference a symbol the
  /// isolated file does not have.
  ///
  /// Every parameter type is rendered `dynamic`, which is assignable in both
  /// directions. Rendering the real type is what produced most of the output's
  /// error-severity diagnostics: [_renderType] names a type by its nearest
  /// nameable supertype while the argument at the call site is a stand-in, so
  /// the two halves disagree about the same type and the call does not
  /// type-check.
  ///
  /// Two facts make this safe. Anything reaching this emitter was already found
  /// by the UI gate to produce no UI, so no call on it returns a `Widget`. And
  /// a parameter's declared type is never an allocation: `BuildMetricsVisitor`
  /// classifies by walking the supertype chain of the type actually
  /// constructed, which the call site still spells out in full.
  String _renderParameters(
    List<FormalParameterElement> parameters,
    Set<String> available,
    Set<String> typeParams, {
    Set<String> superFormals = const {},
    Set<String> fieldFormals = const {},
  }) {
    final positional = <String>[];
    final optionalPositional = <String>[];
    final named = <String>[];

    for (final p in parameters) {
      var name = p.name;
      if (name == null || name.isEmpty || !_isIdentifier(name)) continue;
      if (p.isNamed && superFormals.contains(name)) {
        named.add('super.$name');
        continue;
      }
      // A private parameter name reaches here through a field formal such as
      // `Vector3.fromFloat64List(this._v3storage)`. Named parameters cannot be
      // private at all, and a positional one has no business carrying a name
      // out of another library's private surface, so it becomes a slot.
      if (name.startsWith('_')) {
        if (p.isNamed) continue;
        name = 'p${positional.length + optionalPositional.length}';
      }
      final declaration = fieldFormals.contains(name)
          ? 'this.$name'
          : 'dynamic $name';
      if (p.isRequiredPositional) {
        positional.add(declaration);
      } else if (p.isOptionalPositional) {
        optionalPositional.add(declaration);
      } else {
        named.add(declaration);
      }
    }

    final parts = <String>[...positional];
    // A signature carries optional-positional or named parameters, never both.
    if (optionalPositional.isNotEmpty) {
      parts.add('[${optionalPositional.join(', ')}]');
    } else if (named.isNotEmpty) {
      parts.add('{${named.join(', ')}}');
    }
    return parts.join(', ');
  }

  // ---------------------------------------------------------------------------
  // Types
  // ---------------------------------------------------------------------------

  /// Renders [type] using only names the isolated file can resolve.
  ///
  /// A type that cannot be named falls back to its nearest nameable supertype
  /// before it falls back to `dynamic`. That ordering is the whole point: a
  /// third-party widget rendered as `dynamic` resolves perfectly and is then
  /// counted as a value object, where the same widget rendered as `Widget`
  /// keeps its classification.
  String _renderType(
    DartType type,
    Set<String> available,
    Set<String> typeParams,
  ) {
    if (type is VoidType) return 'void';
    if (type is DynamicType || type is InvalidType) return 'dynamic';
    if (type is NeverType) return 'Never';
    if (type is TypeParameterType) {
      final name = type.element.name;
      return (name != null && typeParams.contains(name)) ? name : 'dynamic';
    }
    if (type is! InterfaceType) return 'dynamic';

    final name = type.element.name;
    if (name != null && _isNameable(type.element, available)) {
      final args = type.typeArguments;
      final rendered = args.isEmpty
          ? name
          : '$name<${args.map((a) => _renderType(a, available, typeParams)).join(', ')}>';
      return _withNullability(rendered, type);
    }

    final fallback = _nearestNameableSupertype(type, available);
    return fallback == null ? 'dynamic' : _withNullability(fallback, type);
  }

  /// Whether the isolated file can write [element]'s name and have it resolve.
  ///
  /// Three sources qualify: names the file declares itself (inlined or
  /// shimmed), `dart:core`, and anything `package:flutter/material.dart`
  /// re-exports, which covers the widget, painting, rendering, foundation and
  /// `dart:ui` surface the transplant relies on. Nothing else is imported, so
  /// nothing else is nameable.
  bool _isNameable(Element element, Set<String> available) {
    final name = element.name;
    if (name != null && available.contains(name)) return true;
    final uri = _libraryUri(element);
    if (uri == null) return false;
    return uri == 'dart:core' ||
        uri == 'dart:ui' ||
        uri.startsWith('package:flutter/');
  }

  /// The type a member hands out, degraded unless it reaches `Widget`.
  ///
  /// Keeping every return and field type was leaving `invalid_assignment` and
  /// part of `undefined_getter` in place, since those live on getters and
  /// fields rather than on parameters. What has to survive is narrower than
  /// "return types": it is whether the member hands out a widget.
  /// `helperWidgetCount` and `helperReferenceCount` come from the
  /// widget-returning-helper rule in `ui_surface.dart` and
  /// `BuildMetricsVisitor._producesWidgets`, and that rule admits
  /// `Iterable<Widget>` as well as `Widget`.
  String _renderMemberType(
    DartType type,
    Set<String> available,
    Set<String> typeParams,
  ) {
    if (type is VoidType) return 'void';
    if (!_reachesWidget(type)) return 'dynamic';
    return _renderType(type, available, typeParams);
  }

  /// Whether [type] is a widget, or an iterable of them.
  ///
  /// The iterable case is not an embellishment: a `List<Widget> _buildRows()`
  /// helper is counted as widget-producing in place, and a stand-in that
  /// rendered it `dynamic` would stop being counted that way in the transplant.
  static bool _reachesWidget(DartType type) {
    if (_isWidgetType(type)) return true;
    if (type is! InterfaceType) return false;
    for (final candidate in [type, ...type.allSupertypes]) {
      if (candidate.element.name != 'Iterable') continue;
      final args = candidate.typeArguments;
      if (args.length == 1 && _reachesWidget(args.single)) return true;
    }
    return false;
  }

  /// Whether [type] is a widget itself.
  ///
  /// Distinct from [_reachesWidget], and the distinction decides what a member
  /// hands back: a `List<Widget>` member keeps its declared type because the
  /// helper rule counts it, and its value is an empty list rather than a
  /// widget.
  static bool _isWidgetType(DartType type) => isTypeNamed(type, 'Widget');

  /// The most-derived supertype of [type] the isolated file can name.
  ///
  /// "Most derived" is approximated by supertype-chain length, which orders
  /// `StatelessWidget` above `Widget` as intended. Ties break by name so the
  /// output is stable.
  String? _nearestNameableSupertype(
    InterfaceType type,
    Set<String> available,
  ) => _nearestNameableSupertypeType(type, available)?.element.name;

  /// [_nearestNameableSupertype], before the name is taken off it.
  InterfaceType? _nearestNameableSupertypeType(
    InterfaceType type,
    Set<String> available,
  ) {
    InterfaceType? best;
    for (final supertype in type.allSupertypes) {
      final element = supertype.element;
      final name = element.name;
      if (name == null || name == 'Object') continue;
      if (!_isNameable(element, available)) continue;
      if (best == null) {
        best = supertype;
        continue;
      }
      final delta =
          supertype.element.allSupertypes.length -
          best.element.allSupertypes.length;
      if (delta > 0 || (delta == 0 && name.compareTo(best.element.name!) < 0)) {
        best = supertype;
      }
    }
    // Type arguments are dropped by the caller: they may name types the file
    // cannot, and a raw type is assignable wherever the parameterised one was.
    return best;
  }

  String _withNullability(String rendered, DartType type) =>
      type.nullabilitySuffix == NullabilitySuffix.question
      ? _optional(rendered)
      : rendered;

  /// Makes a rendered type usable for a binding with no initialiser.
  String _optional(String type) =>
      (type == 'dynamic' || type == 'void' || type.endsWith('?'))
      ? type
      : '$type?';

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  Set<String> _typeParameterNames(List<TypeParameterElement> parameters) => {
    for (final p in parameters)
      if (p.name case final String name)
        if (_isIdentifier(name)) name,
  };

  String _renderTypeParams(Set<String> names) =>
      names.isEmpty ? '' : '<${names.join(', ')}>';

  static String? _libraryUri(Element element) {
    try {
      return element.library?.identifier;
    } catch (_) {
      return null;
    }
  }

  static final RegExp _identifier = RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$');

  static bool _isIdentifier(String name) => _identifier.hasMatch(name);
}
