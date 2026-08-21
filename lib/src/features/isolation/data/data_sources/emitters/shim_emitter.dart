import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

/// Emits declaration-only stand-ins for symbols the transplant cannot inline.
///
/// Two buckets reach here. Repo-local declarations that produce no UI, meaning
/// models, services, and theme or constant holders, are skipped by the filter in
/// the transplant's cross-file loop. Third-party declarations are dropped
/// earlier still, by the import gate in `dependency_extractor_visitor.dart`.
/// Either way the isolated file ends up referencing a name nothing declares,
/// which is an error-severity diagnostic, and `spm analyze` skips any file that
/// carries one. Output that the analyzer refuses to read is of no use to the
/// tool that produced it.
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
/// A shimmed widget has an empty `build`. Analyzing the original project walks
/// the real one, because `tree_extractor` recurses into custom child widgets'
/// build bodies and into widget-returning helpers, so an isolated scope that
/// instantiates a shimmed widget reports a smaller tree than the same scope
/// measured in place. Repo-local declarations avoid this by being inlined whole
/// whenever they can produce UI (see `_declaresUiMember` in the transplant).
/// Third-party widgets have no such escape, so the difference is real: a shim
/// makes the file analyzable, which is not the same as making it measure
/// identically.
class ShimEmitter {
  /// [alreadyDeclared] is the live set of names the isolated file declares by
  /// inlining. It is read at [render] time, not at [request] time, because
  /// inlining and shim requests interleave: a name requested early may still
  /// be inlined later, and the inlined declaration always wins.
  ShimEmitter(this._alreadyDeclared);

  final Set<String> _alreadyDeclared;

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
  /// accessors for a type the scope touches twice, and `vector_math`'s
  /// `Vector3` alone runs past four hundred lines.
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
    final header = StringBuffer();
    final keyword = element is MixinElement ? 'mixin' : 'class';
    header.write('$keyword ${element.name}${_renderTypeParams(typeParams)}');

    // Widget-ness is the one property that has to survive. Collapsing every
    // widget to `StatelessWidget` keeps `Widget` in the resolved chain while
    // leaving exactly one abstract member to satisfy. A `StatefulWidget` base
    // would demand a `createState` returning a `State` the shim cannot supply.
    final isWidget = _hasSupertypeNamed(element, 'Widget');
    if (isWidget && element is! MixinElement) {
      header.write(' extends StatelessWidget');
    }

    final members = <String>[];
    if (element is! MixinElement) {
      for (final ctor in _constructorsFor(element, name)) {
        final rendered = _renderConstructor(
          ctor,
          element,
          available,
          typeParams,
          isWidget: isWidget,
        );
        if (rendered != null) members.add(rendered);
      }
    }
    if (isWidget && element is! MixinElement) {
      members.add(
        '  @override\n'
        '  Widget build(BuildContext context) => const SizedBox.shrink();',
      );
    }
    members.addAll(
      _renderMembers(
        element,
        name,
        available,
        typeParams,
        skip: isWidget ? const {'build'} : const {},
      ),
    );

    if (members.isEmpty) return '$header {}';
    return '$header {\n${members.join('\n')}\n}';
  }

  String _renderExtension(
    ExtensionElement element,
    String name,
    Set<String> available,
  ) {
    final typeParams = _typeParameterNames(element.typeParameters);
    final on = _renderType(element.extendedType, available, typeParams);
    final members = _renderMembers(element, name, available, typeParams);
    final header = 'extension $name${_renderTypeParams(typeParams)} on $on';
    if (members.isEmpty) return '$header {}';
    return '$header {\n${members.join('\n')}\n}';
  }

  /// The most members a type may declare and still have its whole surface
  /// rendered.
  ///
  /// Referenced-only was too little and everything was too much. A stub built
  /// from references alone carries whichever members the traversal happened to
  /// reach, so `removeListener` lands and `addListener` does not, and the file
  /// fails at the one call site the shim forgot. Rendering everything is what
  /// the referenced-only rule was written to avoid: `vector_math`'s `Vector3`
  /// runs past four hundred lines. A small type costs little to render whole,
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

  /// The constructors to emit for [owner].
  ///
  /// Every constructor for a type whose whole surface is rendered, and
  /// otherwise only the ones a reference actually reached, so a value object
  /// with eight named constructors contributes the one that was called. A type
  /// used only as an annotation reaches none, and the implicit default
  /// constructor the shim gets is enough.
  List<ConstructorElement> _constructorsFor(
    InterfaceElement owner,
    String name,
  ) {
    if (_rendersFullSurface(owner, name)) return owner.constructors;
    final requested = _members[name];
    if (requested == null) return const [];
    return requested.values.whereType<ConstructorElement>().toList();
  }

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
  List<String> _renderMembers(
    InstanceElement owner,
    String name,
    Set<String> available,
    Set<String> typeParams, {
    Set<String> skip = const {},
  }) {
    final out = <String>[];
    // Two sources can name one member: the declared surface and the recorded
    // references, which may hold the inherited element of the same name. The
    // second spelling would be a duplicate declaration, so keys are tracked as
    // they are emitted. A field claims both its getter and its setter key,
    // since it renders as the pair.
    final emitted = <String>{};

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
        final type = _renderType(member.returnType, available, typeParams);
        final prefix = member.isStatic ? '  static ' : '  ';
        out.add('$prefix$type get $memberName => throw UnimplementedError();');
        return;
      }
      if (member is SetterElement) {
        final valueType = member.formalParameters.isEmpty
            ? 'dynamic'
            : _renderType(
                member.formalParameters.first.type,
                available,
                typeParams,
              );
        final prefix = member.isStatic ? '  static ' : '  ';
        out.add('${prefix}set $memberName(${_optional(valueType)} _) {}');
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
    return out;
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
    final type = _renderType(field.type, available, typeParams);
    if (field.isStatic && field.isConst) {
      return ['  static const dynamic $name = null;'];
    }
    final prefix = field.isStatic ? '  static ' : '  ';
    final out = ['$prefix$type get $name => throw UnimplementedError();'];
    if (field.setter != null && !field.isFinal && !field.isConst) {
      out.add('${prefix}set $name(${_optional(type)} _) {}');
    }
    return out;
  }

  String _renderTopLevelVariable(
    TopLevelVariableElement element,
    Set<String> available,
  ) {
    final type = _renderType(element.type, available, const {});
    // A `const` holder is routinely read from a const context (`const
    // TextStyle(color: AppColors.primary)`), so the stand-in has to be const
    // too or the use site becomes INVALID_CONSTANT. `null` typed `dynamic` is
    // a valid constant and assignable wherever the real value was.
    if (element.isConst) return 'const dynamic ${element.name} = null;';
    return 'late $type ${element.name};';
  }

  String? _renderConstructor(
    ConstructorElement ctor,
    InterfaceElement owner,
    Set<String> available,
    Set<String> typeParams, {
    required bool isWidget,
  }) {
    final ctorName = ctor.name;
    // The unnamed constructor is `new` in the element model of analyzer >= 13.
    final suffix = (ctorName == null || ctorName.isEmpty || ctorName == 'new')
        ? ''
        : '.$ctorName';
    if (suffix.isNotEmpty && !_isIdentifier(ctorName!)) return null;

    final params = _renderParameters(
      ctor.formalParameters,
      available,
      typeParams,
      // `StatelessWidget` supplies `key`, so a shim widget forwards it rather
      // than shadowing it with a parameter of its own.
      superFormals: isWidget ? const {'key'} : const {},
    );
    // A const constructor may not have a body; the shim never needs one, since
    // all of its state is accessors.
    final constPrefix = ctor.isConst ? 'const ' : '';
    return '  $constPrefix${owner.name}$suffix($params);';
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
    final returnType = _renderType(
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
    final signature =
        '$staticPrefix$returnType $name'
        '${_renderTypeParams(ownTypeParams)}($params)';
    if (returnType == 'void') return '$signature {}';
    return '$signature => throw UnimplementedError();';
  }

  /// Renders a parameter list, mirroring the real element's parameter kinds.
  ///
  /// `required` is dropped from named parameters: a shim is never constructed
  /// by anything but the transplanted code, and a requirement it does not
  /// satisfy would be a fresh error rather than a fixed one. Default values are
  /// dropped for the same reason, since the real one may reference a symbol the
  /// isolated file does not have. That is why every optional parameter is
  /// rendered nullable.
  String _renderParameters(
    List<FormalParameterElement> parameters,
    Set<String> available,
    Set<String> typeParams, {
    Set<String> superFormals = const {},
  }) {
    final positional = <String>[];
    final optionalPositional = <String>[];
    final named = <String>[];

    for (final p in parameters) {
      final name = p.name;
      if (name == null || name.isEmpty || !_isIdentifier(name)) continue;
      if (p.isNamed && superFormals.contains(name)) {
        named.add('super.$name');
        continue;
      }
      final type = _renderType(p.type, available, typeParams);
      if (p.isRequiredPositional) {
        positional.add('$type $name');
      } else if (p.isOptionalPositional) {
        optionalPositional.add('${_optional(type)} $name');
      } else {
        named.add('${_optional(type)} $name');
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

  /// The most-derived supertype of [type] the isolated file can name.
  ///
  /// "Most derived" is approximated by supertype-chain length, which orders
  /// `StatelessWidget` above `Widget` as intended. Ties break by name so the
  /// output is stable.
  String? _nearestNameableSupertype(InterfaceType type, Set<String> available) {
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
    if (best == null) return null;
    // Type arguments are dropped: they may name types the file cannot, and a
    // raw type is assignable wherever the parameterised one was.
    return best.element.name;
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

  static bool _hasSupertypeNamed(InterfaceElement element, String name) {
    if (element.name == name) return true;
    return element.allSupertypes.any((t) => t.element.name == name);
  }

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
